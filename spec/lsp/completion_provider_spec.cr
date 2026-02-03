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

    it "adds auto-import edits for workspace macros" do
      tmp_root = ENV["TMPDIR"]? || "/tmp"
      dir = File.join(tmp_root, "crinkle-lsp-#{Time.utc.to_unix_ms}-#{Random.rand(1000)}")
      Dir.mkdir(dir)

      begin
        macro_path = File.join(dir, "macros.j2")
        File.write(macro_path, "{% macro badge(text, style) %}{% endmacro %}")

        config = Crinkle::LSP::Config.new(template_paths: ["."])
        schema_provider = Crinkle::LSP::SchemaProvider.new(config, dir)
        inference = Crinkle::LSP::InferenceEngine.new(config, dir)
        workspace_index = Crinkle::LSP::WorkspaceIndex.new(config, dir)
        workspace_index.rebuild

        provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference, dir, workspace_index)

        uri = "file://#{File.join(dir, "page.j2")}"
        inference.analyze(uri, "{% call ")

        completions = provider.completions(uri, "{% call ", Crinkle::LSP::Position.new(0, 8))
        item = completions.find(&.label.==("badge"))
        item.should_not be_nil

        edits = item.as(Crinkle::LSP::CompletionItem).additional_text_edits
        edits.should_not be_nil
        edits = edits.as(Array(Crinkle::LSP::TextEdit))
        edits.size.should eq 1
        edits.first.new_text.should contain(%({% from "macros.j2" import badge %}))
      ensure
        Dir.each_child(dir) do |entry|
          path = File.join(dir, entry)
          File.delete(path) if File.file?(path)
        end
        Dir.delete(dir)
      end
    end
  end
end
