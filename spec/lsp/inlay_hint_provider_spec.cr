require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::InlayHintProvider do
    it "provides parameter hints for macro calls" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      provider = Crinkle::LSP::InlayHintProvider.new(inference, schema_provider)

      template = %({% macro button(text, style) %}{{ text }}{% endmacro %}{{ button("Click", "primary") }})
      uri = "file:///test.j2"
      inference.analyze(uri, template)

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 0),
        Crinkle::LSP::Position.new(0, 100)
      )
      hints = provider.inlay_hints(uri, template, range)

      # Should have hints for "text:" and "style:"
      hints.size.should eq 2
      labels = hints.map(&.label)
      labels.should contain "text:"
      labels.should contain "style:"
    end

    it "returns empty for templates without macro calls" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      provider = Crinkle::LSP::InlayHintProvider.new(inference, schema_provider)

      template = "{{ name }}"
      uri = "file:///test.j2"
      inference.analyze(uri, template)

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 0),
        Crinkle::LSP::Position.new(0, 20)
      )
      hints = provider.inlay_hints(uri, template, range)

      hints.should be_empty
    end

    it "skips hint when argument name matches parameter" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      provider = Crinkle::LSP::InlayHintProvider.new(inference, schema_provider)

      # When passing `text` to param named `text`, no hint needed
      template = %({% macro greet(text) %}{{ text }}{% endmacro %}{% set text = "hi" %}{{ greet(text) }})
      uri = "file:///test.j2"
      inference.analyze(uri, template)

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 0),
        Crinkle::LSP::Position.new(0, 100)
      )
      hints = provider.inlay_hints(uri, template, range)

      # Should have no parameter hints since arg matches param
      hints.select { |hint| hint.kind == Crinkle::LSP::InlayHintKind::Parameter }.should be_empty
    end

    it "provides parameter hints for filter calls" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      provider = Crinkle::LSP::InlayHintProvider.new(inference, schema_provider)

      # The 'default' filter takes a 'fallback' parameter
      template = %({{ value|default(42) }})
      uri = "file:///test.j2"
      inference.analyze(uri, template)

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 0),
        Crinkle::LSP::Position.new(0, 50)
      )
      hints = provider.inlay_hints(uri, template, range)

      # Should have hint for the default_value parameter
      hints.size.should eq 1
      hints[0].label.should eq "default_value:"
    end

    it "provides parameter hints for test calls" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      provider = Crinkle::LSP::InlayHintProvider.new(inference, schema_provider)

      # The 'divisibleby' test takes a 'num' parameter
      template = %({% if num is divisibleby(3) %}yes{% endif %})
      uri = "file:///test.j2"
      inference.analyze(uri, template)

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 0),
        Crinkle::LSP::Position.new(0, 50)
      )
      hints = provider.inlay_hints(uri, template, range)

      # Should have hint for the num parameter
      hints.size.should eq 1
      hints[0].label.should eq "num:"
    end

    it "provides inferred type hints for set variables" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      provider = Crinkle::LSP::InlayHintProvider.new(inference, schema_provider)

      template = %({% set foo = 1 %}{% set bar = "hi" %})
      uri = "file:///test.j2"
      inference.analyze(uri, template)

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 0),
        Crinkle::LSP::Position.new(0, 100)
      )
      hints = provider.inlay_hints(uri, template, range)

      labels = hints.map(&.label)
      labels.should contain ": Int64"
      labels.should contain ": String"

      kinds = hints.map(&.kind)
      kinds.all? { |kind| kind == Crinkle::LSP::InlayHintKind::Type }.should be_true
    end
  end
end
