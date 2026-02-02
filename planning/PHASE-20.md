# Phase 20 — LSP Foundation (Detailed Plan)

## Objectives
- Set up core LSP infrastructure for future features.
- Implement document synchronization.
- Establish lifecycle management.

## Priority
**LOW**

## Scope (Phase 20)
- Create `src/lsp/` directory structure.
- Implement JSON-RPC message parsing and serialization.
- Implement LSP protocol types.
- Implement stdio transport.
- Implement document lifecycle.

## File Structure
```
src/
  lsp/
    lsp.cr          # Module entry point and CLI run function
    server.cr       # Main LSP server class
    protocol.cr     # JSON-RPC message types and LSP protocol structs
    transport.cr    # stdio transport layer for LSP communication
    document.cr     # Document and DocumentStore classes
    logger.cr       # File-based logger for LSP debugging
```

## Features
- `initialize` request/response with server capabilities
- `initialized` notification handling
- `shutdown` and `exit` lifecycle
- `textDocument/didOpen` — Track opened documents
- `textDocument/didChange` — Update document content (full sync initially)
- `textDocument/didClose` — Clean up document state
- Document store to maintain open file contents

## API Design

### Server Class
```crystal
module Crinkle::LSP
  class Server
    @documents : DocumentStore
    @transport : Transport

    def initialize(@transport)
      @documents = DocumentStore.new
    end

    def run
      loop do
        message = @transport.read_message
        response = handle_message(message)
        @transport.write_message(response) if response
      end
    end

    private def handle_message(message)
      case message
      when InitializeRequest
        handle_initialize(message)
      when DidOpenNotification
        handle_did_open(message)
      # ... etc
      end
    end
  end
end
```

### Document Store
```crystal
module Crinkle::LSP
  class DocumentStore
    @documents : Hash(String, Document)

    def open(uri : String, text : String, version : Int32)
      @documents[uri] = Document.new(uri, text, version)
    end

    def update(uri : String, text : String, version : Int32)
      @documents[uri]?.try(&.update(text, version))
    end

    def close(uri : String)
      @documents.delete(uri)
    end

    def get(uri : String) : Document?
      @documents[uri]?
    end
  end

  class Document
    getter uri : String
    getter text : String
    getter version : Int32

    def initialize(@uri, @text, @version)
    end

    def update(@text, @version)
    end
  end
end
```

### Transport Layer
```crystal
module Crinkle::LSP
  class Transport
    def initialize(@input : IO, @output : IO)
    end

    def read_message : Message
      # Read Content-Length header
      # Read JSON body
      # Parse into typed message
    end

    def write_message(message : Message)
      # Serialize to JSON
      # Write Content-Length header
      # Write body
    end
  end
end
```

## Acceptance Criteria
- LSP server starts and handles initialize/shutdown.
- Documents tracked on open/change/close.
- Server responds to requests correctly.
- Basic logging for debugging.

## Checklist
- [x] Create `src/lsp/` directory structure
- [x] Implement JSON-RPC message parsing and serialization
- [x] Implement LSP protocol types (InitializeParams, TextDocumentItem, etc.)
- [x] Implement stdio transport (read Content-Length headers, write responses)
- [x] Implement `initialize` with basic server capabilities
- [x] Implement document lifecycle (didOpen, didChange, didClose)
- [x] Create in-memory document store
- [x] Add basic logging/tracing for debugging
- [ ] Test with VS Code or other LSP client
