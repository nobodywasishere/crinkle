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
require "./definition"
require "./references"
require "./symbols"
require "./folding"
require "./highlights"
require "./links"
require "./workspace_symbols"
require "./rename"
require "./code_actions"
require "./inlay_hints"

module Crinkle::LSP
  # Cancellation token for long-running operations.
  # Allows analysis to be cancelled when document changes.
  class CancellationToken
    @cancelled : Atomic(Int32)

    def initialize : Nil
      @cancelled = Atomic(Int32).new(0)
    end

    # Check if the token has been cancelled.
    def cancelled? : Bool
      @cancelled.get == 1
    end

    # Cancel the token.
    def cancel : Nil
      @cancelled.set(1)
    end
  end

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
    @root_path : String?
    @analyzer : Analyzer
    @pending_analysis : Hash(String, Time::Instant)
    @config : Config
    @lsp_settings : CrinkleLspSettings
    @schema_provider : SchemaProvider?
    @inference : InferenceEngine?
    @completion_provider : CompletionProvider?
    @hover_provider : HoverProvider?
    @signature_help_provider : SignatureHelpProvider?
    @definition_provider : DefinitionProvider?
    @references_provider : ReferencesProvider?
    @symbol_provider : SymbolProvider?
    @folding_provider : FoldingProvider?
    @highlight_provider : DocumentHighlightProvider?
    @link_provider : DocumentLinkProvider?
    @workspace_symbol_provider : WorkspaceSymbolProvider?
    @rename_provider : RenameProvider?
    @code_action_provider : CodeActionProvider?
    @inlay_hint_provider : InlayHintProvider?

    # Cancellation tokens for pending analysis per URI
    @cancellation_tokens : Hash(String, CancellationToken)

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
      @lsp_settings = CrinkleLspSettings.new
      @schema_provider = nil
      @inference = nil
      @completion_provider = nil
      @hover_provider = nil
      @signature_help_provider = nil
      @definition_provider = nil
      @references_provider = nil
      @symbol_provider = nil
      @folding_provider = nil
      @highlight_provider = nil
      @link_provider = nil
      @workspace_symbol_provider = nil
      @rename_provider = nil
      @code_action_provider = nil
      @inlay_hint_provider = nil
      @cancellation_tokens = Hash(String, CancellationToken).new
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
        when "textDocument/definition"
          handle_definition(id, params)
        when "textDocument/references"
          handle_references(id, params)
        when "textDocument/documentSymbol"
          handle_document_symbol(id, params)
        when "textDocument/foldingRange"
          handle_folding_range(id, params)
        when "textDocument/documentHighlight"
          handle_document_highlight(id, params)
        when "textDocument/documentLink"
          handle_document_link(id, params)
        when "workspace/symbol"
          handle_workspace_symbol(id, params)
        when "textDocument/prepareRename"
          handle_prepare_rename(id, params)
        when "textDocument/rename"
          handle_rename(id, params)
        when "textDocument/codeAction"
          handle_code_action(id, params)
        when "textDocument/inlayHint"
          handle_inlay_hint(id, params)
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
      when "workspace/didChangeWatchedFiles"
        handle_did_change_watched_files(params)
      when "workspace/didChangeConfiguration"
        handle_did_change_configuration(params)
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

            inference = InferenceEngine.new(@config, root_path)
            @inference = inference

            # Enable debug logging for cross-file resolution (can be removed once stable)
            InferenceEngine.debug = true
            DefinitionProvider.debug = true

            @completion_provider = CompletionProvider.new(schema_provider, inference)
            @hover_provider = HoverProvider.new(schema_provider, inference)
            @signature_help_provider = SignatureHelpProvider.new(schema_provider)
            @definition_provider = DefinitionProvider.new(inference, root_path)
            @references_provider = ReferencesProvider.new(inference, @documents)
            @symbol_provider = SymbolProvider.new
            @folding_provider = FoldingProvider.new
            @highlight_provider = DocumentHighlightProvider.new(inference)
            @link_provider = DocumentLinkProvider.new(root_path)
            @workspace_symbol_provider = WorkspaceSymbolProvider.new(inference)
            @rename_provider = RenameProvider.new(inference, @documents)
            @code_action_provider = CodeActionProvider.new(inference)
            @inlay_hint_provider = InlayHintProvider.new(inference, schema_provider)

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
          change: 2, # Incremental sync
          save: SaveOptions.new(include_text: true)
        ),
        document_formatting_provider: true,
        completion_provider: CompletionOptions.new(
          trigger_characters: ["{", "%", "|", ".", " "]
        ),
        hover_provider: true,
        signature_help_provider: SignatureHelpOptions.new(
          trigger_characters: ["(", ","]
        ),
        definition_provider: true,
        references_provider: true,
        document_symbol_provider: false, # temp workaround
        folding_range_provider: true,
        document_highlight_provider: true,
        document_link_provider: true,
        workspace_symbol_provider: true,
        rename_provider: RenameOptions.new(prepare_provider: true),
        code_action_provider: true,
        inlay_hint_provider: true
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
          if hover = provider.hover(uri, doc.text, position)
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

    # textDocument/definition handler - go to definition for template references
    private def handle_definition(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        # Reuse HoverParams since it has the same structure (textDocument + position)
        def_params = HoverParams.from_json(params.to_json)
        uri = def_params.text_document.uri
        position = def_params.position

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        # Get definition from provider
        if provider = @definition_provider
          if location = provider.definition(uri, doc.text, position)
            log(MessageType::Log, "<<< Response: definition (found: #{location.uri})")
            send_response(id, JSON.parse(location.to_json))
          else
            log(MessageType::Log, "<<< Response: definition (null)")
            send_response(id, JSON::Any.new(nil))
          end
        else
          log(MessageType::Log, "<<< Response: definition (no provider)")
          send_response(id, JSON::Any.new(nil))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide definition: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Definition error: #{ex.message}")
      end
    end

    # textDocument/references handler - find all references to a symbol
    private def handle_references(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        ref_params = ReferenceParams.from_json(params.to_json)
        uri = ref_params.text_document.uri
        position = ref_params.position
        include_declaration = ref_params.context.try(&.include_declaration?) || true

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        # Get references from provider
        if provider = @references_provider
          locations = provider.references(uri, doc.text, position, include_declaration)
          if locations.empty?
            log(MessageType::Log, "<<< Response: references (empty)")
            send_response(id, JSON.parse("[]"))
          else
            log(MessageType::Log, "<<< Response: references (#{locations.size} found)")
            send_response(id, JSON.parse(locations.to_json))
          end
        else
          log(MessageType::Log, "<<< Response: references (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide references: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "References error: #{ex.message}")
      end
    end

    # textDocument/documentSymbol handler - document outline
    private def handle_document_symbol(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        symbol_params = DocumentSymbolParams.from_json(params.to_json)
        uri = symbol_params.text_document.uri

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        if provider = @symbol_provider
          symbols = provider.document_symbols(doc)
          log(MessageType::Log, "<<< Response: documentSymbol (#{symbols.size} symbols)")
          send_response(id, JSON.parse(symbols.to_json))
        else
          log(MessageType::Log, "<<< Response: documentSymbol (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide document symbols: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Document symbol error: #{ex.message}")
      end
    end

    # textDocument/foldingRange handler - code folding
    private def handle_folding_range(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        folding_params = FoldingRangeParams.from_json(params.to_json)
        uri = folding_params.text_document.uri

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        if provider = @folding_provider
          ranges = provider.folding_ranges(doc)
          log(MessageType::Log, "<<< Response: foldingRange (#{ranges.size} ranges)")
          send_response(id, JSON.parse(ranges.to_json))
        else
          log(MessageType::Log, "<<< Response: foldingRange (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide folding ranges: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Folding range error: #{ex.message}")
      end
    end

    # textDocument/documentHighlight handler
    private def handle_document_highlight(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        highlight_params = DocumentHighlightParams.from_json(params.to_json)
        uri = highlight_params.text_document.uri
        position = highlight_params.position

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        if provider = @highlight_provider
          highlights = provider.highlights(uri, doc.text, position)
          log(MessageType::Log, "<<< Response: documentHighlight (#{highlights.size} highlights)")
          send_response(id, JSON.parse(highlights.to_json))
        else
          log(MessageType::Log, "<<< Response: documentHighlight (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide document highlights: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Document highlight error: #{ex.message}")
      end
    end

    # textDocument/documentLink handler
    private def handle_document_link(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        link_params = DocumentLinkParams.from_json(params.to_json)
        uri = link_params.text_document.uri

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        if provider = @link_provider
          links = provider.links(uri, doc.text)
          log(MessageType::Log, "<<< Response: documentLink (#{links.size} links)")
          send_response(id, JSON.parse(links.to_json))
        else
          log(MessageType::Log, "<<< Response: documentLink (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide document links: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Document link error: #{ex.message}")
      end
    end

    # workspace/symbol handler
    private def handle_workspace_symbol(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        symbol_params = WorkspaceSymbolParams.from_json(params.to_json)
        query = symbol_params.query

        if provider = @workspace_symbol_provider
          symbols = provider.symbols(query)
          log(MessageType::Log, "<<< Response: workspace/symbol (#{symbols.size} symbols)")
          send_response(id, JSON.parse(symbols.to_json))
        else
          log(MessageType::Log, "<<< Response: workspace/symbol (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide workspace symbols: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Workspace symbol error: #{ex.message}")
      end
    end

    # textDocument/prepareRename handler
    private def handle_prepare_rename(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        rename_params = PrepareRenameParams.from_json(params.to_json)
        uri = rename_params.text_document.uri
        position = rename_params.position

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        if provider = @rename_provider
          if result = provider.prepare_rename(uri, doc.text, position)
            log(MessageType::Log, "<<< Response: prepareRename (#{result.placeholder})")
            send_response(id, JSON.parse(result.to_json))
          else
            log(MessageType::Log, "<<< Response: prepareRename (null)")
            send_response(id, JSON::Any.new(nil))
          end
        else
          log(MessageType::Log, "<<< Response: prepareRename (no provider)")
          send_response(id, JSON::Any.new(nil))
        end
      rescue ex
        log(MessageType::Error, "Failed to prepare rename: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Prepare rename error: #{ex.message}")
      end
    end

    # textDocument/rename handler
    private def handle_rename(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        rename_params = RenameParams.from_json(params.to_json)
        uri = rename_params.text_document.uri
        position = rename_params.position
        new_name = rename_params.new_name

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        if provider = @rename_provider
          if edit = provider.rename(uri, doc.text, position, new_name)
            log(MessageType::Log, "<<< Response: rename (#{edit.changes.try(&.size) || 0} files)")
            send_response(id, JSON.parse(edit.to_json))
          else
            log(MessageType::Log, "<<< Response: rename (null)")
            send_response(id, JSON::Any.new(nil))
          end
        else
          log(MessageType::Log, "<<< Response: rename (no provider)")
          send_response(id, JSON::Any.new(nil))
        end
      rescue ex
        log(MessageType::Error, "Failed to rename: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Rename error: #{ex.message}")
      end
    end

    # textDocument/codeAction handler
    private def handle_code_action(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        action_params = CodeActionParams.from_json(params.to_json)
        uri = action_params.text_document.uri
        range = action_params.range
        context = action_params.context

        if provider = @code_action_provider
          actions = provider.code_actions(uri, range, context)
          log(MessageType::Log, "<<< Response: codeAction (#{actions.size} actions)")
          send_response(id, JSON.parse(actions.to_json))
        else
          log(MessageType::Log, "<<< Response: codeAction (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide code actions: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Code action error: #{ex.message}")
      end
    end

    # textDocument/inlayHint handler
    private def handle_inlay_hint(id : Int64 | String, params : JSON::Any?) : Nil
      unless params
        send_error(id, ErrorCodes::InvalidParams, "Missing params")
        return
      end

      begin
        hint_params = InlayHintParams.from_json(params.to_json)
        uri = hint_params.text_document.uri
        range = hint_params.range

        doc = @documents.get(uri)
        unless doc
          send_error(id, ErrorCodes::InvalidParams, "Document not open: #{uri}")
          return
        end

        if provider = @inlay_hint_provider
          hints = provider.inlay_hints(uri, doc.text, range)
          log(MessageType::Log, "<<< Response: inlayHint (#{hints.size} hints)")
          send_response(id, JSON.parse(hints.to_json))
        else
          log(MessageType::Log, "<<< Response: inlayHint (no provider)")
          send_response(id, JSON.parse("[]"))
        end
      rescue ex
        log(MessageType::Error, "Failed to provide inlay hints: #{ex.message}")
        send_error(id, ErrorCodes::InternalError, "Inlay hint error: #{ex.message}")
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

        # Apply each content change
        change_params.content_changes.each do |change|
          if range = change.range
            # Incremental sync: apply change to specific range
            @documents.apply_change(uri, range, change.text, version)
          else
            # Full sync fallback: replace entire content
            @documents.update(uri, change.text, version)
          end
        end

        # Get the final document text for analysis
        if doc = @documents.get(uri)
          log(MessageType::Info, "Updated: #{uri} (version #{version})")

          # Run inference analysis
          @inference.try(&.analyze(uri, doc.text))

          # Run diagnostics with debouncing
          publish_diagnostics(uri, doc.text, version, debounce: true)
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

        # Note: We intentionally do NOT clear inference data on close.
        # Other open files may depend on macros/blocks from this file.
        # The data will be refreshed on the next didOpen if needed.

        log(MessageType::Info, "Closed: #{uri}")

        # Clear diagnostics for closed document
        clear_params = PublishDiagnosticsParams.new(uri: uri, diagnostics: Array(Diagnostic).new)
        send_notification("textDocument/publishDiagnostics", JSON.parse(clear_params.to_json))
      rescue ex
        log(MessageType::Error, "Failed to handle didClose: #{ex.message}")
      end
    end

    # workspace/didChangeWatchedFiles notification handler
    private def handle_did_change_watched_files(params : JSON::Any?) : Nil
      return unless params

      begin
        watched_params = DidChangeWatchedFilesParams.from_json(params.to_json)

        watched_params.changes.each do |change|
          uri = change.uri
          path = uri_to_path(uri)

          case
          when path.ends_with?("config.yaml")
            log(MessageType::Info, "Config file changed: #{path}")
            reload_config
          when path.ends_with?("schema.json")
            log(MessageType::Info, "Schema file changed: #{path}")
            reload_schema
          when path.ends_with?(".j2") || path.ends_with?(".jinja2") || path.ends_with?(".jinja")
            # Re-run inference for template changes (only if file is open)
            if doc = @documents.get(uri)
              log(MessageType::Info, "Template changed: #{path}")
              @inference.try(&.analyze(uri, doc.text))
            end
          end
        end
      rescue ex
        log(MessageType::Error, "Failed to handle didChangeWatchedFiles: #{ex.message}")
      end
    end

    # workspace/didChangeConfiguration notification handler
    private def handle_did_change_configuration(params : JSON::Any?) : Nil
      return unless params

      begin
        config_params = DidChangeConfigurationParams.from_json(params.to_json)
        settings = config_params.settings

        # Try to extract crinkle-specific settings
        # Settings may be nested under "crinkle" key or at root level
        crinkle_settings = settings["crinkle"]? || settings

        @lsp_settings = CrinkleLspSettings.from_json(crinkle_settings.to_json)
        log(MessageType::Info, "LSP settings updated: lint=#{@lsp_settings.lint_enabled?}, maxFileSize=#{@lsp_settings.max_file_size}, debounceMs=#{@lsp_settings.debounce_ms}")

        # Re-analyze all open documents with new settings
        reanalyze_open_documents
      rescue ex
        log(MessageType::Warning, "Failed to parse configuration: #{ex.message}")
        # Keep existing settings on parse error
      end
    end

    # Reload configuration from disk
    private def reload_config : Nil
      return unless root_path = @root_path

      @config = Config.load(root_path)
      log(MessageType::Info, "Config reloaded")

      # Reinitialize inference engine with new config
      inference = InferenceEngine.new(@config, root_path)
      @inference = inference

      # Update references provider with new inference engine
      @references_provider = ReferencesProvider.new(inference, @documents)

      # Re-analyze all open documents
      reanalyze_open_documents
    end

    # Reload schema from disk
    private def reload_schema : Nil
      return unless root_path = @root_path

      # Reinitialize schema provider
      schema_provider = SchemaProvider.new(@config, root_path)
      @schema_provider = schema_provider

      # Update providers that depend on schema
      if inference = @inference
        @completion_provider = CompletionProvider.new(schema_provider, inference)
        @definition_provider = DefinitionProvider.new(inference, root_path)
        @hover_provider = HoverProvider.new(schema_provider, inference)
        @references_provider = ReferencesProvider.new(inference, @documents)
      end
      @signature_help_provider = SignatureHelpProvider.new(schema_provider)

      # Update analyzer with new schema
      custom_schema = schema_provider.custom_schema
      @analyzer = Analyzer.new(custom_schema || Schema.registry, @inference)

      log(MessageType::Info, "Schema reloaded")

      # Re-publish diagnostics for all open documents
      reanalyze_open_documents
    end

    # Re-analyze all open documents (after config/schema reload)
    private def reanalyze_open_documents : Nil
      @documents.uris.each do |uri|
        if doc = @documents.get(uri)
          @inference.try(&.analyze(uri, doc.text))
          publish_diagnostics(uri, doc.text, doc.version)
        end
      end
    end

    # Schedule diagnostics with debouncing.
    # This prevents excessive recomputation during rapid typing.
    # Schedule diagnostics with debouncing.
    # Spawns a fiber that waits for the debounce delay, then runs analysis.
    private def schedule_diagnostics(uri : String, text : String, version : Int32) : Nil
      scheduled_at = Time.instant
      @pending_analysis[uri] = scheduled_at

      # Cancel any pending analysis for this URI
      @cancellation_tokens[uri]?.try(&.cancel)

      # Create a new cancellation token for this request
      token = CancellationToken.new
      @cancellation_tokens[uri] = token

      debounce_ms = @lsp_settings.debounce_ms

      spawn do
        sleep(debounce_ms.milliseconds)

        # Only run if this is still the most recent scheduled analysis
        next unless @pending_analysis[uri]? == scheduled_at
        next if token.cancelled?

        # Check document version hasn't changed
        if doc = @documents.get(uri)
          next if doc.version != version
        end

        run_diagnostics(uri, text, version, token)

        # Evict stale caches to manage memory
        evicted = @documents.evict_stale_caches
        if evicted > 0
          log(MessageType::Log, "Evicted #{evicted} stale analysis caches")
        end
      end
    end

    # Run diagnostics immediately (bypasses debouncing).
    # Used for document open events where we want immediate feedback.
    # Accepts an optional cancellation token for background analysis.
    private def run_diagnostics(uri : String, text : String, version : Int32, token : CancellationToken? = nil) : Nil
      doc = @documents.get(uri)

      # Check for cached diagnostics
      if doc && (cached = doc.cached_lsp_diagnostics)
        params = PublishDiagnosticsParams.new(
          uri: uri,
          diagnostics: cached,
          version: version
        )
        send_notification("textDocument/publishDiagnostics", JSON.parse(params.to_json))
        log(MessageType::Log, "Published #{cached.size} cached diagnostics for #{uri}")
        return
      end

      # Check for cancellation before starting analysis
      return if token.try(&.cancelled?)

      # Check file size for graceful degradation
      lsp_diagnostics = if text.bytesize > @lsp_settings.max_file_size
                          log(MessageType::Info, "Large file detected (#{text.bytesize} bytes), using basic analysis for #{uri}")
                          run_basic_analysis(text, uri)
                        else
                          # Use the analyzer to run full pipeline: lex → parse → lint → typo detection
                          @analyzer.analyze_to_lsp(text, uri)
                        end

      # Check for cancellation after analysis (don't publish stale results)
      return if token.try(&.cancelled?)

      # Cache the results
      doc.try(&.cache_diagnostics(lsp_diagnostics))

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

    # Run basic analysis for large files (only lexer and parser errors).
    # Skips linting and typo detection for performance.
    private def run_basic_analysis(text : String, uri : String) : Array(Diagnostic)
      issues = Array(Linter::Issue).new

      # Lex the template
      lexer = Lexer.new(text)
      lexer.lex_all
      lexer.diagnostics.each do |diag|
        issues << Linter::Issue.from_diagnostic(diag)
      end

      # Parse the template (for syntax errors)
      begin
        parser = Parser.new(lexer.lex_all)
        parser.parse
        parser.diagnostics.each do |diag|
          issues << Linter::Issue.from_diagnostic(diag)
        end
      rescue
        # If parsing fails completely, we already have lexer diagnostics
      end

      Diagnostics.convert_all(issues)
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
