require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::SymbolProvider do
    it "returns empty array for plain text" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "Hello World"

      symbols = provider.document_symbols(template)

      symbols.should be_empty
    end

    it "finds block symbols" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% block content %}Hello{% endblock %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should eq "content"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Class
    end

    it "finds macro symbols with params" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% macro button(text, style) %}{{ text }}{% endmacro %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should eq "button(text, style)"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Method
    end

    it "finds set variable symbols" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% set count = 10 %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should eq "count"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Variable
    end

    it "finds for loop symbols" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% for item in items %}{{ item }}{% endfor %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should start_with "for item in"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Struct
    end

    it "finds if statement symbols" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% if x > 0 %}positive{% endif %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should start_with "if"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Boolean
    end

    it "builds nested symbol hierarchy" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% block content %}{% for item in items %}{{ item }}{% endfor %}{% endblock %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should eq "content"
      if children = symbols[0].children
        children.size.should eq 1
        children.first.name.should start_with "for item"
      else
        fail "Expected children to not be nil"
      end
    end

    it "handles parse errors gracefully" do
      provider = Crinkle::LSP::SymbolProvider.new
      # Use completely invalid syntax that will cause parser to fail
      template = "{% %} {{ }}"

      symbols = provider.document_symbols(template)

      # Should return empty or partial results without crashing
      symbols.size.should be <= 1
    end
  end
end
