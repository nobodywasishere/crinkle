# Phase 26 — MCP Foundation (Detailed Plan)

## Objectives
- Set up core MCP (Model Context Protocol) infrastructure.
- Implement JSON-RPC 2.0 message handling.
- Establish stdio transport for AI assistant communication.
- Enable AI assistants (Claude, etc.) to interact with crinkle.

## Priority
**MEDIUM**

## Background

MCP (Model Context Protocol) is an open protocol from Anthropic that standardizes communication between AI applications and external tools/resources. While LSP (Phases 20-25) targets editor integration, MCP enables AI assistant integration.

**Key Differences from LSP:**
- MCP is stateless (request/response) vs LSP's document state management
- MCP exposes tools (actions) and resources (data) vs LSP's language features
- MCP targets AI assistants vs LSP's editor clients

## Scope (Phase 26)
- Create `src/mcp/` directory structure
- Implement JSON-RPC 2.0 message parsing and serialization
- Implement MCP protocol types
- Implement stdio transport
- Implement server lifecycle (initialize, shutdown)
- Add CLI command: `crinkle mcp`

## File Structure
```
src/
  mcp/
    server.cr       # Main MCP server class
    protocol.cr     # JSON-RPC message types and MCP protocol structs
    transport.cr    # stdio transport layer for MCP communication
```

## Features
- `initialize` request/response with server capabilities
- `notifications/initialized` handling
- `shutdown` lifecycle
- Server info and capabilities declaration
- Tool list declaration (actual tools in Phase 27)
- Resource list declaration (actual resources in Phase 28)

## API Design

### Server Class
```crystal
module Crinkle::MCP
  class Server
    @transport : Transport
    @initialized : Bool = false

    def initialize(@transport)
    end

    def run
      loop do
        message = @transport.read_message
        break if message.nil?
        response = handle_message(message)
        @transport.write_message(response) if response
      end
    end

    private def handle_message(message : Message) : Message?
      case message
      when InitializeRequest
        handle_initialize(message)
      when InitializedNotification
        @initialized = true
        nil
      when ShutdownRequest
        handle_shutdown(message)
      when ToolCallRequest
        handle_tool_call(message)
      when ResourceReadRequest
        handle_resource_read(message)
      when ListToolsRequest
        handle_list_tools(message)
      when ListResourcesRequest
        handle_list_resources(message)
      else
        error_response(message.id, -32601, "Method not found")
      end
    end

    private def handle_initialize(request : InitializeRequest) : InitializeResponse
      InitializeResponse.new(
        id: request.id,
        result: ServerCapabilities.new(
          name: "crinkle",
          version: Crinkle::VERSION,
          tools: true,
          resources: true,
          prompts: true
        )
      )
    end
  end
end
```

### Protocol Types
```crystal
module Crinkle::MCP
  # Base message types
  abstract class Message
    getter id : Int32 | String | Nil
    getter jsonrpc : String = "2.0"
  end

  class Request < Message
    getter method : String
    getter params : JSON::Any?
  end

  class Response < Message
    getter result : JSON::Any?
    getter error : ErrorObject?
  end

  class Notification < Message
    getter method : String
    getter params : JSON::Any?
  end

  # MCP-specific types
  class ServerCapabilities
    getter name : String
    getter version : String
    getter tools : Bool
    getter resources : Bool
    getter prompts : Bool
  end

  class InitializeRequest < Request
    # params: { protocolVersion, capabilities, clientInfo }
  end

  class InitializeResponse < Response
    # result: ServerCapabilities
  end

  class ToolDefinition
    getter name : String
    getter description : String
    getter inputSchema : JSON::Any  # JSON Schema
  end

  class ResourceDefinition
    getter uri : String
    getter name : String
    getter description : String
    getter mimeType : String?
  end
end
```

### Transport Layer
```crystal
module Crinkle::MCP
  class Transport
    def initialize(@input : IO = STDIN, @output : IO = STDOUT)
    end

    def read_message : Message?
      # Read Content-Length header
      header = @input.gets
      return nil if header.nil?

      if match = header.match(/Content-Length: (\d+)/)
        length = match[1].to_i
        @input.gets  # Empty line
        body = @input.read_string(length)
        parse_message(body)
      else
        nil
      end
    end

    def write_message(message : Message)
      json = message.to_json
      @output.print "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
      @output.flush
    end

    private def parse_message(json : String) : Message
      # Parse JSON-RPC message into typed Message
    end
  end
end
```

## Acceptance Criteria
- MCP server starts via `crinkle mcp` command
- Server responds to `initialize` with capabilities
- Server handles `shutdown` gracefully
- Server declares available tools (empty list initially)
- Server declares available resources (empty list initially)
- JSON-RPC 2.0 protocol compliance

## Checklist
- [ ] Create `src/mcp/` directory structure
- [ ] Implement JSON-RPC 2.0 message parsing
- [ ] Implement JSON-RPC 2.0 message serialization
- [ ] Implement MCP protocol types (InitializeParams, ServerCapabilities, etc.)
- [ ] Implement stdio transport (Content-Length headers)
- [ ] Implement `initialize` request handler
- [ ] Implement `initialized` notification handler
- [ ] Implement `shutdown` request handler
- [ ] Implement `tools/list` with empty tool list
- [ ] Implement `resources/list` with empty resource list
- [ ] Add `mcp` subcommand to CLI
- [ ] Add basic logging/tracing for debugging
- [ ] Test with MCP inspector or Claude Code

## Dependencies
- None (foundation phase)

## Testing Strategy
- Unit tests for message parsing/serialization
- Unit tests for transport layer
- Integration test with MCP inspector tool
- Manual test with Claude Code

## References
- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [MCP SDK](https://github.com/modelcontextprotocol/sdk)
