# Phase 24 — LSP Document Features (Detailed Plan)

## Objectives
- Provide document outline for navigation.
- Enable code folding for template structures.
- Implement semantic token highlighting.

## Priority
**LOW**

## Scope (Phase 24)
- Implement `textDocument/documentSymbol`.
- Implement `textDocument/foldingRange`.
- Implement `textDocument/semanticTokens`.

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

### Semantic Tokens (`textDocument/semanticTokens`)
Syntax highlighting with token types:
- `keyword` — `if`, `for`, `block`, etc.
- `variable` — Variable names
- `string` — String literals
- `number` — Numeric literals
- `operator` — `+`, `-`, `|`, etc.
- `comment` — Comment content
- `function` — Filter/function names

Token modifiers:
- `definition` — Variable/macro definitions
- `readonly` — Loop variables
- `deprecated` — Deprecated constructs

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
- [ ] Implement `textDocument/documentSymbol` request handler
- [ ] Build symbol tree from AST
- [ ] Implement `textDocument/foldingRange` request handler
- [ ] Calculate folding ranges from AST node spans
- [ ] Implement `textDocument/semanticTokens/full` request handler
- [ ] Define semantic token legend (types and modifiers)
- [ ] Map AST nodes to semantic tokens
- [ ] Test document outline in editor
- [ ] Test code folding in editor
- [ ] Test semantic highlighting in editor
