require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::InferenceEngine do
    it "extracts variables from for loops" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% for item in items %}{{ item.name }}{% endfor %}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "item"
      var_names.should contain "items"

      item_var = vars.find { |var| var.name == "item" }
      item_var.should_not be_nil
      item_var.try(&.source).should eq Crinkle::LSP::VariableSource::ForLoop
    end

    it "extracts variables from set statements" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% set greeting = 'Hello' %}{{ greeting }}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "greeting"

      greeting_var = vars.find { |var| var.name == "greeting" }
      greeting_var.try(&.source).should eq Crinkle::LSP::VariableSource::Set
    end

    it "extracts variables from macro parameters" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% macro button(text, style) %}{{ text }}{% endmacro %}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "text"
      var_names.should contain "style"

      text_var = vars.find { |var| var.name == "text" }
      text_var.try(&.source).should eq Crinkle::LSP::VariableSource::MacroParam
    end

    it "extracts context variables from expressions" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{{ user.name }} {{ product.price }}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "user"
      var_names.should contain "product"
    end

    it "extracts block names" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = <<-JINJA
        {% block header %}Header{% endblock %}
        {% block content %}Content{% endblock %}
        {% block footer %}Footer{% endblock %}
        JINJA
      engine.analyze("file:///test.j2", template)

      blocks = engine.blocks_for("file:///test.j2")
      blocks.should contain "header"
      blocks.should contain "content"
      blocks.should contain "footer"
    end

    it "extracts macro definitions" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = <<-JINJA
        {% macro button(text, style="primary") %}Button{% endmacro %}
        {% macro icon(name) %}Icon{% endmacro %}
        JINJA
      engine.analyze("file:///test.j2", template)

      macros = engine.macros_for("file:///test.j2")
      macro_names = macros.map(&.name)

      macro_names.should contain "button"
      macro_names.should contain "icon"

      button_macro = macros.find { |mac| mac.name == "button" }
      button_macro.should_not be_nil
      button_macro.try(&.params).should eq ["text", "style"]
      button_macro.try(&.signature).should eq %(button(text, style="primary"))
    end

    it "handles tuple unpacking in for loops" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% for key, value in items.items() %}{{ key }}: {{ value }}{% endfor %}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "key"
      var_names.should contain "value"
    end
  end
end
