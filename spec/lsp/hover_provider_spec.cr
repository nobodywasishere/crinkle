require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::HoverProvider do
    it "provides hover for filters" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "upper" filter
      hover = provider.hover("file:///test.j2", "{{ name | upper }}", Crinkle::LSP::Position.new(0, 11))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "upper"
      end
    end

    it "provides hover for tests" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "defined" test
      hover = provider.hover("file:///test.j2", "{% if name is defined %}", Crinkle::LSP::Position.new(0, 17))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "defined"
      end
    end

    it "provides hover for functions" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "range" function
      hover = provider.hover("file:///test.j2", "{{ range(10) }}", Crinkle::LSP::Position.new(0, 5))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "range"
      end
    end

    it "provides hover for variables from set statements" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      template = "{% set greeting = 'Hello' %}{{ greeting }}"
      inference.analyze("file:///test.j2", template)

      # Position on "greeting" in the output
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 33))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "greeting"
        h.contents.value.should contain "assigned variable"
        h.contents.value.should contain "Type: `String`"
      end
    end

    it "provides hover for variables from for loops" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      template = "{% for item in items %}{{ item }}{% endfor %}"
      inference.analyze("file:///test.j2", template)

      # Position on "item" in the output
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 27))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "item"
        h.contents.value.should contain "loop variable"
      end
    end

    it "provides hover for macros" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      template = "{% macro button(text, style='primary') %}{% endmacro %}{{ button('Click') }}"
      inference.analyze("file:///test.j2", template)

      # Position on "button" in the call
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 59))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "button"
        h.contents.value.should contain "text"
      end
    end

    it "provides hover for blocks" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      template = "{% block content %}Hello{% endblock %}"
      inference.analyze("file:///test.j2", template)

      # Position on "content" block name
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 12))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "block"
        h.contents.value.should contain "content"
      end
    end

    it "provides hover for tags" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "for" tag
      hover = provider.hover("file:///test.j2", "{% for item in items %}{% endfor %}", Crinkle::LSP::Position.new(0, 4))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "for"
        h.contents.value.should contain "block tag"
      end
    end

    it "provides hover for if tag" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "if" tag
      hover = provider.hover("file:///test.j2", "{% if true %}yes{% endif %}", Crinkle::LSP::Position.new(0, 4))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "if"
        h.contents.value.should contain "Conditional"
      end
    end

    it "returns nil for text outside Jinja blocks" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on plain text
      hover = provider.hover("file:///test.j2", "Hello {{ name }}", Crinkle::LSP::Position.new(0, 2))

      hover.should be_nil
    end

    it "includes hover info for context variables" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Template with only context variable (inferred from usage, not defined)
      template = "{{ user.name }}"
      inference.analyze("file:///test.j2", template)

      # Position on "user" - a context variable
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 5))

      hover.should_not be_nil
      hover.try do |result|
        contents = result.contents.as(Crinkle::LSP::MarkupContent).value
        contents.should contain("**user** - context variable")
        contents.should contain("Type: `Any`")
      end
    end
  end
end
