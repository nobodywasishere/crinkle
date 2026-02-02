require "json"
require "../lexer/lexer"
require "../parser/parser"

module Crinkle::LSP
  # LSP server for Jinja2/Crinkle templates.
  class Server
    VERSION = "0.1.0"

    @transport : Transport
    @documents : DocumentStore
    @file_logger : Logger?
    @log_level : MessageType
    @initialized : Bool
    @shutdown_requested : Bool
    @root_uri : String?

    def initialize(
      @transport : Transport,
      @file_logger : Logger? = nil,
      @log_level : MessageType = MessageType::Info,
    ) : Nil
      @documents = DocumentStore.new
      @initialized = false
      @shutdown_requested = false
      @root_uri = nil
    end

    # Main run loop - read and handle messages until exit.
    def run : Int32
      log(MessageType::Info, "Crinkle LSP server starting")

      loop do
        message = @transport.read_message
        break if message.nil?

        handle_message(message)
        break if @shutdown_requested && message["method"]? == "exit"
      end

      log(MessageType::Info, "Crinkle LSP server exiting")
      @shutdown_requested ? 0 : 1
    end

    private def handle_message(message : JSON::Any) : Nil
      # Check if this is a request (has non-null id) or notification (no id or null id)
      id_field = message["id"]?
      has_valid_id = id_field && !id_field.raw.nil?

      if has_valid_id
        # Request - needs a response
        handle_request(message)
      else
        # Notification - no response needed
        handle_notification(message)
      end
    end

    private def handle_request(message : JSON::Any) : Nil
      id = parse_id(message["id"])
      method = message["method"]?.try(&.as_s?) || ""
      params = message["params"]?

      log(MessageType::Log, ">>> Request: #{method} (id=#{id})")

      begin
        # Check server state
        if !@initialized && method != "initialize"
          log(MessageType::Log, "<<< Error: Server not initialized")
          send_error(id, ErrorCodes::ServerNotInitialized, "Server not initialized")
          return
        end

        if @shutdown_requested && method != "exit"
          log(MessageType::Log, "<<< Error: Server is shutting down")
          send_error(id, ErrorCodes::InvalidRequest, "Server is shutting down")
          return
        end

        case method
        when "initialize"
          handle_initialize(id, params)
        when "shutdown"
          handle_shutdown(id)
        else
          log(MessageType::Log, "<<< Error: Method not found: #{method}")
          send_error(id, ErrorCodes::MethodNotFound, "Method not found: #{method}")
        end
      rescue ex
        # Always send an error response if something goes wrong
        @file_logger.try(&.error("Exception handling request #{method}: #{ex.message}"))
        send_error(id, ErrorCodes::InternalError, "Internal error: #{ex.message}")
      end
    end

    private def handle_notification(message : JSON::Any) : Nil
      method = message["method"]?.try(&.as_s?) || ""
      params = message["params"]?

      log(MessageType::Log, ">>> Notification: #{method}")

      case method
      when "initialized"
        handle_initialized
      when "exit"
        handle_exit
      when "textDocument/didOpen"
        handle_did_open(params)
      when "textDocument/didChange"
        handle_did_change(params)
      when "textDocument/didClose"
        handle_did_close(params)
      when "$/cancelRequest"
        # Ignore cancel requests (we don't support cancellation yet)
        log(MessageType::Log, "    Ignoring cancel request")
      when "$/setTrace"
        # Ignore trace configuration
        log(MessageType::Log, "    Ignoring setTrace")
      else
        log(MessageType::Log, "    Unknown notification, ignoring")
      end
    end

    # Initialize request handler
    private def handle_initialize(id : Int64 | String, params : JSON::Any?) : Nil
      if @initialized
        log(MessageType::Log, "<<< Error: Server already initialized")
        send_error(id, ErrorCodes::InvalidRequest, "Server already initialized")
        return
      end

      if params
        @root_uri = params["rootUri"]?.try(&.as_s?)
        log(MessageType::Info, "Root URI: #{@root_uri}")
      end

      capabilities = ServerCapabilities.new(
        text_document_sync: TextDocumentSyncOptions.new(
          open_close: true,
          change: 1, # Full sync
          save: SaveOptions.new(include_text: true)
        )
      )

      result = InitializeResult.new(
        capabilities: capabilities,
        server_info: ServerInfo.new(name: "crinkle-lsp", version: VERSION)
      )

      @initialized = true
      log(MessageType::Log, "<<< Response: initialize success")
      send_response(id, JSON.parse(result.to_json))
    end

    # Initialized notification handler
    private def handle_initialized : Nil
      log(MessageType::Info, "Client initialized")
    end

    # Shutdown request handler
    private def handle_shutdown(id : Int64 | String) : Nil
      @shutdown_requested = true
      log(MessageType::Info, "Shutdown requested")
      log(MessageType::Log, "<<< Response: shutdown success")
      send_response(id, JSON::Any.new(nil))
    end

    # Exit notification handler
    private def handle_exit : Nil
      log(MessageType::Info, "Exit received")
    end

    # textDocument/didOpen notification handler
    private def handle_did_open(params : JSON::Any?) : Nil
      return unless params

      begin
        open_params = DidOpenTextDocumentParams.from_json(params.to_json)
        doc = open_params.text_document
        @documents.open(doc.uri, doc.language_id, doc.text, doc.version)
        log(MessageType::Info, "Opened: #{doc.uri} (version #{doc.version})")

        # Run diagnostics
        publish_diagnostics(doc.uri, doc.text, doc.version)
      rescue ex
        log(MessageType::Error, "Failed to handle didOpen: #{ex.message}")
      end
    end

    # textDocument/didChange notification handler
    private def handle_did_change(params : JSON::Any?) : Nil
      return unless params

      begin
        change_params = DidChangeTextDocumentParams.from_json(params.to_json)
        uri = change_params.text_document.uri
        version = change_params.text_document.version

        # Full sync: just take the last content change
        if change = change_params.content_changes.last?
          @documents.update(uri, change.text, version)
          log(MessageType::Info, "Updated: #{uri} (version #{version})")

          # Run diagnostics
          publish_diagnostics(uri, change.text, version)
        end
      rescue ex
        log(MessageType::Error, "Failed to handle didChange: #{ex.message}")
      end
    end

    # textDocument/didClose notification handler
    private def handle_did_close(params : JSON::Any?) : Nil
      return unless params

      begin
        close_params = DidCloseTextDocumentParams.from_json(params.to_json)
        uri = close_params.text_document.uri
        @documents.close(uri)
        log(MessageType::Info, "Closed: #{uri}")

        # Clear diagnostics for closed document
        params = PublishDiagnosticsParams.new(uri: uri, diagnostics: Array(Diagnostic).new)
        send_notification("textDocument/publishDiagnostics", JSON.parse(params.to_json))
      rescue ex
        log(MessageType::Error, "Failed to handle didClose: #{ex.message}")
      end
    end

    # Run diagnostics on document and publish them
    private def publish_diagnostics(uri : String, text : String, version : Int32) : Nil
      # Lex the template
      lexer = Crinkle::Lexer.new(text)
      tokens = lexer.lex_all
      lex_diagnostics = lexer.diagnostics

      # Parse the template
      parser = Crinkle::Parser.new(tokens)
      parser.parse
      parse_diagnostics = parser.diagnostics

      # Combine all diagnostics
      all_diagnostics = lex_diagnostics + parse_diagnostics

      # Convert to LSP diagnostics
      lsp_diagnostics = all_diagnostics.map do |diag|
        convert_diagnostic(diag)
      end

      # Publish diagnostics
      params = PublishDiagnosticsParams.new(
        uri: uri,
        diagnostics: lsp_diagnostics,
        version: version
      )
      send_notification("textDocument/publishDiagnostics", JSON.parse(params.to_json))

      log(MessageType::Log, "Published #{lsp_diagnostics.size} diagnostics for #{uri}")
    rescue ex
      log(MessageType::Error, "Failed to publish diagnostics: #{ex.message}")
    end

    # Convert Crinkle diagnostic to LSP diagnostic
    private def convert_diagnostic(diag : Crinkle::Diagnostic) : Diagnostic
      # Convert severity
      severity = case diag.severity
                 when Crinkle::Severity::Error
                   DiagnosticSeverity::Error
                 when Crinkle::Severity::Warning
                   DiagnosticSeverity::Warning
                 else
                   DiagnosticSeverity::Information
                 end

      # Convert position (Crinkle uses 1-based, LSP uses 0-based)
      start_pos = Position.new(
        line: diag.span.start_pos.line - 1,
        character: diag.span.start_pos.column - 1
      )
      end_pos = Position.new(
        line: diag.span.end_pos.line - 1,
        character: diag.span.end_pos.column - 1
      )
      range = Range.new(start: start_pos, end_pos: end_pos)

      Diagnostic.new(
        range: range,
        message: diag.message,
        severity: severity,
        code: diag.id,
        source: "crinkle"
      )
    end

    # Helper to parse message ID (can be string or int)
    private def parse_id(id : JSON::Any?) : Int64 | String
      return 0_i64 unless id

      case value = id.raw
      when Int64
        value
      when Int32
        value.to_i64
      when String
        value
      else
        # Log unexpected id type for debugging
        @file_logger.try(&.warning("Unexpected id type: #{value.class}"))
        0_i64
      end
    end

    # Send a successful response
    private def send_response(id : Int64 | String, result : JSON::Any) : Nil
      @transport.write_response(id, result)
    end

    # Send an error response
    private def send_error(id : Int64 | String, code : Int32, message : String) : Nil
      @transport.write_error(id, code, message)
    end

    # Send a notification to the client
    private def send_notification(method : String, params : JSON::Any) : Nil
      @transport.write_notification(method, params)
    end

    # Log a message via window/logMessage notification
    private def log(type : MessageType, message : String) : Nil
      # Check log level (lower value = higher priority)
      return if type.value > @log_level.value

      # Log to file if configured
      @file_logger.try do |logger|
        case type
        when .error?   then logger.error(message)
        when .warning? then logger.warning(message)
        when .info?    then logger.info(message)
        when .log?     then logger.debug(message)
        end
      end

      return unless @initialized
      begin
        params = LogMessageParams.new(type: type, message: message)
        send_notification("window/logMessage", JSON.parse(params.to_json))
      rescue ex
        @file_logger.try(&.error("Failed to send log notification: #{ex.message}"))
      end
    end

    # Expose document store for testing
    def documents : DocumentStore
      @documents
    end

    # Check if server is initialized
    def initialized? : Bool
      @initialized
    end

    # Check if shutdown was requested
    def shutdown_requested? : Bool
      @shutdown_requested
    end
  end
end
