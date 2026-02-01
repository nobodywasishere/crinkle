# Phase 28 — MCP Resources (Template Information) (Detailed Plan)

## Objectives
- Expose crinkle metadata and documentation as MCP resources.
- Provide access to builtin filter/test/function documentation.
- Enable template introspection via resource URIs.
- Support AI assistants in understanding available functionality.

## Priority
**MEDIUM**

## Scope (Phase 28)
- Implement resource handlers for builtins documentation
- Implement template-specific resources (AST, diagnostics)
- Define resource URI scheme
- Support resource subscriptions (optional)

## File Structure
```
src/
  mcp/
    resources.cr              # Resource registry and dispatch
    resources/
      builtins.cr             # Filter/test/function resources
      templates.cr            # Template AST and diagnostics
      docs.cr                 # Documentation resources
```

## Resources Specification

### URI Scheme
```
crinkle://builtins/filters              # List all filters
crinkle://builtins/tests                # List all tests
crinkle://builtins/functions            # List all functions
crinkle://docs/filter/{name}            # Filter documentation
crinkle://docs/test/{name}              # Test documentation
crinkle://docs/function/{name}          # Function documentation
crinkle://template/{path}/ast           # Template AST
crinkle://template/{path}/diagnostics   # Template diagnostics
```

### 1. crinkle://builtins/filters
**Description:** List all available filters with signatures.

**Response:**
```json
{
  "uri": "crinkle://builtins/filters",
  "mimeType": "application/json",
  "contents": {
    "filters": [
      {
        "name": "upper",
        "signature": "(value: string) -> string",
        "description": "Convert string to uppercase",
        "examples": ["{{ \"hello\" | upper }}  {# HELLO #}"]
      },
      {
        "name": "default",
        "signature": "(value: any, default_value: any, boolean: bool = false) -> any",
        "description": "Return default value if value is undefined or empty",
        "examples": ["{{ name | default(\"Anonymous\") }}"]
      },
      {
        "name": "join",
        "signature": "(value: sequence, separator: string = \"\", attribute?: string) -> string",
        "description": "Join sequence elements into a string",
        "examples": ["{{ items | join(\", \") }}"]
      }
    ]
  }
}
```

### 2. crinkle://builtins/tests
**Description:** List all available tests with signatures.

**Response:**
```json
{
  "uri": "crinkle://builtins/tests",
  "mimeType": "application/json",
  "contents": {
    "tests": [
      {
        "name": "defined",
        "signature": "(value: any) -> bool",
        "description": "Check if variable is defined",
        "examples": ["{% if user is defined %}"]
      },
      {
        "name": "divisibleby",
        "signature": "(value: number, num: number) -> bool",
        "description": "Check if value is divisible by num",
        "examples": ["{% if loop.index is divisibleby(3) %}"]
      }
    ]
  }
}
```

### 3. crinkle://builtins/functions
**Description:** List all available functions with signatures.

**Response:**
```json
{
  "uri": "crinkle://builtins/functions",
  "mimeType": "application/json",
  "contents": {
    "functions": [
      {
        "name": "range",
        "signature": "(stop: int) -> sequence\n(start: int, stop: int, step: int = 1) -> sequence",
        "description": "Generate a sequence of numbers",
        "examples": ["{% for i in range(5) %}", "{% for i in range(1, 10, 2) %}"]
      },
      {
        "name": "dict",
        "signature": "(**kwargs) -> mapping",
        "description": "Create a dictionary from keyword arguments",
        "examples": ["{% set d = dict(a=1, b=2) %}"]
      }
    ]
  }
}
```

### 4. crinkle://docs/filter/{name}
**Description:** Detailed documentation for a specific filter.

**Example:** `crinkle://docs/filter/truncate`

**Response:**
```json
{
  "uri": "crinkle://docs/filter/truncate",
  "mimeType": "application/json",
  "contents": {
    "name": "truncate",
    "signature": "(value: string, length: int = 255, killwords: bool = false, end: string = \"...\", leeway: int = 0) -> string",
    "description": "Truncate a string to a specified length",
    "parameters": [
      { "name": "value", "type": "string", "description": "The string to truncate" },
      { "name": "length", "type": "int", "default": "255", "description": "Maximum length" },
      { "name": "killwords", "type": "bool", "default": "false", "description": "If true, cut at exact length; if false, cut at word boundary" },
      { "name": "end", "type": "string", "default": "\"...\"", "description": "String to append if truncated" },
      { "name": "leeway", "type": "int", "default": "0", "description": "Allow this many extra characters before truncating" }
    ],
    "examples": [
      {
        "template": "{{ \"Hello World\" | truncate(5) }}",
        "output": "He...",
        "description": "Basic truncation"
      },
      {
        "template": "{{ \"Hello World\" | truncate(8, false) }}",
        "output": "Hello...",
        "description": "Truncate at word boundary"
      }
    ],
    "related": ["wordwrap", "striptags"]
  }
}
```

### 5. crinkle://template/{path}/ast
**Description:** AST for a template file.

**Example:** `crinkle://template/views/home.html.j2/ast`

**Response:**
```json
{
  "uri": "crinkle://template/views/home.html.j2/ast",
  "mimeType": "application/json",
  "contents": {
    "path": "views/home.html.j2",
    "ast": {
      "type": "Template",
      "nodes": [...]
    },
    "stats": {
      "nodeCount": 42,
      "maxDepth": 5,
      "hasExtends": true,
      "blocks": ["content", "sidebar"],
      "macros": ["render_item"],
      "includes": ["partials/header.html.j2"]
    }
  }
}
```

### 6. crinkle://template/{path}/diagnostics
**Description:** Diagnostics for a template file.

**Example:** `crinkle://template/views/home.html.j2/diagnostics`

