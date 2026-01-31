# Phase 23 — LSP Hover & Navigation (Detailed Plan)

## Objectives
- Provide contextual information on hover.
- Enable go-to-definition for template constructs.
- Optionally support find references.

## Priority
**LOW**

## Scope (Phase 23)
- Implement `textDocument/hover` for variables, filters, tests, macros, blocks.
- Implement `textDocument/definition` for navigation.
- Optionally implement `textDocument/references`.

## File Structure
```
src/
  lsp/
    hover.cr       # Hover provider
    definition.cr  # Go-to-definition provider
    references.cr  # Find references provider (optional)
```

## Features

### Hover (`textDocument/hover`)
Show info for:
- **Variables**: type, source location, value hint
- **Filters**: signature, description
- **Tests**: signature, description
- **Macros**: parameters, docstring
- **Blocks**: inheritance chain

### Go-to-Definition (`textDocument/definition`)
Jump to:
- Variable definitions (set statements)
- Macro definitions
- Block definitions
- Included/extended templates

### Find References (`textDocument/references`) - Optional
Find usages of:
- Variables
- Macros
- Blocks

## API Design

### Position-to-Node Lookup
```crystal
module Crinkle::LSP
  class NodeResolver
    def initialize(@ast : AST::Template, @source : String)
    end

    def node_at(line : Int32, column : Int32) : AST::Node?
      # Walk AST to find node containing position
    end

    def symbol_at(line : Int32, column : Int32) : Symbol?
      # Return semantic symbol (variable, filter, etc.)
    end
  end
end
```

### Hover Provider
```crystal
module Crinkle::LSP
  class HoverProvider
    def hover(document : Document, position : Position) : Hover?
      resolver = NodeResolver.new(document.ast, document.text)
      symbol = resolver.symbol_at(position.line, position.character)

      case symbol
      when VariableSymbol
        hover_for_variable(symbol)
      when FilterSymbol
        hover_for_filter(symbol)
      when MacroSymbol
        hover_for_macro(symbol)
      else
        nil
      end
    end

    private def hover_for_filter(symbol : FilterSymbol) : Hover
      # Look up filter in schema or builtins
      Hover.new(
        contents: MarkupContent.new(
          kind: "markdown",
          value: "**#{symbol.name}**\n\n#{symbol.description}"
        )
      )
    end
  end
end
```

### Definition Provider
```crystal
module Crinkle::LSP
  class DefinitionProvider
    def definition(document : Document, position : Position) : Location?
      resolver = NodeResolver.new(document.ast, document.text)
      symbol = resolver.symbol_at(position.line, position.character)

      case symbol
      when VariableSymbol
        find_variable_definition(document, symbol.name)
      when MacroSymbol
        find_macro_definition(document, symbol.name)
      when BlockSymbol
        find_block_definition(document, symbol.name)
      else
        nil
      end
    end
  end
end
```

## Acceptance Criteria
- Hover shows useful information for all symbol types.
- Go-to-definition navigates to correct locations.
- Cross-file navigation works for includes/extends.
- Information from schema integrated when available.

## Checklist
- [ ] Implement position-to-AST-node lookup
- [ ] Implement `textDocument/hover` request handler
- [ ] Add hover content for variables
- [ ] Add hover content for filters (from std library + schema)
- [ ] Add hover content for tests (from std library + schema)
- [ ] Add hover content for macros
- [ ] Add hover content for custom functions (from schema)
- [ ] Implement `textDocument/definition` request handler
- [ ] Add go-to-definition for variables
- [ ] Add go-to-definition for macros
- [ ] Add go-to-definition for blocks
- [ ] Add go-to-definition for includes/extends (cross-file)
- [ ] Integrate schema/stub information for enhanced hover
