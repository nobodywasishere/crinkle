require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe "FileChangeType enum" do
    it "has correct values" do
      Crinkle::LSP::FileChangeType::Created.value.should eq 1
      Crinkle::LSP::FileChangeType::Changed.value.should eq 2
      Crinkle::LSP::FileChangeType::Deleted.value.should eq 3
    end
  end
end
