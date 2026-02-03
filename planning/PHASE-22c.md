# Phase 22c — LSP Enhancements

## Objectives
- Add variable and block name completions
- Implement go-to-definition for template references
- Add file watcher for config/schema hot reload

## Priority
**LOW** - Quality of life improvements

## Motivation

With Phase 22b complete (schema-aware completions, hover, signature help, inference, typo detection), these enhancements round out the IDE experience:

- Variable completions reduce typing for common context variables
- Block name completions help when overriding blocks in child templates
- Go-to-definition enables navigation between related templates
- File watcher eliminates need to restart LSP after config changes

## Features

### Variable Completions

When typing `{{ █`, suggest known variables from inference:

```jinja
{% for item in items %}
  {{ i█ }}
     ↓
  item    (from for loop)
  items   (context variable)
```

Variables to track:
- Context variables (from template usage)
- For loop variables (`item` in `{% for item in items %}`)
- Set variables (`{% set x = ... %}`)
- Macro parameters

### Block Name Completions

When typing `{% block █`, suggest block names from extended parent:

```jinja
{% extends "base.html.j2" %}
{% block █ %}
        ↓
  content   (defined in base.html.j2)
  sidebar   (defined in base.html.j2)
  footer    (defined in base.html.j2)
```

Requires:
- Parsing the extended template
- Extracting block names from parent
- Following extends chains

### Macro Completions

When typing `{% call █`, suggest defined macros:

```jinja
{% macro button(text, style="primary") %}...{% endmacro %}
{% macro icon(name) %}...{% endmacro %}

{% call █ %}
       ↓
  button(text, style="primary")
  icon(name)
```

### Go-to-Definition

Ctrl+click on template paths to navigate:

```jinja
{% extends "base.html.j2" %}
            ^^^^^^^^^^^^^^
            → Opens base.html.j2

{% include "partials/header.j2" %}
            ^^^^^^^^^^^^^^^^^^^
            → Opens partials/header.j2
```

Supported references:
- `{% extends "..." %}`
- `{% include "..." %}`
- `{% import "..." %}`
- `{% from "..." import ... %}`

### File Watcher

Auto-reload on file changes:

| File | Action |
|------|--------|
| `.crinkle/config.yaml` | Reload config, reinitialize providers |
| `.crinkle/schema.json` | Reload schema, update completions |
| `*.j2` templates | Re-run inference for relationships |

Implementation options:
1. Poll-based (check mtime periodically)
2. `workspace/didChangeWatchedFiles` notification from client
3. Native file watcher (platform-specific)

Option 2 is preferred as most LSP clients support it.

## Implementation

### Variable Tracking in Inference Engine

```crystal
class InferenceEngine
  # Existing: variable -> properties
  @usage : Hash(String, Hash(String, Set(String)))

  # New: track all known variables per template
  @variables : Hash(String, Set(String))

  def variables_for(uri : String) : Array(String)
    @variables[uri]?.try(&.to_a) || Array(String).new
  end
end
```

### Block Extraction

```crystal
def blocks_for(uri : String) : Array(String)
  # Parse extended template
  # Extract block names from AST
  # Cache results
end
```

### Definition Provider

```crystal
class DefinitionProvider
  def definition(uri : String, text : String, position : Position) : Location?
    # Find template reference at position
    # Resolve to file path
    # Return Location
  end
end
```

### File Watcher via Client

```crystal
# In handle_initialize, register for file watching
capabilities = ServerCapabilities.new(
  # ...existing...
  workspace: WorkspaceCapabilities.new(
    file_operations: FileOperationOptions.new(
      did_create: FileOperationRegistration.new(
        filters: [FileOperationFilter.new(pattern: "**/*.j2")]
      )
    )
  )
)

# Handle workspace/didChangeWatchedFiles notification
def handle_did_change_watched_files(params)
  params.changes.each do |change|
    case change.uri
    when /config\.yaml$/
      reload_config
    when /schema\.json$/
      reload_schema
    end
  end
end
```

## Acceptance Criteria

### Variable Completions
- [x] Track variables from for loops, set statements, macro params
- [x] Suggest variables in `{{ █ }}` context
- [x] Include variables from extended/included templates

### Block Completions
- [x] Extract block names from parent templates
- [x] Suggest in `{% block █ %}` context
- [x] Follow extends chains

### Macro Completions
- [x] Track macro definitions with signatures
- [x] Suggest in `{% call █ %}` context
- [x] Show parameter hints

### Go-to-Definition
- [x] Handle extends/include/import/from-import
- [x] Resolve relative template paths
- [x] Return correct file location

### File Watcher
- [x] Register for workspace file events
- [x] Reload config on change
- [x] Reload schema on change
- [x] Re-run inference on template changes

## Status

**COMPLETE** - All Phase 22c features implemented.

## Dependencies

- **Phase 22b**: Inference engine, schema provider, completion provider

## Checklist

### Variable Completions
- [x] Add variable tracking to InferenceEngine
- [x] Track for loop variables
- [x] Track set variables
- [x] Track macro parameters
- [x] Update CompletionProvider for variable context
- [x] Include cross-template variables

### Block Completions
- [x] Add block extraction to InferenceEngine
- [x] Parse extended templates on demand
- [x] Cache block names
- [x] Update CompletionProvider for block context

### Macro Completions
- [x] Track macro definitions with signatures
- [x] Update CompletionProvider for call context

### Go-to-Definition
- [x] Create DefinitionProvider class
- [x] Parse template references at position
- [x] Resolve template paths
- [x] Wire up textDocument/definition handler

### File Watcher
- [x] Add workspace capabilities
- [x] Handle didChangeWatchedFiles notification
- [x] Implement config reload
- [x] Implement schema reload
- [ ] Test with VS Code (manual testing required)
