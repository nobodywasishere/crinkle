# Phase 25a — LSP Advanced Features

## Objectives
- Add code actions for quick fixes and refactoring
- Implement rename symbol for variables, macros, and blocks
- Add workspace-wide symbol search
- Enhance editing experience with document highlights and links

## Priority
**LOW** - Quality of life improvements building on Phase 23-25

## Motivation

With the core LSP features complete (diagnostics, completions, hover, go-to-definition, references), these advanced features provide the polish expected from a production-quality language server:

- Code actions turn diagnostics into one-click fixes
- Rename symbol enables safe refactoring
- Workspace symbols help navigate large template codebases
- Document highlights improve code comprehension

## Features

### 1. Code Actions (`textDocument/codeAction`)

Provide quick fixes for common issues:

#### Fix Typos
```jinja
{{ user.emial }}
        ^^^^^
   ⚡ Quick fix: Change 'emial' to 'email'
```

When inference detects a possible typo, offer to fix it.

#### Auto-Import Macro
```jinja
{{ button("Submit") }}
   ^^^^^^
   ⚡ Quick fix: Import 'button' from "macros/buttons.html.j2"
```

When an unknown function matches a macro in another analyzed template.

#### Close Unclosed Tag
```jinja
{% if condition %}
  content
{% endif
   ^^^^^
   ⚡ Quick fix: Add missing '%}'
```

#### Remove Unused Import
```jinja
{% from "macros.html.j2" import button, icon %}
                                        ^^^^
   ⚡ Quick fix: Remove unused import 'icon'
```

When an imported macro is never used in the template.

#### Convert Deprecated Syntax
```jinja
{% include "header.j2" with context %}
                       ^^^^^^^^^^^^
   ⚡ Quick fix: Remove deprecated 'with context' (always implicit)
```

### 2. Rename Symbol (`textDocument/rename`, `textDocument/prepareRename`)

Safe renaming across templates:

#### Rename Variable
```jinja
{% set user_name = "Alice" %}
      ^^^^^^^^^
      Rename to: username

      Updates all references in file
```

#### Rename Macro
```jinja
{% macro render_button(text) %}
         ^^^^^^^^^^^^^
         Rename to: button

         Updates:
         - Definition in this file
         - All call sites in this file
         - Import statements in other files (if exported)
```

#### Rename Block
```jinja
{% block sidebar %}
         ^^^^^^^
         Rename to: aside

         Updates:
         - Definition in parent template
         - All overrides in child templates
```

### 3. Workspace Symbols (`workspace/symbol`)

Find symbols across all templates:

```
Query: "button"
Results:
  📦 button (macro) - macros/buttons.html.j2:5
  📦 button_group (macro) - macros/buttons.html.j2:15
  📦 icon_button (macro) - macros/buttons.html.j2:25
  🔲 button_container (block) - layouts/base.html.j2:42
```

Symbol kinds:
- Macros → Method
- Blocks → Class
- Set variables → Variable

### 4. Document Highlights (`textDocument/documentHighlight`)

Highlight all occurrences when cursor is on a symbol:

```jinja
{% for item in items %}     ← item highlighted (write)
  {{ item.name }}           ← item highlighted (read)
  {{ item.price }}          ← item highlighted (read)
{% endfor %}
```

Highlight kinds:
- `Write` - Definition site (for loop var, set statement, macro param)
- `Read` - Usage site

### 5. Document Links (`textDocument/documentLink`)

Make template paths clickable without requiring go-to-definition:

```jinja
{% extends "layouts/base.html.j2" %}
            ^^^^^^^^^^^^^^^^^^^^^^
            Click to open file

{% include "partials/header.j2" %}
            ^^^^^^^^^^^^^^^^^^^^
            Click to open file
```

Unlike go-to-definition:
- Shows underline/link decoration in editor
- Works without cursor positioning
- Can show tooltip with resolved path

### 6. Inlay Hints (`textDocument/inlayHint`)

Show inline hints for clarity:

#### Parameter Names
```jinja
{{ button(/* text: */ "Submit", /* style: */ "primary") }}
```

#### Inferred Types (optional, may be noisy)
```jinja
{% set count /* : int */ = items | length %}
{% set name /* : string */ = user.name %}
```

