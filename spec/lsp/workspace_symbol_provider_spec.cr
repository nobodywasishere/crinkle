require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::WorkspaceSymbolProvider do
    it "finds macros across analyzed templates" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::WorkspaceSymbolProvider.new(inference)

      # Analyze templates with macros
      inference.analyze("file:///a.j2", "{% macro button(text) %}{% endmacro %}")
      inference.analyze("file:///b.j2", "{% macro icon(name) %}{% endmacro %}")

      symbols = provider.symbols("button")

      symbols.size.should eq 1
      symbols[0].name.should eq "button"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Method
    end

    it "uses fuzzy matching" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::WorkspaceSymbolProvider.new(inference)

      inference.analyze("file:///a.j2", "{% macro render_button(text) %}{% endmacro %}")

      # Fuzzy search "btn" should match "render_button"
      symbols = provider.symbols("btn")

      symbols.size.should eq 1
      symbols[0].name.should eq "render_button"
    end

    it "returns empty for no matches" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::WorkspaceSymbolProvider.new(inference)

      inference.analyze("file:///a.j2", "{% macro button() %}{% endmacro %}")

      symbols = provider.symbols("xyz123nonexistent")

      symbols.should be_empty
    end
  end
end
