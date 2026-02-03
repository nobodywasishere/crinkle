require "../spec_helper"

describe Crinkle::LSP do
  describe "InferenceEngine definition spans" do
    it "tracks variable definition spans from set statements" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% set greeting = 'Hello' %}"
      engine.analyze("file:///test.j2", template)

      var_info = engine.variable_info("file:///test.j2", "greeting")
      var_info.should_not be_nil
      if info = var_info
        info.definition_span.should_not be_nil
        info.source.should eq Crinkle::LSP::VariableSource::Set
      end
    end

    it "tracks variable definition spans from for loops" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% for item in items %}{{ item }}{% endfor %}"
      engine.analyze("file:///test.j2", template)

      var_info = engine.variable_info("file:///test.j2", "item")
      var_info.should_not be_nil
      if info = var_info
        info.definition_span.should_not be_nil
        info.source.should eq Crinkle::LSP::VariableSource::ForLoop
      end
    end

    it "tracks macro definition spans" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% macro button(text) %}{{ text }}{% endmacro %}"
      engine.analyze("file:///test.j2", template)

      macro_info = engine.macro_info("file:///test.j2", "button")
      macro_info.should_not be_nil
      if info = macro_info
        info.definition_span.should_not be_nil
        info.name.should eq "button"
      end
    end

    it "tracks block definition spans" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% block content %}Hello{% endblock %}"
      engine.analyze("file:///test.j2", template)

      block_info = engine.block_info("file:///test.j2", "content")
      block_info.should_not be_nil
      if info = block_info
        info.definition_span.should_not be_nil
        info.name.should eq "content"
        info.source_uri.should eq "file:///test.j2"
      end
    end

    it "returns nil for unknown variable" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% set greeting = 'Hello' %}"
      engine.analyze("file:///test.j2", template)

      var_info = engine.variable_info("file:///test.j2", "nonexistent")
      var_info.should be_nil
    end

    it "returns nil for unknown macro" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% macro button(text) %}{% endmacro %}"
      engine.analyze("file:///test.j2", template)

      macro_info = engine.macro_info("file:///test.j2", "nonexistent")
      macro_info.should be_nil
    end

    it "returns nil for unknown block" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% block content %}{% endblock %}"
      engine.analyze("file:///test.j2", template)

      block_info = engine.block_info("file:///test.j2", "nonexistent")
      block_info.should be_nil
    end

    it "blocks_info_for returns BlockInfo array" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% block header %}{% endblock %}{% block content %}{% endblock %}"
      engine.analyze("file:///test.j2", template)

      blocks = engine.blocks_info_for("file:///test.j2")
      blocks.size.should eq 2
      block_names = blocks.map(&.name)
      block_names.should contain "header"
      block_names.should contain "content"
    end
  end
end
