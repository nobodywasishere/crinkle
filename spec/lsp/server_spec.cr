require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::Server do
    it "starts uninitialized" do
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, IO::Memory.new)
      server = Crinkle::LSP::Server.new(transport)

      server.initialized?.should be_false
      server.shutdown_requested?.should be_false
    end

    it "has empty document store initially" do
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, IO::Memory.new)
      server = Crinkle::LSP::Server.new(transport)

      server.documents.size.should eq 0
    end
  end
end
