require "./spec_helper"
require "../src/lsp/lsp"
require "file_utils"

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

    describe "#apply_change (incremental sync)" do
      it "inserts text at the beginning" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "World", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 0),
          Crinkle::LSP::Position.new(0, 0)
        )
        doc.apply_change(range, "Hello ", 2)
        doc.text.should eq "Hello World"
        doc.version.should eq 2
      end

      it "inserts text in the middle" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello World", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 5),
          Crinkle::LSP::Position.new(0, 5)
        )
        doc.apply_change(range, " Beautiful", 2)
        doc.text.should eq "Hello Beautiful World"
      end

      it "replaces text range" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello World", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 6),
          Crinkle::LSP::Position.new(0, 11)
        )
        doc.apply_change(range, "Crystal", 2)
        doc.text.should eq "Hello Crystal"
      end

      it "deletes text when replacement is empty" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello World", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 5),
          Crinkle::LSP::Position.new(0, 11)
        )
        doc.apply_change(range, "", 2)
        doc.text.should eq "Hello"
      end

      it "handles multi-line changes" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "line1\nline2\nline3", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(1, 0),
          Crinkle::LSP::Position.new(2, 0)
        )
        doc.apply_change(range, "new\n", 2)
        doc.text.should eq "line1\nnew\nline3"
      end

      it "invalidates cache on change" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "{{ x }}", 1)
        # Force caching by accessing tokens
        doc.tokens.size.should be > 0

        # Apply change
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 3),
          Crinkle::LSP::Position.new(0, 4)
        )
        doc.apply_change(range, "name", 2)

        # Tokens should be recomputed with new content
        doc.text.should eq "{{ name }}"
      end
    end

    describe "LSP diagnostics caching" do
      it "caches and retrieves diagnostics" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "{{ x }}", 1)
        diagnostics = [
          Crinkle::LSP::Diagnostic.new(
            range: Crinkle::LSP::Range.new(
              Crinkle::LSP::Position.new(0, 0),
              Crinkle::LSP::Position.new(0, 7)
            ),
            message: "Test diagnostic"
          ),
        ]

        doc.cache_diagnostics(diagnostics)
        cached = doc.cached_lsp_diagnostics

        cached.should_not be_nil
        cached.try(&.size).should eq 1
        cached.try(&.first.message).should eq "Test diagnostic"
      end

      it "returns nil for cached diagnostics when version changes" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "{{ x }}", 1)
        diagnostics = [
          Crinkle::LSP::Diagnostic.new(
            range: Crinkle::LSP::Range.new(
              Crinkle::LSP::Position.new(0, 0),
              Crinkle::LSP::Position.new(0, 7)
            ),
            message: "Test"
          ),
        ]

        doc.cache_diagnostics(diagnostics)
        doc.update("{{ y }}", 2)

        doc.cached_lsp_diagnostics.should be_nil
      end

      it "clears analysis cache separately from other caches" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "{{ x }}", 1)
        diagnostics = [
          Crinkle::LSP::Diagnostic.new(
            range: Crinkle::LSP::Range.new(
              Crinkle::LSP::Position.new(0, 0),
              Crinkle::LSP::Position.new(0, 7)
            ),
            message: "Test"
          ),
        ]

        # Cache diagnostics
        doc.cache_diagnostics(diagnostics)
        doc.cached_lsp_diagnostics.should_not be_nil

        # Clear analysis cache
        doc.clear_analysis_cache
        doc.cached_lsp_diagnostics.should be_nil
      end
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

    it "applies incremental changes" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///test.j2", "jinja2", "Hello World", 1)

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 6),
        Crinkle::LSP::Position.new(0, 11)
      )
      store.apply_change("file:///test.j2", range, "Crystal", 2)

      doc = store.get("file:///test.j2")
      doc.try(&.text).should eq "Hello Crystal"
      doc.try(&.version).should eq 2
    end

    describe "memory management" do
      it "tracks memory usage" do
        store = Crinkle::LSP::DocumentStore.new
        store.open("file:///a.j2", "jinja2", "Hello", 1)
        store.open("file:///b.j2", "jinja2", "World", 1)

        # Memory should be at least the text size
        store.memory_usage.should be >= 10
      end

      it "evicts stale caches when limit exceeded" do
        store = Crinkle::LSP::DocumentStore.new

        # Open documents and cache diagnostics
        5.times do |i|
          doc = store.open("file:///doc#{i}.j2", "jinja2", "{{ x }}", 1)
          doc.cache_diagnostics(Array(Crinkle::LSP::Diagnostic).new)
        end

        # All should have cached diagnostics
        5.times do |i|
          store.get("file:///doc#{i}.j2").try(&.cached_lsp_diagnostics).should_not be_nil
        end

        # Evict with a small limit
        evicted = store.evict_stale_caches(2)

        evicted.should eq 3
      end

      it "evicts least recently used first" do
        store = Crinkle::LSP::DocumentStore.new

        # Open documents in order
        store.open("file:///old.j2", "jinja2", "old", 1).cache_diagnostics(Array(Crinkle::LSP::Diagnostic).new)
        store.open("file:///middle.j2", "jinja2", "middle", 1).cache_diagnostics(Array(Crinkle::LSP::Diagnostic).new)
        store.open("file:///new.j2", "jinja2", "new", 1).cache_diagnostics(Array(Crinkle::LSP::Diagnostic).new)

        # Access old document to make it recently used
        store.get("file:///old.j2")

        # Evict to keep only 1
        store.evict_stale_caches(1)

        # Old should still have cache (was accessed most recently)
        store.get("file:///old.j2").try(&.cached_lsp_diagnostics).should_not be_nil
        # Middle should have been evicted (least recently used)
        store.get("file:///middle.j2").try(&.cached_lsp_diagnostics).should be_nil
      end
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

  describe Crinkle::LSP::InferenceEngine do
    it "extracts variables from for loops" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% for item in items %}{{ item.name }}{% endfor %}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "item"
      var_names.should contain "items"

      item_var = vars.find { |var| var.name == "item" }
      item_var.should_not be_nil
      item_var.try(&.source).should eq Crinkle::LSP::VariableSource::ForLoop
    end

    it "extracts variables from set statements" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% set greeting = 'Hello' %}{{ greeting }}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "greeting"

      greeting_var = vars.find { |var| var.name == "greeting" }
      greeting_var.try(&.source).should eq Crinkle::LSP::VariableSource::Set
    end

    it "extracts variables from macro parameters" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% macro button(text, style) %}{{ text }}{% endmacro %}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "text"
      var_names.should contain "style"

      text_var = vars.find { |var| var.name == "text" }
      text_var.try(&.source).should eq Crinkle::LSP::VariableSource::MacroParam
    end

    it "extracts context variables from expressions" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{{ user.name }} {{ product.price }}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "user"
      var_names.should contain "product"
    end

    it "extracts block names" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = <<-JINJA
        {% block header %}Header{% endblock %}
        {% block content %}Content{% endblock %}
        {% block footer %}Footer{% endblock %}
        JINJA
      engine.analyze("file:///test.j2", template)

      blocks = engine.blocks_for("file:///test.j2")
      blocks.should contain "header"
      blocks.should contain "content"
      blocks.should contain "footer"
    end

    it "extracts macro definitions" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = <<-JINJA
        {% macro button(text, style="primary") %}Button{% endmacro %}
        {% macro icon(name) %}Icon{% endmacro %}
        JINJA
      engine.analyze("file:///test.j2", template)

      macros = engine.macros_for("file:///test.j2")
      macro_names = macros.map(&.name)

      macro_names.should contain "button"
      macro_names.should contain "icon"

      button_macro = macros.find { |mac| mac.name == "button" }
      button_macro.should_not be_nil
      button_macro.try(&.params).should eq ["text", "style"]
      button_macro.try(&.signature).should eq %(button(text, style="primary"))
    end

    it "handles tuple unpacking in for loops" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% for key, value in items.items() %}{{ key }}: {{ value }}{% endfor %}"
      engine.analyze("file:///test.j2", template)

      vars = engine.variables_for("file:///test.j2")
      var_names = vars.map(&.name)

      var_names.should contain "key"
      var_names.should contain "value"
    end
  end

  describe Crinkle::LSP::CompletionProvider do
    it "provides variable completions in output context" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      # Analyze template to populate inference
      inference.analyze("file:///test.j2", "{% set greeting = 'Hi' %}{% for item in items %}{% endfor %}")

      # Request completions after {{
      completions = provider.completions(
        "file:///test.j2",
        "{{ ",
        Crinkle::LSP::Position.new(0, 3)
      )

      labels = completions.map(&.label)
      labels.should contain "greeting"
      labels.should contain "item"
      labels.should contain "items"
    end

    it "provides block completions after {% block" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      # Analyze template with blocks
      inference.analyze("file:///base.j2", "{% block header %}{% endblock %}{% block content %}{% endblock %}")

      # Request completions after {% block in child template
      completions = provider.completions(
        "file:///base.j2",
        "{% block ",
        Crinkle::LSP::Position.new(0, 9)
      )

      labels = completions.map(&.label)
      labels.should contain "header"
      labels.should contain "content"
    end

    it "provides macro completions after {% call" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      # Analyze template with macros
      inference.analyze("file:///test.j2", "{% macro button(text) %}{% endmacro %}{% macro icon(name) %}{% endmacro %}")

      # Request completions after {% call
      completions = provider.completions(
        "file:///test.j2",
        "{% call ",
        Crinkle::LSP::Position.new(0, 8)
      )

      labels = completions.map(&.label)
      labels.should contain "button"
      labels.should contain "icon"
    end

    it "filters completions by prefix" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CompletionProvider.new(schema_provider, inference)

      # Analyze template with multiple variables
      inference.analyze("file:///test.j2", "{% set user = 1 %}{% set username = 2 %}{% set product = 3 %}")

      # Request completions with prefix "us"
      completions = provider.completions(
        "file:///test.j2",
        "{{ us",
        Crinkle::LSP::Position.new(0, 5)
      )

      labels = completions.map(&.label)
      labels.should contain "user"
      labels.should contain "username"
      labels.should_not contain "product"
    end
  end

  describe Crinkle::LSP::DefinitionProvider do
    it "returns nil for extends when file does not exist" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = %({% extends "nonexistent.j2" %})

      # Position inside the quoted string
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 15))

      # Location should be nil because file doesn't exist
      location.should be_nil
    end

    it "returns nil for include when file does not exist" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = %({% include "nonexistent.j2" %})

      # Position inside the quoted string
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 14))

      # Location should be nil because file doesn't exist
      location.should be_nil
    end

    it "returns nil for position outside template reference" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = %(Hello {% extends "base.j2" %})

      # Position at "Hello"
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 2))

      location.should be_nil
    end

    it "returns location for existing file" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      # Use actual spec directory as root
      provider = Crinkle::LSP::DefinitionProvider.new(inference, "spec")

      # Reference spec_helper.cr which exists in spec/
      template = %({% extends "spec_helper.cr" %})

      # Position inside the quoted string
      location = provider.definition("file:///spec/test.j2", template, Crinkle::LSP::Position.new(0, 15))

      location.should_not be_nil
      if loc = location
        loc.uri.should contain "spec_helper.cr"
      end
    end
  end

  describe Crinkle::LSP::VariableInfo do
    it "stores variable information" do
      info = Crinkle::LSP::VariableInfo.new("item", Crinkle::LSP::VariableSource::ForLoop, "loop variable")

      info.name.should eq "item"
      info.source.should eq Crinkle::LSP::VariableSource::ForLoop
      info.detail.should eq "loop variable"
    end
  end

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

  describe "FileChangeType enum" do
    it "has correct values" do
      Crinkle::LSP::FileChangeType::Created.value.should eq 1
      Crinkle::LSP::FileChangeType::Changed.value.should eq 2
      Crinkle::LSP::FileChangeType::Deleted.value.should eq 3
    end
  end

  describe Crinkle::LSP::BlockInfo do
    it "stores block information" do
      info = Crinkle::LSP::BlockInfo.new("content")

      info.name.should eq "content"
      info.definition_span.should be_nil
      info.source_uri.should be_nil
    end

    it "stores block information with span and source" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 0, 0),
        Crinkle::Position.new(0, 20, 20)
      )
      info = Crinkle::LSP::BlockInfo.new("header", span, "file:///base.j2")

      info.name.should eq "header"
      info.definition_span.should eq span
      info.source_uri.should eq "file:///base.j2"
    end
  end

  describe Crinkle::LSP::HoverProvider do
    it "provides hover for filters" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "upper" filter
      hover = provider.hover("file:///test.j2", "{{ name | upper }}", Crinkle::LSP::Position.new(0, 11))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "upper"
      end
    end

    it "provides hover for tests" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "defined" test
      hover = provider.hover("file:///test.j2", "{% if name is defined %}", Crinkle::LSP::Position.new(0, 17))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "defined"
      end
    end

    it "provides hover for functions" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "range" function
      hover = provider.hover("file:///test.j2", "{{ range(10) }}", Crinkle::LSP::Position.new(0, 5))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "range"
      end
    end

    it "provides hover for variables from set statements" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      template = "{% set greeting = 'Hello' %}{{ greeting }}"
      inference.analyze("file:///test.j2", template)

      # Position on "greeting" in the output
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 33))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "greeting"
        h.contents.value.should contain "assigned variable"
      end
    end

    it "provides hover for variables from for loops" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      template = "{% for item in items %}{{ item }}{% endfor %}"
      inference.analyze("file:///test.j2", template)

      # Position on "item" in the output
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 27))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "item"
        h.contents.value.should contain "loop variable"
      end
    end

    it "provides hover for macros" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      template = "{% macro button(text, style='primary') %}{% endmacro %}{{ button('Click') }}"
      inference.analyze("file:///test.j2", template)

      # Position on "button" in the call
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 59))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "button"
        h.contents.value.should contain "text"
      end
    end

    it "provides hover for blocks" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      template = "{% block content %}Hello{% endblock %}"
      inference.analyze("file:///test.j2", template)

      # Position on "content" block name
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 12))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "block"
        h.contents.value.should contain "content"
      end
    end

    it "provides hover for tags" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "for" tag
      hover = provider.hover("file:///test.j2", "{% for item in items %}{% endfor %}", Crinkle::LSP::Position.new(0, 4))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "for"
        h.contents.value.should contain "block tag"
      end
    end

    it "provides hover for if tag" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on "if" tag
      hover = provider.hover("file:///test.j2", "{% if true %}yes{% endif %}", Crinkle::LSP::Position.new(0, 4))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "if"
        h.contents.value.should contain "Conditional"
      end
    end

    it "returns nil for text outside Jinja blocks" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Position on plain text
      hover = provider.hover("file:///test.j2", "Hello {{ name }}", Crinkle::LSP::Position.new(0, 2))

      hover.should be_nil
    end

    it "returns nil for context variables (no useful definition info)" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # Template with only context variable (inferred from usage, not defined)
      template = "{{ user.name }}"
      inference.analyze("file:///test.j2", template)

      # Position on "user" - a context variable
      hover = provider.hover("file:///test.j2", template, Crinkle::LSP::Position.new(0, 5))

      # Context variables should not show hover since they have no useful info
      hover.should be_nil
    end
  end

  describe "InferenceEngine definition spans" do
    it "tracks variable definition spans from set statements" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% set greeting = 'Hello' %}"
      engine.analyze("file:///test.j2", template)

      var_info = engine.variable_info("file:///test.j2", "greeting")
      var_info.should_not be_nil
      if info = var_info
        info.definition_span.should_not be_nil
        info.source.should eq Crinkle::LSP::VariableSource::Set
      end
    end

    it "tracks variable definition spans from for loops" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% for item in items %}{{ item }}{% endfor %}"
      engine.analyze("file:///test.j2", template)

      var_info = engine.variable_info("file:///test.j2", "item")
      var_info.should_not be_nil
      if info = var_info
        info.definition_span.should_not be_nil
        info.source.should eq Crinkle::LSP::VariableSource::ForLoop
      end
    end

    it "tracks macro definition spans" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% macro button(text) %}{{ text }}{% endmacro %}"
      engine.analyze("file:///test.j2", template)

      macro_info = engine.macro_info("file:///test.j2", "button")
      macro_info.should_not be_nil
      if info = macro_info
        info.definition_span.should_not be_nil
        info.name.should eq "button"
      end
    end

    it "tracks block definition spans" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% block content %}Hello{% endblock %}"
      engine.analyze("file:///test.j2", template)

      block_info = engine.block_info("file:///test.j2", "content")
      block_info.should_not be_nil
      if info = block_info
        info.definition_span.should_not be_nil
        info.name.should eq "content"
        info.source_uri.should eq "file:///test.j2"
      end
    end

    it "returns nil for unknown variable" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% set greeting = 'Hello' %}"
      engine.analyze("file:///test.j2", template)

      var_info = engine.variable_info("file:///test.j2", "nonexistent")
      var_info.should be_nil
    end

    it "returns nil for unknown macro" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% macro button(text) %}{% endmacro %}"
      engine.analyze("file:///test.j2", template)

      macro_info = engine.macro_info("file:///test.j2", "nonexistent")
      macro_info.should be_nil
    end

    it "returns nil for unknown block" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% block content %}{% endblock %}"
      engine.analyze("file:///test.j2", template)

      block_info = engine.block_info("file:///test.j2", "nonexistent")
      block_info.should be_nil
    end

    it "blocks_info_for returns BlockInfo array" do
      config = Crinkle::LSP::Config.new
      engine = Crinkle::LSP::InferenceEngine.new(config)

      template = "{% block header %}{% endblock %}{% block content %}{% endblock %}"
      engine.analyze("file:///test.j2", template)

      blocks = engine.blocks_info_for("file:///test.j2")
      blocks.size.should eq 2
      block_names = blocks.map(&.name)
      block_names.should contain "header"
      block_names.should contain "content"
    end
  end

  describe "DefinitionProvider for variables, macros, and blocks" do
    it "provides definition for variables from set statements" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{% set greeting = 'Hello' %}{{ greeting }}"
      inference.analyze("file:///test.j2", template)

      # Position on "greeting" in the output
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 33))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq "file:///test.j2"
        # LSP uses 0-based lines, single-line template means line 0
        loc.range.start.line.should eq 0
      end
    end

    it "provides definition for variables from for loops" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{% for item in items %}{{ item }}{% endfor %}"
      inference.analyze("file:///test.j2", template)

      # Position on "item" in the output
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 27))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq "file:///test.j2"
        # LSP uses 0-based lines, single-line template means line 0
        loc.range.start.line.should eq 0
      end
    end

    it "provides definition for macros" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{% macro button(text) %}{{ text }}{% endmacro %}{{ button('Click') }}"
      inference.analyze("file:///test.j2", template)

      # Position on "button" in the call
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 52))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq "file:///test.j2"
        # LSP uses 0-based lines, single-line template means line 0
        loc.range.start.line.should eq 0
      end
    end

    it "provides definition for blocks" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{% block content %}Hello{% endblock %}"
      inference.analyze("file:///test.j2", template)

      # Position on "content" block name
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 12))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq "file:///test.j2"
        # LSP uses 0-based lines, single-line template means line 0
        loc.range.start.line.should eq 0
      end
    end

    it "returns nil for context variables without definition" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "{{ user.name }}"
      inference.analyze("file:///test.j2", template)

      # Position on "user" - context variable has no definition span
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 5))

      # Context variables don't have definition spans, so should be nil
      location.should be_nil
    end

    it "returns nil for position on plain text" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = "Hello {{ name }}"
      inference.analyze("file:///test.j2", template)

      # Position on plain text
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 2))

      location.should be_nil
    end
  end

  describe Crinkle::LSP::ReferencesProvider do
    it "finds all references to a variable from set statement" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{% set greeting = 'Hello' %}{{ greeting }} {{ greeting }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on first "greeting" usage
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 33))

      # Should find: definition in set, and two usages in output
      locations.size.should eq 3
      locations.all? { |loc| loc.uri == uri }.should be_true
    end

    it "finds references to for loop variable" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{% for item in items %}{{ item.name }} - {{ item.id }}{% endfor %}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on "item" in the for loop
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 9))

      # Should find: definition in for loop, and two usages
      locations.size.should eq 3
    end

    it "can exclude declaration from results" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{% set x = 1 %}{{ x }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # With declaration - position on the 'x' in output (char 18)
      with_decl = provider.references(uri, template, Crinkle::LSP::Position.new(0, 18), include_declaration: true)
      # Without declaration
      without_decl = provider.references(uri, template, Crinkle::LSP::Position.new(0, 18), include_declaration: false)

      with_decl.size.should eq 2    # set + usage
      without_decl.size.should eq 1 # only usage
    end

    it "finds macro definition and call sites" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{% macro btn(t) %}{{ t }}{% endmacro %}{{ btn('A') }}{{ btn('B') }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on "btn" in first call
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 42))

      # Should find: macro definition, two call sites
      locations.size.should eq 3
    end

    it "finds block references across templates" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      base_template = "{% block content %}Base content{% endblock %}"
      child_template = "{% extends 'base.j2' %}{% block content %}Child content{% endblock %}"

      base_uri = "file:///base.j2"
      child_uri = "file:///child.j2"

      documents.open(base_uri, "jinja2", base_template, 1)
      documents.open(child_uri, "jinja2", child_template, 1)
      inference.analyze(base_uri, base_template)
      inference.analyze(child_uri, child_template)

      # Position on "content" in child template
      locations = provider.references(child_uri, child_template, Crinkle::LSP::Position.new(0, 33))

      # Should find both block definitions
      locations.size.should eq 2
      locations.map(&.uri).should contain base_uri
      locations.map(&.uri).should contain child_uri
    end

    it "returns empty array for position on plain text" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "Hello World"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)

      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 3))

      locations.should be_empty
    end

    it "returns empty array for filters (not referenceable)" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      template = "{{ name | upper }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on "upper" filter - filters are not referenceable
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 12))

      locations.should be_empty
    end
  end

  describe Crinkle::LSP::SymbolProvider do
    it "returns empty array for plain text" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "Hello World"

      symbols = provider.document_symbols(template)

      symbols.should be_empty
    end

    it "finds block symbols" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% block content %}Hello{% endblock %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should eq "content"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Class
    end

    it "finds macro symbols with params" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% macro button(text, style) %}{{ text }}{% endmacro %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should eq "button(text, style)"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Method
    end

    it "finds set variable symbols" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% set count = 10 %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should eq "count"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Variable
    end

    it "finds for loop symbols" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% for item in items %}{{ item }}{% endfor %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should start_with "for item in"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Struct
    end

    it "finds if statement symbols" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% if x > 0 %}positive{% endif %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should start_with "if"
      symbols[0].kind.should eq Crinkle::LSP::SymbolKind::Boolean
    end

    it "builds nested symbol hierarchy" do
      provider = Crinkle::LSP::SymbolProvider.new
      template = "{% block content %}{% for item in items %}{{ item }}{% endfor %}{% endblock %}"

      symbols = provider.document_symbols(template)

      symbols.size.should eq 1
      symbols[0].name.should eq "content"
      if children = symbols[0].children
        children.size.should eq 1
        children.first.name.should start_with "for item"
      else
        fail "Expected children to not be nil"
      end
    end

    it "handles parse errors gracefully" do
      provider = Crinkle::LSP::SymbolProvider.new
      # Use completely invalid syntax that will cause parser to fail
      template = "{% %} {{ }}"

      symbols = provider.document_symbols(template)

      # Should return empty or partial results without crashing
      symbols.size.should be <= 1
    end
  end

  describe "Linter::Issue.from_diagnostic" do
    it "creates Issue from Diagnostic" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 5),
        Crinkle::Position.new(10, 1, 15)
      )
      diag = Crinkle::Diagnostic.new(
        Crinkle::DiagnosticType::UnknownFilter,
        Crinkle::Severity::Warning,
        "Unknown filter 'foo'",
        span
      )

      issue = Crinkle::Linter::Issue.from_diagnostic(diag)

      issue.id.should eq "E_UNKNOWN_FILTER"
      issue.severity.should eq Crinkle::Severity::Warning
      issue.message.should eq "Unknown filter 'foo'"
      issue.span.should eq span
      issue.source_type.should eq Crinkle::DiagnosticType::UnknownFilter
    end

    it "preserves error severity" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 1),
        Crinkle::Position.new(5, 1, 6)
      )
      diag = Crinkle::Diagnostic.new(
        Crinkle::DiagnosticType::UnterminatedExpression,
        Crinkle::Severity::Error,
        "Unterminated expression",
        span
      )

      issue = Crinkle::Linter::Issue.from_diagnostic(diag)

      issue.severity.should eq Crinkle::Severity::Error
    end
  end

  describe Crinkle::LSP::CancellationToken do
    it "starts uncancelled" do
      token = Crinkle::LSP::CancellationToken.new
      token.cancelled?.should be_false
    end

    it "can be cancelled" do
      token = Crinkle::LSP::CancellationToken.new
      token.cancel
      token.cancelled?.should be_true
    end

    it "remains cancelled after multiple cancel calls" do
      token = Crinkle::LSP::CancellationToken.new
      token.cancel
      token.cancel
      token.cancelled?.should be_true
    end
  end

  describe Crinkle::LSP::CrinkleLspSettings do
    it "has default values" do
      settings = Crinkle::LSP::CrinkleLspSettings.new
      settings.lint_enabled?.should be_true
      settings.max_file_size.should eq 1_000_000
      settings.debounce_ms.should eq 150
      settings.typo_detection?.should be_true
    end

    it "deserializes from JSON" do
      json = %({"lintEnabled": false, "maxFileSize": 500000, "debounceMs": 200, "typoDetection": false})
      settings = Crinkle::LSP::CrinkleLspSettings.from_json(json)

      settings.lint_enabled?.should be_false
      settings.max_file_size.should eq 500000
      settings.debounce_ms.should eq 200
      settings.typo_detection?.should be_false
    end

    it "uses defaults for missing fields" do
      json = %({"lintEnabled": false})
      settings = Crinkle::LSP::CrinkleLspSettings.from_json(json)

      settings.lint_enabled?.should be_false
      settings.max_file_size.should eq 1_000_000 # default
      settings.debounce_ms.should eq 150         # default
      settings.typo_detection?.should be_true    # default
    end

    it "serializes to JSON" do
      settings = Crinkle::LSP::CrinkleLspSettings.new(
        lint_enabled: false,
        max_file_size: 2_000_000,
        debounce_ms: 100,
        typo_detection: false
      )
      json = settings.to_json
      parsed = JSON.parse(json)

      parsed["lintEnabled"].as_bool.should be_false
      parsed["maxFileSize"].should eq 2_000_000
      parsed["debounceMs"].should eq 100
      parsed["typoDetection"].as_bool.should be_false
    end
  end

  describe "Cross-file macro import resolution" do
    it "resolves imported macro for go-to-definition" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      # foo.html.j2 defines the macro (single line for predictable span)
      foo_template = %({% macro bar() %}{% endmacro %})
      foo_uri = "file:///templates/foo.html.j2"

      # baz.html.j2 imports and uses the macro
      # Template: {% from "foo.html.j2" import bar %}{{ bar() }}
      # Positions: 0-34 = import statement, 35-45 = {{ bar() }}
      # "bar" in call is at positions 38-40
      baz_template = %({% from "foo.html.j2" import bar %}{{ bar() }})
      baz_uri = "file:///templates/baz.html.j2"

      # Analyze both templates
      inference.analyze(foo_uri, foo_template)
      inference.analyze(baz_uri, baz_template)

      # Position on "bar" in the call ({{ bar() }}) - "bar" is at chars 38-40
      location = provider.definition(baz_uri, baz_template, Crinkle::LSP::Position.new(0, 39))

      location.should_not be_nil
      if loc = location
        loc.uri.should eq foo_uri
        # Should point to the macro definition in foo.html.j2
        loc.range.start.line.should eq 0
      end
    end

    it "finds imported macro via inference engine" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)

      # foo.html.j2 defines the macro
      foo_template = %({% macro bar() %}{% endmacro %})
      foo_uri = "file:///templates/foo.html.j2"

      # baz.html.j2 imports the macro
      baz_template = %({% from "foo.html.j2" import bar %})
      baz_uri = "file:///templates/baz.html.j2"

      # Analyze both templates
      inference.analyze(foo_uri, foo_template)
      inference.analyze(baz_uri, baz_template)

      # Macro should be accessible from baz via cross-template resolution
      macro_info = inference.macro_info(baz_uri, "bar")
      macro_info.should_not be_nil
      if info = macro_info
        info.name.should eq "bar"
        info.definition_span.should_not be_nil
      end
    end

    it "reports unknown function error for unimported macro" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      # Pass the schema registry to enable UnknownFunction rule
      analyzer = Crinkle::LSP::Analyzer.new(Crinkle::Schema.registry, inference)

      # baz.html.j2 tries to call bar() without importing it
      baz_template = "{{ bar() }}"
      baz_uri = "file:///templates/baz.html.j2"

      inference.analyze(baz_uri, baz_template)
      issues = analyzer.analyze(baz_template, baz_uri)

      # Should have an unknown function error
      unknown_func_issues = issues.select { |i| i.id == "Lint/UnknownFunction" }
      unknown_func_issues.size.should eq 1
      unknown_func_issues.first.message.should contain "Unknown function 'bar'"
    end

    it "does not report unknown function for properly imported macro (from...import)" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      # Pass the schema registry to enable UnknownFunction rule
      analyzer = Crinkle::LSP::Analyzer.new(Crinkle::Schema.registry, inference)

      # baz.html.j2 imports bar using from...import syntax
      baz_template = %({% from "foo.html.j2" import bar %}{{ bar() }})
      baz_uri = "file:///templates/baz.html.j2"

      inference.analyze(baz_uri, baz_template)
      issues = analyzer.analyze(baz_template, baz_uri)

      # Should NOT have an unknown function error for bar
      unknown_func_issues = issues.select { |i| i.id == "Lint/UnknownFunction" && i.message.includes?("bar") }
      unknown_func_issues.should be_empty
    end

    it "does not report unknown function for macro from import (cross-template resolution)" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      analyzer = Crinkle::LSP::Analyzer.new(Crinkle::Schema.registry, inference)

      # foo.html.j2 defines the macro
      foo_template = %({% macro bar() %}content{% endmacro %})
      foo_uri = "file:///templates/foo.html.j2"

      # baz.html.j2 uses {% import %} syntax (not {% from ... import %})
      baz_template = %({% import "foo.html.j2" %}{{ bar() }})
      baz_uri = "file:///templates/baz.html.j2"

      # Analyze both templates
      inference.analyze(foo_uri, foo_template)
      inference.analyze(baz_uri, baz_template)
      issues = analyzer.analyze(baz_template, baz_uri)

      # Should NOT have an unknown function error for bar
      # because the analyzer uses inference engine's cross-template resolution
      unknown_func_issues = issues.select { |i| i.id == "Lint/UnknownFunction" && i.message.includes?("bar") }
      unknown_func_issues.should be_empty
    end

    it "provides hover info for imported macro call" do
      config = Crinkle::LSP::Config.new
      schema_provider = Crinkle::LSP::SchemaProvider.new(config, ".")
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::HoverProvider.new(schema_provider, inference)

      # foo.html.j2 defines the macro with params
      foo_template = %({% macro bar(text, style="default") %}{{ text }}{% endmacro %})
      foo_uri = "file:///templates/foo.html.j2"

      # baz.html.j2 imports and uses the macro
      baz_template = %({% from "foo.html.j2" import bar %}{{ bar("hello") }})
      baz_uri = "file:///templates/baz.html.j2"

      # Analyze both templates
      inference.analyze(foo_uri, foo_template)
      inference.analyze(baz_uri, baz_template)

      # Position on "bar" in the call - "bar" is at chars 38-40
      hover = provider.hover(baz_uri, baz_template, Crinkle::LSP::Position.new(0, 39))

      hover.should_not be_nil
      if h = hover
        h.contents.value.should contain "bar"
        h.contents.value.should contain "text"
      end
    end

    it "finds macro references within same file" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::ReferencesProvider.new(inference, documents)

      # Template with macro definition and call in same file
      template = %({% macro bar() %}content{% endmacro %}{{ bar() }})
      uri = "file:///templates/test.html.j2"

      # Register document
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Find references to "bar" from the definition - "bar" in macro def is at char 9-11
      locations = provider.references(uri, template, Crinkle::LSP::Position.new(0, 10))

      # Should find the definition and the call site
      locations.size.should eq 2
      locations.all? { |loc| loc.uri == uri }.should be_true
    end

    it "tracks import relationships correctly" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)

      # baz.html.j2 has from...import relationship
      baz_template = %({% from "foo.html.j2" import bar, baz as qux %})
      baz_uri = "file:///templates/baz.html.j2"

      inference.analyze(baz_uri, baz_template)

      # The inference engine should track the relationship
      # (extends_path returns first relationship, which should include our import)
      extends = inference.extends_path(baz_uri)
      extends.should eq "foo.html.j2"
    end

    it "auto-analyzes imported templates from disk" do
      # Create temporary template files
      temp_dir = File.tempname("crinkle_test")
      Dir.mkdir_p(temp_dir)

      begin
        # Write foo.html.j2 with a macro
        foo_path = File.join(temp_dir, "foo.html.j2")
        File.write(foo_path, %({% macro bar(text) %}{{ text }}{% endmacro %}))

        # Write baz.html.j2 that imports foo
        baz_path = File.join(temp_dir, "baz.html.j2")
        baz_content = %({% from "foo.html.j2" import bar %}{{ bar("hello") }})
        File.write(baz_path, baz_content)

        # Create inference engine with root_path set
        config = Crinkle::LSP::Config.new
        inference = Crinkle::LSP::InferenceEngine.new(config, temp_dir)

        # Analyze only baz.html.j2 - foo.html.j2 should be auto-analyzed
        baz_uri = "file://#{baz_path}"
        inference.analyze(baz_uri, baz_content)

        # The macro from foo.html.j2 should be accessible via cross-template resolution
        macro_info = inference.macro_info(baz_uri, "bar")
        macro_info.should_not be_nil
        if info = macro_info
          info.name.should eq "bar"
          info.params.should eq ["text"]
        end
      ensure
        # Clean up temp files
        FileUtils.rm_rf(temp_dir)
      end
    end
  end

  describe Crinkle::LSP::FoldingProvider do
    it "returns empty array for single-line template" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{{ name }}"

      ranges = provider.folding_ranges(template)

      ranges.should be_empty
    end

    it "creates folding range for multi-line block" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% block content %}\nHello\n{% endblock %}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 1
      ranges[0].start_line.should eq 0
      ranges[0].end_line.should eq 2
      ranges[0].kind.should eq Crinkle::LSP::FoldingRangeKind::Region
    end

    it "creates folding range for multi-line for loop" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% for item in items %}\n{{ item }}\n{% endfor %}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 1
      ranges[0].start_line.should eq 0
      ranges[0].end_line.should eq 2
    end

    it "creates folding range for multi-line if" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% if x %}\ntrue\n{% endif %}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 1
      ranges[0].start_line.should eq 0
      ranges[0].end_line.should eq 2
    end

    it "creates comment folding range" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{# This is a\nmulti-line\ncomment #}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 1
      ranges[0].kind.should eq Crinkle::LSP::FoldingRangeKind::Comment
    end

    it "creates nested folding ranges" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% block outer %}\n{% for i in items %}\n{{ i }}\n{% endfor %}\n{% endblock %}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 2
    end

    it "handles parse errors gracefully" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% block unclosed"

      ranges = provider.folding_ranges(template)

      ranges.should be_empty
    end
  end
end
