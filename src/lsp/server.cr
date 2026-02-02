require "json"

module Crinkle::LSP
  # LSP server for Jinja2/Crinkle templates.
  class Server
    VERSION = "0.1.0"

    @transport : Transport
    @documents : DocumentStore
    @logger : Logger?
    @initialized : Bool
    @shutdown_requested : Bool
    @root_uri : String?

    def initialize(@transport : Transport, @logger : Logger? = nil) : Nil
      @documents = DocumentStore.new
      @initialized = false
      @shutdown_requested = false
      @root_uri = nil
    end

    # Main run loop - read and handle messages until exit.
    def run : Int32
      @logger.try(&.info("Crinkle LSP server starting"))

      loop do
        message = @transport.read_message
        break if message.nil?

        handle_message(message)
        break if @shutdown_requested && message["method"]? == "exit"
      end

      @logger.try(&.info("Crinkle LSP server exiting"))
      @shutdown_requested ? 0 : 1
    end

    private def handle_message(message : JSON::Any) : Nil
      if message["id"]?
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

      @logger.try(&.debug("Request: #{method} (id=#{id})"))

      # Check server state
      if !@initialized && method != "initialize"
        send_error(id, ErrorCodes::ServerNotInitialized, "Server not initialized")
        return
      end

      if @shutdown_requested && method != "exit"
        send_error(id, ErrorCodes::InvalidRequest, "Server is shutting down")
        return
      end

      case method
      when "initialize"
        handle_initialize(id, params)
      when "shutdown"
        handle_shutdown(id)
      else
        send_error(id, ErrorCodes::MethodNotFound, "Method not found: #{method}")
      end
    end

    private def handle_notification(message : JSON::Any) : Nil
      method = message["method"]?.try(&.as_s?) || ""
      params = message["params"]?

      @logger.try(&.debug("Notification: #{method}"))

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
      else
        @logger.try(&.debug("Ignoring unknown notification: #{method}"))
      end
    end

    # Initialize request handler
    private def handle_initialize(id : Int64 | String, params : JSON::Any?) : Nil
      if @initialized
        send_error(id, ErrorCodes::InvalidRequest, "Server already initialized")
        return
      end

      if params
        @root_uri = params["rootUri"]?.try(&.as_s?)
        @logger.try(&.info("Root URI: #{@root_uri}"))
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
      send_response(id, JSON.parse(result.to_json))
    end

    # Initialized notification handler
    private def handle_initialized : Nil
      @logger.try(&.info("Client initialized"))
    end

    # Shutdown request handler
    private def handle_shutdown(id : Int64 | String) : Nil
      @shutdown_requested = true
      @logger.try(&.info("Shutdown requested"))
      send_response(id, JSON::Any.new(nil))
    end

    # Exit notification handler
    private def handle_exit : Nil
      @logger.try(&.info("Exit received"))
    end

    # textDocument/didOpen notification handler
    private def handle_did_open(params : JSON::Any?) : Nil
      return unless params

      begin
        open_params = DidOpenTextDocumentParams.from_json(params.to_json)
        doc = open_params.text_document
        @documents.open(doc.uri, doc.language_id, doc.text, doc.version)
        @logger.try(&.info("Opened: #{doc.uri} (version #{doc.version})"))
      rescue ex
        @logger.try(&.error("Failed to handle didOpen: #{ex.message}"))
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
          @logger.try(&.info("Updated: #{uri} (version #{version})"))
        end
      rescue ex
        @logger.try(&.error("Failed to handle didChange: #{ex.message}"))
      end
    end

    # textDocument/didClose notification handler
    private def handle_did_close(params : JSON::Any?) : Nil
      return unless params

      begin
        close_params = DidCloseTextDocumentParams.from_json(params.to_json)
        uri = close_params.text_document.uri
        @documents.close(uri)
        @logger.try(&.info("Closed: #{uri}"))
      rescue ex
        @logger.try(&.error("Failed to handle didClose: #{ex.message}"))
      end
    end

    # Helper to parse message ID (can be string or int)
    private def parse_id(id : JSON::Any?) : Int64 | String
      case value = id.try(&.raw)
      when Int64
        value
      when String
        value
      else
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
