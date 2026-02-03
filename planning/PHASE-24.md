# Phase 24 — LSP Document Features (Detailed Plan)

## Objectives
- Provide document outline for navigation.
- Enable code folding for template structures.

## Priority
**LOW**

## Scope (Phase 24)
- Implement `textDocument/documentSymbol`.
- Implement `textDocument/foldingRange`.

## Features

### Document Symbols (`textDocument/documentSymbol`)
Outline view showing:
- Blocks
- Macros
- Variables (set statements)
- For loops
- If branches

Hierarchical structure matching template nesting.

### Folding Ranges (`textDocument/foldingRange`)
Code folding for:
- Block tags (`{% block %}...{% endblock %}`)
- Control structures (`{% if %}`, `{% for %}`, etc.)
- Comments (`{# ... #}`)
- Raw blocks (`{% raw %}...{% endraw %}`)

## API Design

### Document Symbols
```crystal
module Crinkle::LSP
  class SymbolProvider
    def document_symbols(document : Document) : Array(DocumentSymbol)
      visitor = SymbolVisitor.new
      visitor.visit(document.ast)
      visitor.symbols
    end
  end

  class SymbolVisitor
    getter symbols : Array(DocumentSymbol)

    def visit(node : AST::Block)
      symbols << DocumentSymbol.new(
        name: node.name,
        kind: SymbolKind::Class,
        range: node_range(node),
        selection_range: name_range(node),
        children: visit_children(node.body)
      )
    end

    def visit(node : AST::Macro)
      symbols << DocumentSymbol.new(
        name: node.name,
        kind: SymbolKind::Method,
        range: node_range(node),
        selection_range: name_range(node)
      )
    end

    def visit(node : AST::Set)
      symbols << DocumentSymbol.new(
        name: node.name,
        kind: SymbolKind::Variable,
        range: node_range(node),
        selection_range: name_range(node)
      )
    end
  end
end
```

### Folding Ranges
```crystal
module Crinkle::LSP
  class FoldingProvider
    def folding_ranges(document : Document) : Array(FoldingRange)
      visitor = FoldingVisitor.new
      visitor.visit(document.ast)
      visitor.ranges
    end
  end

  class FoldingVisitor
    getter ranges : Array(FoldingRange)

    def visit(node : AST::If | AST::For | AST::Block | AST::Macro)
      ranges << FoldingRange.new(
        start_line: node.span.start_line - 1,
        end_line: node.span.end_line - 1,
        kind: FoldingRangeKind::Region
      )
      visit_children(node)
    end

    def visit(node : AST::Comment)
      ranges << FoldingRange.new(
        start_line: node.span.start_line - 1,
        end_line: node.span.end_line - 1,
        kind: FoldingRangeKind::Comment
      )
    end
  end
end
```

### Semantic Tokens
```crystal
module Crinkle::LSP
  class SemanticTokenProvider
    TOKEN_TYPES = ["keyword", "variable", "string", "number", "operator", "comment", "function"]
    TOKEN_MODIFIERS = ["definition", "readonly", "deprecated"]

    def semantic_tokens(document : Document) : SemanticTokens
      builder = SemanticTokensBuilder.new
      visitor = TokenVisitor.new(builder)
      visitor.visit(document.ast)
      builder.build
    end
  end
end
```

## Acceptance Criteria
- Document outline shows logical template structure.
- Code folding works for all block types.
- Semantic highlighting improves readability.
- All features work in VS Code and other editors.

## Checklist
- [x] Implement `textDocument/documentSymbol` request handler
- [x] Build symbol tree from AST
- [x] Implement `textDocument/foldingRange` request handler
- [x] Calculate folding ranges from AST node spans
- [x] Add AST/token caching to Document class
- [x] Add recursion depth guard to expr_preview
- [ ] Test document outline in editor
- [ ] Test code folding in editor

## Implementation Notes

### Performance Optimizations
- Added AST and token caching to `Document` class
- Cache is invalidated on document update, shared across multiple LSP requests
- Added depth limit (10) to `expr_preview` to prevent deep recursion

### Current Status
- **Folding ranges**: Enabled and working
- **Document symbols**: Implemented but disabled (`document_symbol_provider: false`) - needs investigation
- **Semantic tokens**: Removed - editors typically ignore LSP semantic tokens in favor of TextMate grammars for syntax highlighting