#### Inferred Types for `set` Variables
```jinja
{% set foo /* Int64 */ = 1 %}
```

## Implementation

### Code Action Provider

```crystal
class CodeActionProvider
  def code_actions(uri : String, range : Range, context : CodeActionContext) : Array(CodeAction)
    actions = Array(CodeAction).new

    # Check diagnostics in range for fixable issues
    context.diagnostics.each do |diag|
      case diag.code
      when "Inference/PossibleTypo"
        actions << typo_fix_action(uri, diag)
      when "Lint/UnknownFunction"
        actions.concat(import_macro_actions(uri, diag))
      when "Syntax/UnclosedTag"
        actions << close_tag_action(uri, diag)
      end
    end

    actions
  end

  private def typo_fix_action(uri : String, diag : Diagnostic) : CodeAction
    # Extract suggestion from message "Did you mean 'X'?"
    suggestion = extract_suggestion(diag.message)

    CodeAction.new(
      title: "Change to '#{suggestion}'",
      kind: CodeActionKind::QuickFix,
      diagnostics: [diag],
      edit: WorkspaceEdit.new(
        changes: {uri => [TextEdit.new(range: diag.range, new_text: suggestion)]}
      )
    )
  end
end
```

### Rename Provider

```crystal
class RenameProvider
  def prepare_rename(uri : String, position : Position) : PrepareRenameResult?
    # Find symbol at position
    # Return range and placeholder text if renameable
  end

  def rename(uri : String, position : Position, new_name : String) : WorkspaceEdit?
    symbol = find_symbol_at(uri, position)
    return nil unless symbol

    edits = Hash(String, Array(TextEdit)).new

    case symbol
    when VariableSymbol
      # Find all references in current file
      refs = find_variable_references(uri, symbol.name)
      edits[uri] = refs.map { |r| TextEdit.new(range: r, new_text: new_name) }

    when MacroSymbol
      # Find definition and all call sites
      # May span multiple files if macro is imported
      collect_macro_rename_edits(symbol, new_name, edits)

    when BlockSymbol
      # Find in parent and all child templates
      collect_block_rename_edits(symbol, new_name, edits)
    end

    WorkspaceEdit.new(changes: edits)
  end
end
```

### Workspace Symbol Provider

```crystal
class WorkspaceSymbolProvider
  def symbols(query : String) : Array(SymbolInformation)
    results = Array(SymbolInformation).new

    # Search all analyzed templates
    @inference.all_macros.each do |uri, macros|
      macros.each do |macro|
        if fuzzy_match?(macro.name, query)
          results << SymbolInformation.new(
            name: macro.name,
            kind: SymbolKind::Method,
            location: Location.new(uri: uri, range: macro.range)
          )
        end
      end
    end

    @inference.all_blocks.each do |uri, blocks|
      blocks.each do |block|
        if fuzzy_match?(block.name, query)
          results << SymbolInformation.new(
            name: block.name,
            kind: SymbolKind::Class,
            location: Location.new(uri: uri, range: block.range)
          )
        end
      end
    end

    results.sort_by { |s| -match_score(s.name, query) }
  end
end
```

### Document Highlight Provider

```crystal
class DocumentHighlightProvider
  def highlights(uri : String, text : String, position : Position) : Array(DocumentHighlight)
    symbol = find_symbol_at(uri, text, position)
    return Array(DocumentHighlight).new unless symbol

    highlights = Array(DocumentHighlight).new

    # Find definition (write highlight)
    if def_span = symbol.definition_span
      highlights << DocumentHighlight.new(
        range: span_to_range(def_span),
        kind: DocumentHighlightKind::Write
      )
    end

    # Find all usages (read highlights)
    find_references(uri, text, symbol.name).each do |ref|
      highlights << DocumentHighlight.new(
        range: ref,
        kind: DocumentHighlightKind::Read
      )
    end

    highlights
  end
end
```

### Document Link Provider

```crystal
class DocumentLinkProvider
  def links(uri : String, text : String) : Array(DocumentLink)
    links = Array(DocumentLink).new

    # Find all template references
    find_template_references(text).each do |ref|
      resolved = resolve_template_path(uri, ref.path)
      next unless resolved && File.exists?(resolved)

      links << DocumentLink.new(
        range: ref.range,
        target: "file://#{resolved}",
        tooltip: "Open #{ref.path}"
      )
    end

    links
  end
end
```

