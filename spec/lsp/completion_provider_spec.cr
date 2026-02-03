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

    it "provides filter completions after pipe with trailing whitespace" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      template = "{% set foo = 1 %}\n\n{{ foo | }}"
      inference.analyze("file:///test.j2", template)

      completions = provider.completions(
        "file:///test.j2",
        template,
        Crinkle::LSP::Position.new(2, 8)
      )

      labels = completions.map(&.label)
      labels.should contain "default"
      labels.should contain "upper"
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

    it "ranks completions using custom schema types" do
      tmp_root = ENV["TMPDIR"]? || "/tmp"
      dir = File.join(tmp_root, "crinkle-lsp-#{Time.utc.to_unix_ms}-#{Random.rand(1000)}")
      Dir.mkdir(dir)

      begin
        schema_dir = File.join(dir, ".crinkle")
        Dir.mkdir(schema_dir)
        schema_path = File.join(schema_dir, "schema.json")

        schema = Crinkle::Schema::Registry.new
        schema.register_template(
          Crinkle::Schema::TemplateContextSchema.new(
            path: "page.j2",
            context: {"user" => "User"}
          )
        )
        schema.register_callable(
          Crinkle::Schema::CallableSchema.new(
            class_name: "User",
            methods: {
              "name" => Crinkle::Schema::MethodSchema.new(name: "name", returns: "String"),
            }
          )
        )
        File.write(schema_path, schema.to_json)

        config = Crinkle::LSP::Config.new(template_paths: ["."])
        schema_provider = Crinkle::LSP::SchemaProvider.new(config, dir)
        inference = Crinkle::LSP::InferenceEngine.new(config, dir, schema_provider.custom_schema || Crinkle::Schema.registry)
        provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference, dir)

        uri = "file://#{File.join(dir, "page.j2")}"
        inference.analyze(uri, "{{ user.name }}")

        var_completions = provider.completions(uri, "{{ ", Crinkle::LSP::Position.new(0, 3))
        user_item = var_completions.find(&.label.==("user"))
        user_item.should_not be_nil
        user_item = user_item.as(Crinkle::LSP::CompletionItem)
        user_item.detail.should_not be_nil
        user_item.detail.try(&.includes?("User")).should be_true
        user_item.sort_text.should_not be_nil
        user_item.sort_text.try(&.starts_with?("0")).should be_true

        prop_completions = provider.completions(uri, "{{ user.", Crinkle::LSP::Position.new(0, 8))
        name_item = prop_completions.find(&.label.==("name"))
        name_item.should_not be_nil
        name_item = name_item.as(Crinkle::LSP::CompletionItem)
        name_item.detail.should_not be_nil
        name_item.detail.try(&.includes?("method")).should be_true
        name_item.detail.try(&.includes?("String")).should be_true
        name_item.sort_text.should_not be_nil
        name_item.sort_text.try(&.starts_with?("0")).should be_true
      ensure
        if Dir.exists?(dir)
          Dir.each_child(dir) do |entry|
            path = File.join(dir, entry)
            if File.directory?(path)
              Dir.each_child(path) do |child|
                child_path = File.join(path, child)
                File.delete(child_path) if File.file?(child_path)
              end
              Dir.delete(path)
            else
              File.delete(path) if File.file?(path)
            end
          end
          Dir.delete(dir)
        end
      end
    end
  end
end
