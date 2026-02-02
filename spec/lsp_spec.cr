require "./spec_helper"
require "../src/lsp/lsp"

describe Crinkle::LSP do
  describe Crinkle::LSP::Document do
    it "stores document content" do
      doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello {{ name }}", 1)
      doc.uri.should eq "file:///test.j2"
      doc.language_id.should eq "jinja2"
      doc.text.should eq "Hello {{ name }}"
      doc.version.should eq 1
    end

    it "updates document content" do
      doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello", 1)
      doc.update("Hello World", 2)
      doc.text.should eq "Hello World"
      doc.version.should eq 2
    end

    it "counts lines" do
      doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "line1\nline2\nline3", 1)
      doc.line_count.should eq 3
    end

    it "gets specific line" do
      doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "line1\nline2\nline3", 1)
      doc.line(0).should eq "line1"
      doc.line(1).should eq "line2"
      doc.line(2).should eq "line3"
      doc.line(3).should be_nil
    end
  end

  describe Crinkle::LSP::DocumentStore do
    it "opens and retrieves documents" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///test.j2", "jinja2", "content", 1)

      retrieved = store.get("file:///test.j2")
      retrieved.should_not be_nil
      retrieved.try(&.text).should eq "content"
    end

    it "updates documents" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///test.j2", "jinja2", "old content", 1)
      store.update("file:///test.j2", "new content", 2)

      doc = store.get("file:///test.j2")
      doc.try(&.text).should eq "new content"
      doc.try(&.version).should eq 2
    end

    it "closes documents" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///test.j2", "jinja2", "content", 1)
      store.close("file:///test.j2")

      store.get("file:///test.j2").should be_nil
      store.open?("file:///test.j2").should be_false
    end

    it "tracks open documents" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///a.j2", "jinja2", "a", 1)
      store.open("file:///b.j2", "jinja2", "b", 1)

      store.size.should eq 2
      store.uris.should contain "file:///a.j2"
      store.uris.should contain "file:///b.j2"
    end
  end

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

  describe Crinkle::LSP::Transport do
    it "writes response messages with Content-Length header" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_response(1_i64, JSON.parse(%({"success": true})))

      result = output.to_s
      result.should contain "Content-Length:"
      result.should contain "jsonrpc"
      result.should contain "result"
    end

    it "writes error responses" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_error(1_i64, -32601, "Method not found")

      result = output.to_s
      result.should contain "error"
      result.should contain "Method not found"
      result.should contain "-32601"
    end

    it "writes notifications" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_notification("textDocument/publishDiagnostics", JSON.parse(%({"uri": "file:///test.j2"})))

      result = output.to_s
      result.should contain "textDocument/publishDiagnostics"
      result.should_not contain "\"id\""
    end

    it "reads messages with Content-Length header" do
      message = %({"jsonrpc": "2.0", "id": 1, "method": "initialize"})
      input = IO::Memory.new("Content-Length: #{message.bytesize}\r\n\r\n#{message}")
      transport = Crinkle::LSP::Transport.new(input, IO::Memory.new)

      result = transport.read_message
      result.should_not be_nil
      result.try(&.["method"]).should eq "initialize"
      result.try(&.["id"]).should eq 1
    end

    it "returns nil on EOF" do
      input = IO::Memory.new("")
      transport = Crinkle::LSP::Transport.new(input, IO::Memory.new)

      transport.read_message.should be_nil
    end
  end

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

  describe Crinkle::LSP::Logger do
    it "logs to IO" do
      io = IO::Memory.new
      logger = Crinkle::LSP::Logger.new(io, Crinkle::LSP::Logger::Level::Debug)

      logger.debug("test debug")
      logger.info("test info")
      logger.warning("test warning")
      logger.error("test error")

      output = io.to_s
      output.should contain "test debug"
      output.should contain "test info"
      output.should contain "test warning"
      output.should contain "test error"
    end

    it "respects log level" do
      io = IO::Memory.new
      logger = Crinkle::LSP::Logger.new(io, Crinkle::LSP::Logger::Level::Warning)

      logger.debug("test debug")
      logger.info("test info")
      logger.warning("test warning")
      logger.error("test error")

      output = io.to_s
      output.should_not contain "test debug"
      output.should_not contain "test info"
      output.should contain "test warning"
      output.should contain "test error"
    end
  end
end
