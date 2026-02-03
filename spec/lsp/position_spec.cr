require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::Position do
    it "serializes to JSON" do
      pos = Crinkle::LSP::Position.new(10, 5)
      json = pos.to_json
      parsed = JSON.parse(json)

      parsed["line"].should eq 10
      parsed["character"].should eq 5
    end

    it "deserializes from JSON" do
      json = %({"line": 10, "character": 5})
      pos = Crinkle::LSP::Position.from_json(json)

      pos.line.should eq 10
      pos.character.should eq 5
    end
  end
end
