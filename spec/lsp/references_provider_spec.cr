require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::ReferencesProvider do
    it "finds all references to a variable from set statement" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{% set greeting = 'Hello' %}{{ greeting }} {{ greeting }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on first "greeting" usage
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 33))

      # Should find: definition in set, and two usages in output
      locations.size.should eq 3
      locations.all? { |loc| loc.uri == uri }.should be_true
    end

    it "finds references to for loop variable" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{% for item in items %}{{ item.name }} - {{ item.id }}{% endfor %}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on "item" in the for loop
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 9))

      # Should find: definition in for loop, and two usages
      locations.size.should eq 3
    end

    it "can exclude declaration from results" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{% set x = 1 %}{{ x }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # With declaration - position on the 'x' in output (char 18)
      with_decl = provider.references(uri, template, Crinkle::LSP::Position.new(0, 18), include_declaration: true)
      # Without declaration
      without_decl = provider.references(uri, template, Crinkle::LSP::Position.new(0, 18), include_declaration: false)

      with_decl.size.should eq 2    # set + usage
      without_decl.size.should eq 1 # only usage
    end

    it "finds macro definition and call sites" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{% macro btn(t) %}{{ t }}{% endmacro %}{{ btn('A') }}{{ btn('B') }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on "btn" in first call
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 42))

      # Should find: macro definition, two call sites
      locations.size.should eq 3
    end

    it "finds block references across templates" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      base_template = "{% block content %}Base content{% endblock %}"
      child_template = "{% extends 'base.j2' %}{% block content %}Child content{% endblock %}"

      base_uri = "file:///base.j2"
      child_uri = "file:///child.j2"

      documents.open(base_uri, "jinja2", base_template, 1)
      documents.open(child_uri, "jinja2", child_template, 1)
      inference.analyze(base_uri, base_template)
      inference.analyze(child_uri, child_template)

      # Position on "content" in child template
      locations = provider.references(child_uri, child_template, Crinkle::LSP::Position.new(0, 33))

      # Should find both block definitions
      locations.size.should eq 2
      locations.map(&.uri).should contain base_uri
      locations.map(&.uri).should contain child_uri
    end

    it "returns empty array for position on plain text" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "Hello World"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)

      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 3))

      locations.should be_empty
    end

    it "returns empty array for filters (not referenceable)" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{{ name | upper }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on "upper" filter - filters are not referenceable
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 12))

      locations.should be_empty
    end
  end
end
