require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::VariableInfo do
    it "stores variable information" do
      info = Crinkle::LSP::VariableInfo.new("item", Crinkle::LSP::VariableSource::ForLoop, "loop variable")

      info.name.should eq "item"
      info.source.should eq Crinkle::LSP::VariableSource::ForLoop
      info.detail.should eq "loop variable"
    end
  end
end
