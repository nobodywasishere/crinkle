require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::CompletionProvider do
    it "provides variable completions in output context" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      # Analyze template to populate inference
      inference.analyze("file:///test.j2", "{% set greeting = 'Hi' %}{% for item in items %}{% endfor %}")

      # Request completions after {{
      completions = provider.completions(
        "file:///test.j2",
        "{{ ",
        Crinkle::LSP::Position.new(0, 3)
      )

      labels = completions.map(&.label)
      labels.should contain "greeting"
      labels.should contain "item"
      labels.should contain "items"
    end

    it "provides block completions after {% block" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      # Analyze template with blocks
      inference.analyze("file:///base.j2", "{% block header %}{% endblock %}{% block content %}{% endblock %}")

      # Request completions after {% block in child template
      completions = provider.completions(
        "file:///base.j2",
        "{% block ",
        Crinkle::LSP::Position.new(0, 9)
      )

      labels = completions.map(&.label)
      labels.should contain "header"
      labels.should contain "content"
    end

    it "provides macro completions after {% call" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      # Analyze template with macros
      inference.analyze("file:///test.j2", "{% macro button(text) %}{% endmacro %}{% macro icon(name) %}{% endmacro %}")

      # Request completions after {% call
      completions = provider.completions(
        "file:///test.j2",
        "{% call ",
        Crinkle::LSP::Position.new(0, 8)
      )

      labels = completions.map(&.label)
      labels.should contain "button"
      labels.should contain "icon"
    end

    it "filters completions by prefix" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      # Analyze template with multiple variables
      inference.analyze("file:///test.j2", "{% set user = 1 %}{% set username = 2 %}{% set product = 3 %}")

      # Request completions with prefix "us"
      completions = provider.completions(
        "file:///test.j2",
        "{{ us",
        Crinkle::LSP::Position.new(0, 5)
      )

      labels = completions.map(&.label)
      labels.should contain "user"
      labels.should contain "username"
      labels.should_not contain "product"
    end
  end
end
