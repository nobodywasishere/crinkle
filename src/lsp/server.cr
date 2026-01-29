require "lsprotocol"
require "../crinkle"
require "./types"
require "./document_store"
require "./text_scanner"
require "./analyzer"
require "./resolver"
require "./mapper"
require "./transport"

module Crinkle
  module LSP
    class Server
      @io_out : IO
      @io_err : IO
      @transport : Transport

      def self.run : Nil
        new.run
      end

      def initialize : Nil
        @documents = DocumentStore.new
        @analyzer = Analyzer.new
        @running = true
        @io_out = STDOUT.as(IO)
        @io_err = STDERR.as(IO)
        @transport = Transport.new(STDIN, STDOUT)
      end

      def run(io_in : IO = STDIN, io_out : IO = STDOUT, io_err : IO = STDERR) : Nil
        @io_out = io_out
        @io_err = io_err
        @transport = Transport.new(io_in, io_out)
        loop do
          raw_message = @transport.read_message
          break if raw_message.nil?
          message = parse_message(raw_message, io_err)
          next if message.nil?
          handle_message(message)
          break unless @running
        end
      rescue ex
        io_err.puts "LSP server error: #{ex.message}"
      end

      private def parse_message(data : String, io_err : IO) : LSProtocol::Message?
        LSProtocol.parse_message(data)
      rescue ex : LSProtocol::ParseError
        io_err.puts "LSP parse error: #{ex.message}"
        nil
      end

      private def handle_initialize(message : LSProtocol::InitializeRequest) : Nil
        sync_options = LSProtocol::TextDocumentSyncOptions.new(
          change: LSProtocol::TextDocumentSyncKind::Full,
          open_close: true,
        )
        capabilities = LSProtocol::ServerCapabilities.new(
          text_document_sync: sync_options,
          hover_provider: true,
          definition_provider: true,
          document_symbol_provider: true,
          folding_range_provider: true,
        )
        server_info = LSProtocol::ServerInfo.new("crinkle")
        result = LSProtocol::InitializeResult.new(capabilities, server_info)
        response = LSProtocol::InitializeResponse.new(message.id, result)
        @transport.send_message(response.to_json)
      end

      private def handle_shutdown(message : LSProtocol::ShutdownRequest) : Nil
        response = LSProtocol::ShutdownResponse.new(message.id, nil)
        @transport.send_message(response.to_json)
      end

      private def handle_did_open(message : LSProtocol::DidOpenTextDocumentNotification) : Nil
        doc = message.params.text_document
        document = @documents.open(doc.uri, doc.text, doc.version)
        result = @analyzer.analyze(doc.text)
        document.template = result.template
        document.symbols = result.symbols
        publish_diagnostics(doc.uri, doc.version, Mapper.to_lsp_diagnostics(result.diagnostics))
      end

      private def handle_did_change(message : LSProtocol::DidChangeTextDocumentNotification) : Nil
        doc = message.params.text_document
        existing = @documents.fetch(doc.uri)
        text = existing ? existing.text : ""
        updated = apply_changes(text, message.params.content_changes)
        document = @documents.update(doc.uri, updated, doc.version)
        result = @analyzer.analyze(updated)
        document.template = result.template
        document.symbols = result.symbols
        publish_diagnostics(doc.uri, doc.version, Mapper.to_lsp_diagnostics(result.diagnostics))
      end

      private def handle_did_close(message : LSProtocol::DidCloseTextDocumentNotification) : Nil
        uri = message.params.text_document.uri
        @documents.close(uri)
        publish_diagnostics(uri, nil, Array(LSProtocol::Diagnostic).new)
      end

      private def apply_changes(
        text : String,
        changes : Array(LSProtocol::TextDocumentContentChangeEvent),
      ) : String
        updated = text
        changes.each do |change|
          case change
          when LSProtocol::TextDocumentContentChangeWholeDocument
            updated = change.text
          when LSProtocol::TextDocumentContentChangePartial
            @io_err.puts "LSP: incremental change received but full sync is enabled"
          end
        end
        updated
      end

      private def publish_diagnostics(
        uri : URI,
        version : Int32?,
        diagnostics : Array(LSProtocol::Diagnostic),
      ) : Nil
        params = LSProtocol::PublishDiagnosticsParams.new(diagnostics, uri, version)
        notification = LSProtocol::PublishDiagnosticsNotification.new(params)
        @transport.send_message(notification.to_json)
      end

      private def handle_message(message : LSProtocol::Message) : Nil
        case message
        when LSProtocol::InitializeRequest
          handle_initialize(message)
        when LSProtocol::ShutdownRequest
          handle_shutdown(message)
        when LSProtocol::ExitNotification
          @running = false
        when LSProtocol::InitializedNotification
          # No-op for now.
        when LSProtocol::DidOpenTextDocumentNotification
          handle_did_open(message)
        when LSProtocol::DidChangeTextDocumentNotification
          handle_did_change(message)
        when LSProtocol::DidCloseTextDocumentNotification
          handle_did_close(message)
        when LSProtocol::HoverRequest
          handle_hover(message)
        when LSProtocol::DefinitionRequest
          handle_definition(message)
        when LSProtocol::DocumentSymbolRequest
          handle_document_symbols(message)
        when LSProtocol::FoldingRangeRequest
          handle_folding_ranges(message)
        else
          # Ignore unsupported messages for now.
        end
      end

      private def handle_hover(message : LSProtocol::HoverRequest) : Nil
        params = message.params
        uri = params.text_document.uri
        document = @documents.fetch(uri)
        hover = nil
        if document
          resolver = Resolver.new(document)
          reference = resolver.reference_at(params.position)
          if reference
            definition = resolver.definition_for(reference.name)
            contents = hover_contents(reference.name, definition)
            hover = LSProtocol::Hover.new(contents, Mapper.to_lsp_range(reference.span))
          end
        end
        response = LSProtocol::HoverResponse.new(message.id, hover)
        @transport.send_message(response.to_json)
      end

      private def handle_definition(message : LSProtocol::DefinitionRequest) : Nil
        params = message.params
        uri = params.text_document.uri
        document = @documents.fetch(uri)
        result = nil
        if document
          resolver = Resolver.new(document)
          reference = resolver.reference_at(params.position)
          if reference
            definition = resolver.definition_for(reference.name)
            target_span = definition ? definition.span : reference.span
            result = LSProtocol::Location.new(Mapper.to_lsp_range(target_span), uri)
          end
        end
        response = LSProtocol::DefinitionResponse.new(message.id, result)
        @transport.send_message(response.to_json)
      end

      private def handle_document_symbols(message : LSProtocol::DocumentSymbolRequest) : Nil
        uri = message.params.text_document.uri
        document = @documents.fetch(uri)
        result = Array(LSProtocol::DocumentSymbol).new
        if document
          resolver = Resolver.new(document)
          resolver.document_symbols.each do |definition|
            range = Mapper.to_lsp_range(definition.span)
            result << LSProtocol::DocumentSymbol.new(
              definition.kind,
              definition.name,
              range,
              range,
              detail: definition.detail,
            )
          end
        end
        response = LSProtocol::DocumentSymbolResponse.new(message.id, result)
        @transport.send_message(response.to_json)
      end

      private def handle_folding_ranges(message : LSProtocol::FoldingRangeRequest) : Nil
        uri = message.params.text_document.uri
        document = @documents.fetch(uri)
        result = Array(LSProtocol::FoldingRange).new
        if document
          resolver = Resolver.new(document)
          resolver.folding_spans.each do |span|
            range = Mapper.foldable_range(span)
            result << range if range
          end
        end
        response = LSProtocol::FoldingRangeResponse.new(message.id, result)
        @transport.send_message(response.to_json)
      end

      private def hover_contents(name : String, definition : SymbolDefinition?) : LSProtocol::MarkupContent
        detail = definition.try(&.detail)
        label = definition ? definition.kind.to_s.downcase : "symbol"
        text = if detail
                 "**#{name}** (#{label})\n\n`#{detail}`"
               else
                 "**#{name}** (#{label})"
               end
        LSProtocol::MarkupContent.new(LSProtocol::MarkupKind::Markdown, text)
      end
    end
  end
end
