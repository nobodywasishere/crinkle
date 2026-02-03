require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::Range do
    it "serializes to JSON" do
      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 0),
        Crinkle::LSP::Position.new(0, 10)
      )
      json = range.to_json
      parsed = JSON.parse(json)

      parsed["start"]["line"].should eq 0
      parsed["start"]["character"].should eq 0
      parsed["end"]["line"].should eq 0
      parsed["end"]["character"].should eq 10
    end
  end
end
