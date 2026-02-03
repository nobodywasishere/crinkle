require "json"
require "uri"
require "../lexer/lexer"
require "../parser/parser"
require "../linter/linter"
require "../linter/rules"
require "../formatter/formatter"
require "./config"
require "./schema_provider"
require "./inference"
require "./completion"
require "./hover"
require "./signature_help"

module Crinkle::LSP
  # LSP server for Jinja2/Crinkle templates.
  class Server
    VERSION = "0.1.0"

    # Debounce delay for diagnostics (milliseconds).
    DEBOUNCE_MS = 150

    @transport : Transport
    @documents : DocumentStore
    @file_logger : Logger?
    @log_level : MessageType
    @initialized : Bool
    @shutdown_requested : Bool
    @root_uri : String?
    @root_path : String?
    @analyzer : Analyzer
    @pending_analysis : Hash(String, Time::Instant)
    @config : Config
    @schema_provider : SchemaProvider?
    @inference : InferenceEngine?
    @completion_provider : CompletionProvider?
    @hover_provider : HoverProvider?
    @signature_help_provider : SignatureHelpProvider?

    def initialize(
      @transport : Transport,
      @file_logger : Logger? = nil,
      @log_level : MessageType = MessageType::Info,
    ) : Nil
      @documents = DocumentStore.new
      @initialized = false
      @shutdown_requested = false
      @root_uri = nil
      @root_path = nil
      @analyzer = Analyzer.new
      @pending_analysis = Hash(String, Time::Instant).new
      @config = Config.new
      @schema_provider = nil
      @inference = nil
      @completion_provider = nil
      @hover_provider = nil
      @signature_help_provider = nil
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
        when "textDocument/formatting"
          handle_formatting(id, params)
        when "textDocument/completion"
          handle_completion(id, params)
        when "textDocument/hover"
          handle_hover(id, params)
        when "textDocument/signatureHelp"
          handle_signature_help(id, params)
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

        # Extract root path from URI
        if root_uri = @root_uri
          @root_path = uri_to_path(root_uri)
          log(MessageType::Info, "Root path: #{@root_path}")

          # Load configuration
          if root_path = @root_path
            @config = Config.load(root_path)
            log(MessageType::Info, "Config loaded from #{root_path}")

            # Initialize semantic providers
            schema_provider = SchemaProvider.new(@config, root_path)
            @schema_provider = schema_provider

            inference = InferenceEngine.new(@config)
            @inference = inference

            @completion_provider = CompletionProvider.new(schema_provider, inference)
            @hover_provider = HoverProvider.new(schema_provider)
            @signature_help_provider = SignatureHelpProvider.new(schema_provider)

            # Recreate analyzer with schema for schema-aware linting and typo detection
            custom_schema = schema_provider.custom_schema
            @analyzer = Analyzer.new(custom_schema || Schema.registry, inference)

            log(MessageType::Info, "Semantic providers initialized")
          end
        end
      end

      capabilities = ServerCapabilities.new(
        text_document_sync: TextDocumentSyncOptions.new(
          open_close: true,
          change: 1, # Full sync
          save: SaveOptions.new(include_text: true)
        ),
        document_formatting_provider: true,
        completion_provider: CompletionOptions.new(
          trigger_characters: ["|", ".", " "]
        ),
        hover_provider: true,
        signature_help_provider: SignatureHelpOptions.new(
          trigger_characters: ["(", ","]
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

    # Convert file:// URI to file path
    private def uri_to_path(uri : String) : String
      parsed = URI.parse(uri)
      parsed.path || uri
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

    # textDocument/formatting request handler
    private def handle_formatting(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        format_params = DocumentFormattingParams.from_json(params.to_json)
        uri = format_params.text_document.uri

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        # Format the document
        formatted = Formatter.new(doc.text).format

        # If no changes, return empty array
        if formatted == doc.text
          log(MessageType::Log, "<<< Response: formatting (no changes)")
          send_response(id, JSON.parse("[]"))
          return
        end

        # Return a single edit that replaces the entire document
        last_line = doc.line_count - 1
        last_line_content = doc.line(last_line) || ""
        end_pos = Position.new(line: last_line, character: last_line_content.size)

        edit = TextEdit.new(
          range: Range.new(
            start: Position.new(line: 0, character: 0),
            end_pos: end_pos
          ),
          new_text: formatted
        )

        log(MessageType::Log, "<<< Response: formatting (1 edit)")
        send_response(id, JSON.parse([edit].to_json))
      rescue ex
        log(MessageType::Error, "Failed to format: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Format error: #{ex.message}")
      end
    end

    # textDocument/completion request handler
    private def handle_completion(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        completion_params = CompletionParams.from_json(params.to_json)
        uri = completion_params.text_document.uri
        position = completion_params.position

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        # Get completions from provider
        if provider = @completion_provider
          completions = provider.completions(uri, doc.text, position)
          log(MessageType::Log, "<<< Response: completion (#{completions.size} items)")
          send_response(id, JSON.parse(completions.to_json))
        else
          # No provider, return empty list
          log(MessageType::Log, "<<< Response: completion (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide completions: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Completion error: #{ex.message}")
      end
    end

    # textDocument/hover request handler
    private def handle_hover(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        hover_params = HoverParams.from_json(params.to_json)
        uri = hover_params.text_document.uri
        position = hover_params.position

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        # Get hover from provider
        if provider = @hover_provider
          if hover = provider.hover(doc.text, position)
            log(MessageType::Log, "<<< Response: hover (found)")
            send_response(id, JSON.parse(hover.to_json))
          else
            log(MessageType::Log, "<<< Response: hover (null)")
            send_response(id, JSON::Any.new(nil))
          end
        else
          log(MessageType::Log, "<<< Response: hover (no provider)")
          send_response(id, JSON::Any.new(nil))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide hover: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Hover error: #{ex.message}")
      end
    end

    # textDocument/signatureHelp request handler
    private def handle_signature_help(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        sig_params = SignatureHelpParams.from_json(params.to_json)
        uri = sig_params.text_document.uri
        position = sig_params.position

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        # Get signature help from provider
        if provider = @signature_help_provider
          if sig_help = provider.signature_help(doc.text, position)
            log(MessageType::Log, "<<< Response: signatureHelp (found)")
            send_response(id, JSON.parse(sig_help.to_json))
          else
            log(MessageType::Log, "<<< Response: signatureHelp (null)")
            send_response(id, JSON::Any.new(nil))
          end
        else
          log(MessageType::Log, "<<< Response: signatureHelp (no provider)")
          send_response(id, JSON::Any.new(nil))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide signature help: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Signature help error: #{ex.message}")
      end
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

        # Run inference analysis
        @inference.try(&.analyze(doc.uri, doc.text))

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

          # Run inference analysis
          @inference.try(&.analyze(uri, change.text))

          # Run diagnostics with debouncing
          publish_diagnostics(uri, change.text, version, debounce: true)
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
        @pending_analysis.delete(uri)

        # Clear inference data
        @inference.try(&.clear(uri))

        log(MessageType::Info, "Closed: #{uri}")

        # Clear diagnostics for closed document
        clear_params = PublishDiagnosticsParams.new(uri: uri, diagnostics: Array(Diagnostic).new)
        send_notification("textDocument/publishDiagnostics", JSON.parse(clear_params.to_json))
      rescue ex
        log(MessageType::Error, "Failed to handle didClose: #{ex.message}")
      end
    end

    # Schedule diagnostics with debouncing.
    # This prevents excessive recomputation during rapid typing.
    private def schedule_diagnostics(uri : String, text : String, version : Int32) : Nil
      scheduled_at = Time.instant
      @pending_analysis[uri] = scheduled_at

      spawn do
        sleep(DEBOUNCE_MS.milliseconds)

        # Only run if this is still the most recent scheduled analysis
        if @pending_analysis[uri]? == scheduled_at
          run_diagnostics(uri, text, version)
        end
      end
    end

    # Run diagnostics immediately (bypasses debouncing).
    # Used for document open events where we want immediate feedback.
    private def run_diagnostics(uri : String, text : String, version : Int32) : Nil
      # Use the analyzer to run full pipeline: lex → parse → lint → typo detection
      lsp_diagnostics = @analyzer.analyze_to_lsp(text, uri)

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

    # Run diagnostics on document open (immediate) or change (debounced).
    private def publish_diagnostics(uri : String, text : String, version : Int32, debounce : Bool = false) : Nil
      if debounce
        schedule_diagnostics(uri, text, version)
      else
        run_diagnostics(uri, text, version)
      end
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
