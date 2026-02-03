require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::MacroInfo do
    it "generates signature without defaults" do
      info = Crinkle::LSP::MacroInfo.new("button", ["text", "style"])

      info.signature.should eq "button(text, style)"
    end

    it "generates signature with defaults" do
      defaults = {"style" => %("primary")}
      info = Crinkle::LSP::MacroInfo.new("button", ["text", "style"], defaults)

      info.signature.should eq %(button(text, style="primary"))
    end
  end
end
