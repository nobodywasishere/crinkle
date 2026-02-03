# Phase 23 — LSP Hover & Navigation Enhancements

## Objectives
- Extend hover to cover variables, macros, blocks, and tags
- Add go-to-definition for variables, macros, and blocks
- Refactor hover context detection to use token-based analysis
- Optionally support find references

## Priority
**LOW**

## Already Implemented (Phase 22b/22c)
- ✅ Go-to-definition for template paths (extends/include/import/from)

## Existing But Broken
- ⚠️ Hover for filters/tests/functions exists but uses regex-based context detection that doesn't work reliably

## Scope (Phase 23)

### Fix Existing Hover
Refactor HoverProvider to use token-based context detection (like CompletionProvider):
- **Filters**: signature, description, examples
- **Tests**: signature, description
- **Functions**: signature, description

### Add New Hover Support
Extend `textDocument/hover` to support:
- **Variables**: source (for loop, set, macro param, context), inferred type
- **Macros**: parameter signature, docstring if available
- **Blocks**: inheritance chain (which parent defines it)
- **Tags**: description from `Std::Tags::BUILTINS` or schema

### Go-to-Definition Enhancements
Extend `textDocument/definition` to support:
- **Variables**: jump to `{% set %}` or `{% for %}` definition
- **Macros**: jump to `{% macro %}` definition (same file or imported)
- **Blocks**: jump to block definition in parent template

### Find References (Optional)
Implement `textDocument/references` for:
- Variables (all usages)
- Macros (all call sites)
- Blocks (all overrides)

## Features

### Variable Hover
Show variable source and any inferred info:

```jinja
{% for item in items %}
  {{ item }}
     ^^^^^
     item: loop variable
     from: {% for item in items %}
```

```jinja
{% set count = 10 %}
{{ count }}
   ^^^^^
   count: assigned variable
   from: {% set count = 10 %}
```

### Macro Hover
Show macro signature and location:

```jinja
{% call button("Submit") %}
       ^^^^^^
       button(text, style="primary")
       Defined at line 5
```

### Block Hover
Show block inheritance info:

```jinja
{% block content %}
         ^^^^^^^
         block content
         Defined in: base.html.j2
         Overridden in: page.html.j2
```

### Tag Hover
Show tag documentation:

```jinja
{% for item in items %}
   ^^^
   for: Iteration over sequences
   Block tag (requires {% endfor %})
```

### Variable Go-to-Definition
Jump to where variable is defined:

```jinja
{% set username = user.name %}
...
{{ username }}  <- Ctrl+click jumps to set statement
```

### Macro Go-to-Definition
Jump to macro definition:

```jinja
{% from "macros.html.j2" import button %}
{{ button("Click me") }}  <- Ctrl+click jumps to macro in macros.html.j2
```

### Block Go-to-Definition
Jump to block in parent template:

```jinja
{% extends "base.html.j2" %}
{% block content %}  <- Ctrl+click jumps to block in base.html.j2
```

## Technical Approach

### Refactor Hover to Use Token-Based Analysis
The completion provider now uses token-based context detection. Hover should use the same approach for consistency:

```crystal
class HoverProvider
  # Reuse token-based analysis from CompletionProvider
  def hover(text : String, position : Position) : Hover?
    cursor_offset = offset_for_position(text, position)
    tokens = Lexer.new(text).lex_all
    token_index = find_token_at_offset(tokens, cursor_offset)

    # Determine what's being hovered based on token context
    analyze_hover_from_tokens(tokens, token_index)
  end
end
```

### Variable Definition Tracking
Extend InferenceEngine to track definition locations:

```crystal
struct VariableInfo
  property name : String
  property source : VariableSource
  property definition_span : Span?  # Where it's defined
  property detail : String?
end
```

### Cross-File Macro Resolution
When hovering/go-to-definition on an imported macro:
1. Find the import statement
2. Resolve the template path
3. Parse the template
4. Find the macro definition

## Acceptance Criteria
- Hover shows useful information for variables, macros, blocks, and tags
- Go-to-definition works for variables within the same file
- Go-to-definition works for macros (same file and imported)
- Go-to-definition works for blocks in extended templates
- Hover uses consistent token-based detection

## Checklist

### Fix Existing Hover
- [x] Refactor HoverProvider to use token-based context detection
- [x] Fix hover for filters (currently broken)
- [x] Fix hover for tests (currently broken)
- [x] Fix hover for functions (currently broken)

### Add New Hover Support
- [x] Add hover for variables (show source, definition location)
- [x] Add hover for macros (show signature, definition location)
- [x] Add hover for blocks (show inheritance chain)
- [x] Add hover for tags (show description from Std::Tags)

### Go-to-Definition Enhancements
- [x] Extend InferenceEngine to track variable definition spans
- [x] Add go-to-definition for variables (set, for loop vars)
- [x] Add go-to-definition for macros (same file)
- [x] Add go-to-definition for imported macros (cross-file)
- [x] Add go-to-definition for blocks (in parent templates)

### Find References (Optional)
- [x] Implement textDocument/references handler
- [x] Add reference finding for variables
- [x] Add reference finding for macros
- [x] Add reference finding for blocks
