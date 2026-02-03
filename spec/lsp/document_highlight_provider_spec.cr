require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::DocumentHighlightProvider do
    it "highlights variable occurrences" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DocumentHighlightProvider.new(inference)

      template = "{% set name = 'Alice' %}{{ name }} Hello {{ name }}"
      uri = "file:///test.j2"
      inference.analyze(uri, template)

      # Position on first "name" usage in output
      highlights = provider.highlights(uri, template, Crinkle::LSP::Position.new(0, 28))

      # Should find: definition + 2 usages
      highlights.size.should be >= 2
    end

    it "highlights macro definition and calls" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DocumentHighlightProvider.new(inference)

      template = "{% macro btn(t) %}{{ t }}{% endmacro %}{{ btn('A') }}"
      uri = "file:///test.j2"
      inference.analyze(uri, template)

      # Position on "btn" in call
      highlights = provider.highlights(uri, template, Crinkle::LSP::Position.new(0, 42))

      # Should find definition and call
      highlights.size.should be >= 1
    end

    it "returns empty for plain text" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DocumentHighlightProvider.new(inference)

      template = "Hello World"
      uri = "file:///test.j2"

      highlights = provider.highlights(uri, template, Crinkle::LSP::Position.new(0, 3))

      highlights.should be_empty
    end
  end
end