**Response:**
```json
{
  "uri": "crinkle://template/views/home.html.j2/diagnostics",
  "mimeType": "application/json",
  "contents": {
    "path": "views/home.html.j2",
    "diagnostics": [
      {
        "severity": "warning",
        "code": "Linter/UnusedMacro",
        "message": "Macro 'helper' is defined but never used",
        "span": { "start": 100, "end": 150, "line": 5, "column": 1 }
      }
    ],
    "summary": {
      "errors": 0,
      "warnings": 1,
      "info": 0
    }
  }
}
```

## API Design

### Resource Registry
```crystal
module Crinkle::MCP
  class ResourceRegistry
    @handlers : Hash(Regex, ResourceHandler)

    def initialize
      @handlers = {} of Regex => ResourceHandler
      register_builtin_handlers
    end

    def register(pattern : Regex, handler : ResourceHandler)
      @handlers[pattern] = handler
    end

    def list : Array(ResourceDefinition)
      [
        ResourceDefinition.new(
          uri: "crinkle://builtins/filters",
          name: "Builtin Filters",
          description: "List of all available Jinja2 filters"
        ),
        ResourceDefinition.new(
          uri: "crinkle://builtins/tests",
          name: "Builtin Tests",
          description: "List of all available Jinja2 tests"
        ),
        ResourceDefinition.new(
          uri: "crinkle://builtins/functions",
          name: "Builtin Functions",
          description: "List of all available Jinja2 functions"
        ),
        ResourceDefinition.new(
          uri: "crinkle://docs/filter/{name}",
          name: "Filter Documentation",
          description: "Detailed documentation for a specific filter"
        ),
        ResourceDefinition.new(
          uri: "crinkle://docs/test/{name}",
          name: "Test Documentation",
          description: "Detailed documentation for a specific test"
        ),
        ResourceDefinition.new(
          uri: "crinkle://docs/function/{name}",
          name: "Function Documentation",
          description: "Detailed documentation for a specific function"
        ),
        ResourceDefinition.new(
          uri: "crinkle://template/{path}/ast",
          name: "Template AST",
          description: "Abstract syntax tree for a template file"
        ),
        ResourceDefinition.new(
          uri: "crinkle://template/{path}/diagnostics",
          name: "Template Diagnostics",
          description: "Diagnostics (errors, warnings) for a template file"
        )
      ]
    end

    def read(uri : String) : ResourceContents
      @handlers.each do |pattern, handler|
        if match = uri.match(pattern)
          return handler.read(uri, match)
        end
      end
      raise ResourceNotFound.new(uri)
    end

    private def register_builtin_handlers
      register(/^crinkle:\/\/builtins\/(filters|tests|functions)$/, BuiltinsHandler.new)
      register(/^crinkle:\/\/docs\/(filter|test|function)\/(.+)$/, DocsHandler.new)
      register(/^crinkle:\/\/template\/(.+)\/(ast|diagnostics)$/, TemplateHandler.new)
    end
  end

  abstract class ResourceHandler
    abstract def read(uri : String, match : Regex::MatchData) : ResourceContents
  end

  struct ResourceContents
    getter uri : String
    getter mimeType : String
    getter contents : JSON::Any
  end
end
```

### Builtin Documentation Storage
```crystal
module Crinkle::MCP::Resources
  # Documentation for each builtin, used by resources
  FILTER_DOCS = {
    "upper" => FilterDoc.new(
      signature: "(value: string) -> string",
      description: "Convert string to uppercase",
      parameters: [
        ParamDoc.new("value", "string", nil, "The string to convert")
      ],
      examples: [
        ExampleDoc.new("{{ \"hello\" | upper }}", "HELLO", "Basic usage")
      ],
      related: ["lower", "capitalize", "title"]
    ),
    # ... more filters
  }

  TEST_DOCS = {
    "defined" => TestDoc.new(
      signature: "(value: any) -> bool",
      description: "Check if a variable is defined (not undefined)",
      # ...
    ),
    # ... more tests
  }

  FUNCTION_DOCS = {
    "range" => FunctionDoc.new(
      signature: "(stop: int) -> sequence | (start: int, stop: int, step: int = 1) -> sequence",
      description: "Generate a sequence of numbers",
      # ...
    ),
    # ... more functions
  }
end
```

## Acceptance Criteria
- All 8 resource types implemented
- Resources return valid JSON with correct MIME type
- Filter/test/function documentation is accurate
- Template resources work with file paths
- `resources/list` returns all resource definitions
- `resources/read` fetches correct resource
- Graceful handling of missing resources

## Checklist
- [ ] Create resource registry and base handler class
- [ ] Implement `crinkle://builtins/filters` resource
- [ ] Implement `crinkle://builtins/tests` resource
- [ ] Implement `crinkle://builtins/functions` resource
- [ ] Implement `crinkle://docs/filter/{name}` resource
- [ ] Implement `crinkle://docs/test/{name}` resource
- [ ] Implement `crinkle://docs/function/{name}` resource
- [ ] Implement `crinkle://template/{path}/ast` resource
- [ ] Implement `crinkle://template/{path}/diagnostics` resource
- [ ] Write documentation for all builtins
- [ ] Wire resources into MCP server
- [ ] Test each resource with MCP inspector
- [ ] Handle missing/invalid resource URIs gracefully

## Dependencies
- Phase 26 (MCP Foundation)
- Phase 27 (MCP Tools) - for shared diagnostic utilities

## Documentation Requirements
Each builtin needs documentation including:
- Signature with types
- Description
- Parameter details (name, type, default, description)
- Examples with expected output
- Related builtins

## Testing Strategy
- Unit tests for resource handlers
- Verify documentation accuracy against implementation
- Integration tests via MCP protocol
- Manual testing with Claude Code
