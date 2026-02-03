require "../spec_helper"

describe Crinkle::LSP do
  describe "Cross-file macro import resolution" do
    it "resolves imported macro for go-to-definition" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      # foo.html.j2 defines the macro (single line for predictable span)
      foo_template = %({% macro bar() %}{% endmacro %})
      foo_uri = "file:///templates/foo.html.j2"

      # baz.html.j2 imports and uses the macro
      # Template: {% from "foo.html.j2" import bar %}{{ bar() }}
      # Positions: 0-34 = import statement, 35-45 = {{ bar() }}
      # "bar" in call is at positions 38-40
      baz_template = %({% from "foo.html.j2" import bar %}{{ bar() }})
      baz_uri = "file:///templates/baz.html.j2"

      # Analyze both templates
      inference.analyze(foo_uri, foo_template)
      inference.analyze(baz_uri, baz_template)

      # Position on "bar" in the call ({{ bar() }}) - "bar" is at chars 38-40
      location = provider.definition(baz_uri, baz_template, Crinkle::LSP::Position.new(0, 39))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq foo_uri
        # Should point to the macro definition in foo.html.j2
        loc.range.start.line.should eq 0
      end
    end

    it "finds imported macro via inference engine" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)

      # foo.html.j2 defines the macro
      foo_template = %({% macro bar() %}{% endmacro %})
      foo_uri = "file:///templates/foo.html.j2"

      # baz.html.j2 imports the macro
      baz_template = %({% from "foo.html.j2" import bar %})
      baz_uri = "file:///templates/baz.html.j2"

      # Analyze both templates
      inference.analyze(foo_uri, foo_template)
      inference.analyze(baz_uri, baz_template)

      # Macro should be accessible from baz via cross-template resolution
      macro_info = inference.macro_info(baz_uri, "bar")
      macro_info.should_not be_nil
      if info = macro_info
        info.name.should eq "bar"
        info.definition_span.should_not be_nil
      end
    end

    it "reports unknown function error for unimported macro" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      # Pass the schema registry to enable UnknownFunction rule
      analyzer = Crinkle::LSP::Analyzer.new(Crinkle::Schema.registry, inference)

      # baz.html.j2 tries to call bar() without importing it
      baz_template = "{{ bar() }}"
      baz_uri = "file:///templates/baz.html.j2"

      inference.analyze(baz_uri, baz_template)
      issues = analyzer.analyze(baz_template, baz_uri)

      # Should have an unknown function error
      unknown_func_issues = issues.select { |i| i.id == "Lint/UnknownFunction" }
      unknown_func_issues.size.should eq 1
      unknown_func_issues.first.message.should contain "Unknown function 'bar'"
    end

    it "does not report unknown function for properly imported macro (from...import)" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      # Pass the schema registry to enable UnknownFunction rule
      analyzer = Crinkle::LSP::Analyzer.new(Crinkle::Schema.registry, inference)

      # baz.html.j2 imports bar using from...import syntax
      baz_template = %({% from "foo.html.j2" import bar %}{{ bar() }})
      baz_uri = "file:///templates/baz.html.j2"

      inference.analyze(baz_uri, baz_template)
      issues = analyzer.analyze(baz_template, baz_uri)

      # Should NOT have an unknown function error for bar
      unknown_func_issues = issues.select { |i| i.id == "Lint/UnknownFunction" && i.message.includes?("bar") }
      unknown_func_issues.should be_empty
    end

    it "does not report unknown function for macro from import (cross-template resolution)" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      analyzer = Crinkle::LSP::Analyzer.new(Crinkle::Schema.registry, inference)

      # foo.html.j2 defines the macro
      foo_template = %({% macro bar() %}content{% endmacro %})
      foo_uri = "file:///templates/foo.html.j2"

      # baz.html.j2 uses {% import %} syntax (not {% from ... import %})
      baz_template = %({% import "foo.html.j2" %}{{ bar() }})
      baz_uri = "file:///templates/baz.html.j2"

      # Analyze both templates
      inference.analyze(foo_uri, foo_template)
      inference.analyze(baz_uri, baz_template)
      issues = analyzer.analyze(baz_template, baz_uri)

      # Should NOT have an unknown function error for bar
      # because the analyzer uses inference engine's cross-template resolution
      unknown_func_issues = issues.select { |i| i.id == "Lint/UnknownFunction" && i.message.includes?("bar") }
      unknown_func_issues.should be_empty
    end

    it "provides hover info for imported macro call" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # foo.html.j2 defines the macro with params
      foo_template = %({% macro bar(text, style="default") %}{{ text }}{% endmacro %})
      foo_uri = "file:///templates/foo.html.j2"

      # baz.html.j2 imports and uses the macro
      baz_template = %({% from "foo.html.j2" import bar %}{{ bar("hello") }})
      baz_uri = "file:///templates/baz.html.j2"

      # Analyze both templates
      inference.analyze(foo_uri, foo_template)
      inference.analyze(baz_uri, baz_template)

      # Position on "bar" in the call - "bar" is at chars 38-40
      hover = provider.hover(baz_uri, baz_template, Crinkle::LSP::Position.new(0, 39))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "bar"
        h.contents.value.should contain "text"
      end
    end

    it "finds macro references within same file" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      # Template with macro definition and call in same file
      template = %({% macro bar() %}content{% endmacro %}{{ bar() }})
      uri = "file:///templates/test.html.j2"

      # Register document
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Find references to "bar" from the definition - "bar" in macro def is at char 9-11
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 10))

      # Should find the definition and the call site
      locations.size.should eq 2
      locations.all? { |loc| loc.uri == uri }.should be_true
    end

    it "tracks import relationships correctly" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)

      # baz.html.j2 has from...import relationship
      baz_template = %({% from "foo.html.j2" import bar, baz as qux %})
      baz_uri = "file:///templates/baz.html.j2"

      inference.analyze(baz_uri, baz_template)

      # The inference engine should track the relationship
      # (extends_path returns first relationship, which should include our import)
      extends = inference.extends_path(baz_uri)
      extends.should eq "foo.html.j2"
    end

    it "auto-analyzes imported templates from disk" do
      # Create temporary template files
      temp_dir = File.tempname("crinkle_test")
      Dir.mkdir_p(temp_dir)

      begin
        # Write foo.html.j2 with a macro
        foo_path = File.join(temp_dir, "foo.html.j2")
        File.write(foo_path, %({% macro bar(text) %}{{ text }}{% endmacro %}))

        # Write baz.html.j2 that imports foo
        baz_path = File.join(temp_dir, "baz.html.j2")
        baz_content = %({% from "foo.html.j2" import bar %}{{ bar("hello") }})
        File.write(baz_path, baz_content)

        # Create inference engine with root_path set
        config = Crinkle::LSP::Config.new
        inference = Crinkle::LSP::InferenceEngine.new(config, temp_dir)

        # Analyze only baz.html.j2 - foo.html.j2 should be auto-analyzed
        baz_uri = "file://#{baz_path}"
        inference.analyze(baz_uri, baz_content)

        # The macro from foo.html.j2 should be accessible via cross-template resolution
        macro_info = inference.macro_info(baz_uri, "bar")
        macro_info.should_not be_nil
        if info = macro_info
          info.name.should eq "bar"
          info.params.should eq ["text"]
        end
      ensure
        # Clean up temp files
        FileUtils.rm_rf(temp_dir)
      end
    end
  end
end
