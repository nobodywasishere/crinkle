require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::InitializeResult do
    it "includes server capabilities" do
      caps = Crinkle::LSP::ServerCapabilities.new(
        text_document_sync: Crinkle::LSP::TextDocumentSyncOptions.new(
          open_close: true,
          change: 1
        )
      )
      result = Crinkle::LSP::InitializeResult.new(
        capabilities: caps,
        server_info: Crinkle::LSP::ServerInfo.new(name: "crinkle-lsp", version: "0.1.0")
      )

      json = result.to_json
      parsed = JSON.parse(json)

      parsed["capabilities"]["textDocumentSync"]["openClose"].should be_true
      parsed["capabilities"]["textDocumentSync"]["change"].should eq 1
      parsed["serverInfo"]["name"].should eq "crinkle-lsp"
      parsed["serverInfo"]["version"].should eq "0.1.0"
    end
  end
end