## Acceptance Criteria

### Code Actions
- [x] Typo quick fix works from diagnostic
- [x] Auto-import suggests macros from other templates
- [x] Close tag fix adds missing `%}` or tag name
- [x] Code actions appear in editor lightbulb menu

### Rename Symbol
- [x] Variables can be renamed within file
- [x] Macros can be renamed (updates call sites)
- [x] Blocks can be renamed across parent/child templates
- [x] Prepare rename returns valid range
- [x] Invalid renames rejected (keywords, etc.)

### Workspace Symbols
- [x] Macros searchable across workspace
- [x] Blocks searchable across workspace
- [x] Fuzzy matching works
- [x] Results sorted by relevance

### Document Highlights
- [x] Variables highlighted on cursor
- [x] Macro names highlighted on cursor
- [x] Write vs read distinction shown

### Document Links
- [x] Template paths show as links
- [x] Clicking link opens file
- [x] Invalid paths not linked

### Inlay Hints
- [x] Parameter name hints for macro calls
- [x] Hints configurable (on/off)
- [x] Inferred type hints for `set` variables

## Checklist

### Code Actions
- [x] Create `CodeActionProvider` class
- [x] Implement typo quick fix
- [x] Implement auto-import for macros
- [x] Implement close unclosed tag
- [x] Implement remove unused import
- [x] Wire up `textDocument/codeAction` handler
- [x] Add `codeActionProvider` to server capabilities

### Rename Symbol
- [x] Create `RenameProvider` class
- [x] Implement `prepareRename` for validation
- [x] Implement variable rename (single file)
- [x] Implement macro rename (cross-file)
- [x] Implement block rename (inheritance chain)
- [x] Wire up `textDocument/rename` handler
- [x] Wire up `textDocument/prepareRename` handler
- [x] Add `renameProvider` to server capabilities

### Workspace Symbols
- [x] Create `WorkspaceSymbolProvider` class
- [x] Index macros from inference engine
- [x] Index blocks from inference engine
- [x] Implement fuzzy matching
- [x] Wire up `workspace/symbol` handler
- [x] Add `workspaceSymbolProvider` to server capabilities

### Document Highlights
- [x] Create `DocumentHighlightProvider` class
- [x] Implement variable highlights
- [x] Implement macro highlights
- [x] Wire up `textDocument/documentHighlight` handler
- [x] Add `documentHighlightProvider` to server capabilities

### Document Links
- [x] Create `DocumentLinkProvider` class
- [x] Parse template references from text
- [x] Resolve paths to file URIs
- [x] Wire up `textDocument/documentLink` handler
- [x] Add `documentLinkProvider` to server capabilities

### Inlay Hints
- [x] Create `InlayHintProvider` class
- [x] Implement parameter name hints
- [x] Add configuration option to enable/disable
- [x] Wire up `textDocument/inlayHint` handler
- [x] Add `inlayHintProvider` to server capabilities
- [x] Add inferred type hints for `set` variables

### Testing
- [ ] Unit tests for each provider
- [ ] Integration tests with sample templates
- [ ] Test cross-file rename scenarios
- [ ] Test workspace symbol search performance

## Dependencies

- **Phase 23**: Go-to-definition, references (provides foundation)
- **Phase 25**: Caching, performance (required for workspace-wide features)

## Open Questions

1. **Rename scope**: Should macro rename update imports in unopened files?
   - Proposal: Only rename in files currently in inference engine cache

2. **Inlay hint verbosity**: Parameter hints can be noisy. Enable by default?
   - Proposal: Off by default, configurable via settings

3. **Code action priority**: How to order multiple available fixes?
   - Proposal: Typo fixes first, then imports, then syntax fixes

## References

- [LSP Code Action](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_codeAction)
- [LSP Rename](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_rename)
- [LSP Workspace Symbol](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspace_symbol)
- [LSP Document Highlight](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentHighlight)
- [LSP Document Link](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentLink)
- [LSP Inlay Hint](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_inlayHint)
