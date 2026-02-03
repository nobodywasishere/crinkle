require "../spec_helper"

describe Crinkle::LSP do
  describe "DefinitionProvider for variables, macros, and blocks" do
    it "provides definition for variables from set statements" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{% set greeting = 'Hello' %}{{ greeting }}"
      inference.analyze("file:///test.j2", template)

      # Position on "greeting" in the output
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 33))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq "file:///test.j2"
        # LSP uses 0-based lines, single-line template means line 0
        loc.range.start.line.should eq 0
      end
    end

    it "provides definition for variables from for loops" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{% for item in items %}{{ item }}{% endfor %}"
      inference.analyze("file:///test.j2", template)

      # Position on "item" in the output
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 27))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq "file:///test.j2"
        # LSP uses 0-based lines, single-line template means line 0
        loc.range.start.line.should eq 0
      end
    end

    it "provides definition for macros" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{% macro button(text) %}{{ text }}{% endmacro %}{{ button('Click') }}"
      inference.analyze("file:///test.j2", template)

      # Position on "button" in the call
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 52))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq "file:///test.j2"
        # LSP uses 0-based lines, single-line template means line 0
        loc.range.start.line.should eq 0
      end
    end

    it "provides definition for blocks" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{% block content %}Hello{% endblock %}"
      inference.analyze("file:///test.j2", template)

      # Position on "content" block name
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 12))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq "file:///test.j2"
        # LSP uses 0-based lines, single-line template means line 0
        loc.range.start.line.should eq 0
      end
    end

    it "returns nil for context variables without definition" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{{ user.name }}"
      inference.analyze("file:///test.j2", template)

      # Position on "user" - context variable has no definition span
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 5))

      # Context variables don't have definition spans, so should be nil
      location.should be_nil
    end

    it "returns nil for position on plain text" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "Hello {{ name }}"
      inference.analyze("file:///test.j2", template)

      # Position on plain text
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 2))

      location.should be_nil
    end
  end
end
