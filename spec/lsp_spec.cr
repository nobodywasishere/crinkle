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

    it "writes error responses with correct JSON structure" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_error(42_i64, -32601, "Method not found: textDocument/hover")

      result = output.to_s
      # Extract JSON body (after headers)
      if body_start = result.index("{")
        json_body = result[body_start..]

        parsed = JSON.parse(json_body)
        parsed["jsonrpc"].should eq "2.0"
        parsed["id"].should eq 42
        parsed["error"]["code"].should eq -32601
        parsed["error"]["message"].should eq "Method not found: textDocument/hover"
      else
        fail "No JSON body found in response"
      end
    end

    it "writes notifications" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_notification("textDocument/publishDiagnostics", JSON.parse(%({"uri": "file:///test.j2"})))

      result = output.to_s
      result.should contain "textDocument/publishDiagnostics"
      result.should_not contain "\"id\""
    end

    it "writes notifications with correct JSON structure" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_notification("window/logMessage", JSON.parse(%({"type": 3, "message": "test"})))

      result = output.to_s
      if body_start = result.index("{")
        json_body = result[body_start..]

        parsed = JSON.parse(json_body)
        parsed["jsonrpc"].should eq "2.0"
        parsed["method"].should eq "window/logMessage"
        parsed["params"]["type"].should eq 3
        parsed["params"]["message"].should eq "test"
        parsed["id"]?.should be_nil
      else
        fail "No JSON body found in notification"
      end
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

  describe Crinkle::LSP::Diagnostics do
    it "converts linter issue to LSP diagnostic" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 5),
        Crinkle::Position.new(10, 1, 15)
      )
      issue = Crinkle::Linter::Issue.new(
        id: "Lint/TestRule",
        severity: Crinkle::Severity::Warning,
        message: "Test warning message",
        span: span
      )

      diag = Crinkle::LSP::Diagnostics.convert(issue)

      diag.range.start.line.should eq 0      # 1-based -> 0-based
      diag.range.start.character.should eq 4 # 5 -> 4
      diag.range.end_pos.line.should eq 0
      diag.range.end_pos.character.should eq 14
      diag.message.should eq "Test warning message"
      diag.severity.should eq Crinkle::LSP::DiagnosticSeverity::Warning
      diag.code.should eq "Lint/TestRule"
      diag.source.should eq "crinkle"
    end

    it "maps error severity correctly" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 1),
        Crinkle::Position.new(5, 1, 6)
      )
      issue = Crinkle::Linter::Issue.new(
        id: "Lexer/UnterminatedString",
        severity: Crinkle::Severity::Error,
        message: "Unterminated string",
        span: span
      )

      diag = Crinkle::LSP::Diagnostics.convert(issue)

      diag.severity.should eq Crinkle::LSP::DiagnosticSeverity::Error
    end

    it "maps info severity correctly" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 1),
        Crinkle::Position.new(5, 1, 6)
      )
      issue = Crinkle::Linter::Issue.new(
        id: "Lint/Info",
        severity: Crinkle::Severity::Info,
        message: "Info message",
        span: span
      )

      diag = Crinkle::LSP::Diagnostics.convert(issue)

      diag.severity.should eq Crinkle::LSP::DiagnosticSeverity::Information
    end

    it "converts multiple issues" do
      span1 = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 1),
        Crinkle::Position.new(5, 1, 6)
      )
      span2 = Crinkle::Span.new(
        Crinkle::Position.new(10, 2, 1),
        Crinkle::Position.new(15, 2, 6)
      )
      issues = [
        Crinkle::Linter::Issue.new("Lint/A", Crinkle::Severity::Error, "Error A", span1),
        Crinkle::Linter::Issue.new("Lint/B", Crinkle::Severity::Warning, "Warning B", span2),
      ]

      diagnostics = Crinkle::LSP::Diagnostics.convert_all(issues)

      diagnostics.size.should eq 2
      diagnostics[0].message.should eq "Error A"
      diagnostics[1].message.should eq "Warning B"
    end
  end

  describe Crinkle::LSP::Analyzer do
    it "analyzes template with syntax error" do
      analyzer = Crinkle::LSP::Analyzer.new

      # Template with unterminated expression
      issues = analyzer.analyze("Hello {{ name")

      issues.size.should be > 0
      issues.any? { |i| i.id.includes?("Lexer/") || i.id.includes?("Parser/") }.should be_true
    end

    it "analyzes valid template" do
      analyzer = Crinkle::LSP::Analyzer.new

      issues = analyzer.analyze("Hello {{ name }}")

      # May have lint issues (like formatting) but no syntax errors
      syntax_errors = issues.select { |i| i.id.starts_with?("Lexer/") || i.id.starts_with?("Parser/") }
      syntax_errors.size.should eq 0
    end

    it "returns LSP diagnostics directly" do
      analyzer = Crinkle::LSP::Analyzer.new

      diagnostics = analyzer.analyze_to_lsp("Hello {{ name")

      diagnostics.size.should be > 0
      diagnostics.all? { |diag| diag.source == "crinkle" }.should be_true
    end

    it "includes linter rules in analysis" do
      analyzer = Crinkle::LSP::Analyzer.new

      # Template with duplicate block names
      template = <<-JINJA
        {% block content %}Hello{% endblock %}
        {% block content %}World{% endblock %}
        JINJA

      issues = analyzer.analyze(template)

      # Should have duplicate block lint issue
      issues.any? { |issue| issue.id == "Lint/DuplicateBlock" }.should be_true
    end
  end
end
