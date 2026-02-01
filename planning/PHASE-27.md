# Phase 27 — MCP Tools (Template Operations) (Detailed Plan)

## Objectives
- Expose crinkle template operations as MCP tools.
- Enable AI assistants to lex, parse, render, format, and lint templates.
- Provide rich diagnostic information in tool responses.

## Priority
**MEDIUM**

## Scope (Phase 27)
- Implement tool handlers for all crinkle operations
- Define JSON Schema for tool inputs
- Return structured results with diagnostics
- Handle errors gracefully

## File Structure
```
src/
  mcp/
    tools.cr              # Tool registry and dispatch
    tools/
      lex.cr              # crinkle/lex tool
      parse.cr            # crinkle/parse tool
      render.cr           # crinkle/render tool
      format.cr           # crinkle/format tool
      lint.cr             # crinkle/lint tool
      validate.cr         # crinkle/validate tool
```

## Tools Specification

### 1. crinkle/lex
**Description:** Tokenize a Jinja2 template into a token stream.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    }
  },
  "required": ["source"]
}
```

**Output:**
```json
{
  "tokens": [
    {
      "type": "Text",
      "value": "Hello, ",
      "span": { "start": 0, "end": 7, "line": 1, "column": 1 }
    },
    {
      "type": "VarStart",
      "value": "{{",
      "span": { "start": 7, "end": 9, "line": 1, "column": 8 }
    }
  ],
  "diagnostics": []
}
```

### 2. crinkle/parse
**Description:** Parse a Jinja2 template into an AST.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    },
    "pretty": {
      "type": "boolean",
      "description": "Pretty-print the AST JSON",
      "default": true
    }
  },
  "required": ["source"]
}
```

**Output:**
```json
{
  "ast": {
    "type": "Template",
    "nodes": [...]
  },
  "diagnostics": [
    {
      "severity": "error",
      "message": "Unexpected token",
      "span": { "start": 10, "end": 15, "line": 1, "column": 11 },
      "code": "Parser/UnexpectedToken"
    }
  ]
}
```

### 3. crinkle/render
**Description:** Render a Jinja2 template with provided context.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    },
    "context": {
      "type": "object",
      "description": "Variables to pass to the template",
      "default": {}
    },
    "strict": {
      "type": "boolean",
      "description": "Fail on undefined variables",
      "default": false
    }
  },
  "required": ["source"]
}
```

**Output:**
```json
{
  "output": "<h1>Hello, World!</h1>",
  "diagnostics": []
}
```

### 4. crinkle/format
**Description:** Format a Jinja2 template with consistent styling.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    },
    "indent": {
      "type": "integer",
      "description": "Indentation width",
      "default": 2
    }
  },
  "required": ["source"]
}
```

**Output:**
```json
{
  "formatted": "{% if user %}\n  <h1>{{ user.name }}</h1>\n{% endif %}",
  "changed": true,
  "diagnostics": []
}
```

### 5. crinkle/lint
**Description:** Lint a Jinja2 template for issues.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    },
    "rules": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Specific rules to check (all if empty)"
    }
  },
  "required": ["source"]
}
```

**Output:**
```json
{
  "issues": [
    {
      "rule": "DuplicateBlock",
      "severity": "warning",
      "message": "Block 'content' defined multiple times",
      "span": { "start": 50, "end": 70, "line": 5, "column": 1 }
    }
  ],
  "diagnostics": []
}
```

### 6. crinkle/validate
**Description:** Check if a template has valid syntax.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    }
  },
  "required": ["source"]
}
```

**Output:**
```json
{
  "valid": false,
  "errorCount": 2,
  "warningCount": 1,
  "diagnostics": [...]
}
```

## API Design

### Tool Registry
```crystal
module Crinkle::MCP
  class ToolRegistry
    @tools : Hash(String, Tool)

    def initialize
      @tools = {} of String => Tool
      register_builtin_tools
    end

    def register(tool : Tool)
      @tools[tool.name] = tool
    end

    def list : Array(ToolDefinition)
      @tools.values.map(&.definition)
    end

    def call(name : String, arguments : JSON::Any) : JSON::Any
      tool = @tools[name]?
      raise ToolNotFound.new(name) unless tool
      tool.call(arguments)
    end

    private def register_builtin_tools
      register(LexTool.new)
      register(ParseTool.new)
      register(RenderTool.new)
      register(FormatTool.new)
      register(LintTool.new)
      register(ValidateTool.new)
    end
  end

  abstract class Tool
    abstract def name : String
    abstract def description : String
    abstract def input_schema : JSON::Any
    abstract def call(arguments : JSON::Any) : JSON::Any

    def definition : ToolDefinition
      ToolDefinition.new(
        name: name,
        description: description,
        inputSchema: input_schema
      )
    end
  end
end
```

### Example Tool Implementation
```crystal
module Crinkle::MCP::Tools
  class LexTool < Tool
    def name : String
      "crinkle/lex"
    end

    def description : String
      "Tokenize a Jinja2 template into a token stream"
    end

    def input_schema : JSON::Any
      JSON.parse(<<-JSON)
        {
          "type": "object",
          "properties": {
            "source": {
              "type": "string",
              "description": "Template source code"
            }
          },
          "required": ["source"]
        }
      JSON
    end

    def call(arguments : JSON::Any) : JSON::Any
      source = arguments["source"].as_s

      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.tokenize
      diagnostics = lexer.diagnostics

      JSON.parse({
        tokens: tokens.map { |t| serialize_token(t) },
        diagnostics: diagnostics.map { |d| serialize_diagnostic(d) }
      }.to_json)
    end
  end
end
```

## Acceptance Criteria
- All 6 tools implemented and registered
- Tools return structured JSON responses
- Diagnostics included in all tool responses
- Input validation with helpful error messages
- `tools/list` returns all tool definitions
- `tools/call` dispatches to correct handler

## Checklist
- [ ] Create tool registry and base class
- [ ] Implement `crinkle/lex` tool
- [ ] Implement `crinkle/parse` tool
- [ ] Implement `crinkle/render` tool
- [ ] Implement `crinkle/format` tool
- [ ] Implement `crinkle/lint` tool
- [ ] Implement `crinkle/validate` tool
- [ ] Wire tools into MCP server
- [ ] Add input validation for all tools
- [ ] Add comprehensive error handling
- [ ] Test each tool with MCP inspector
- [ ] Document tool schemas

## Dependencies
- Phase 26 (MCP Foundation)

## Testing Strategy
- Unit tests for each tool
- Integration tests via MCP protocol
- Manual testing with Claude Code
