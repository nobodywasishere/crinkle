require "./protocol"
require "./document"

module Crinkle::LSP
  # Provides document symbols (outline) for textDocument/documentSymbol
  class SymbolProvider
    # Get symbols from a Document (uses cached AST)
    def document_symbols(doc : Document) : Array(DocumentSymbol)
      build_symbols(doc.ast.body)
    rescue
      # Parse error - return empty
      Array(DocumentSymbol).new
    end

    # Get symbols from raw text (parses from scratch - for testing)
    def document_symbols(text : String) : Array(DocumentSymbol)
      lexer = Lexer.new(text)
      tokens = lexer.lex_all
      parser = Parser.new(tokens)
      ast = parser.parse
      build_symbols(ast.body)
    rescue
      Array(DocumentSymbol).new
    end

    # Build symbols from AST nodes
    private def build_symbols(nodes : Array(AST::Node)) : Array(DocumentSymbol)
      symbols = Array(DocumentSymbol).new

      nodes.each do |node|
        case node
        when AST::Block
          symbols << build_block_symbol(node)
        when AST::Macro
          symbols << build_macro_symbol(node)
        when AST::Set
          symbols << build_set_symbol(node)
        when AST::SetBlock
          symbols << build_set_block_symbol(node)
        when AST::For
          symbols << build_for_symbol(node)
        when AST::If
          symbols << build_if_symbol(node)
        when AST::CustomTag
          # Only include custom tags with bodies as they have structure
          unless node.body.empty?
            symbols << build_custom_tag_symbol(node)
          end
        end
      end

      symbols
    end

    # Build symbol for a block
    private def build_block_symbol(node : AST::Block) : DocumentSymbol
      children = build_symbols(node.body)
      DocumentSymbol.new(
        name: node.name,
        kind: SymbolKind::Class,
        range: span_to_range(node.span),
        selection_range: name_selection_range(node.span, "block ".size, node.name.size),
        detail: "block",
        children: children.empty? ? nil : children
      )
    end

    # Build symbol for a macro
    private def build_macro_symbol(node : AST::Macro) : DocumentSymbol
      param_str = node.params.map(&.name).join(", ")
      children = build_symbols(node.body)
      DocumentSymbol.new(
        name: "#{node.name}(#{param_str})",
        kind: SymbolKind::Method,
        range: span_to_range(node.span),
        selection_range: name_selection_range(node.span, "macro ".size, node.name.size),
        detail: "macro",
        children: children.empty? ? nil : children
      )
    end

    # Build symbol for a set statement
    private def build_set_symbol(node : AST::Set) : DocumentSymbol
      name = target_name(node.target)
      DocumentSymbol.new(
        name: name,
        kind: SymbolKind::Variable,
        range: span_to_range(node.span),
        selection_range: name_selection_range(node.span, "set ".size, name.size),
        detail: "variable"
      )
    end

    # Build symbol for a set block
    private def build_set_block_symbol(node : AST::SetBlock) : DocumentSymbol
      name = target_name(node.target)
      children = build_symbols(node.body)
      DocumentSymbol.new(
        name: name,
        kind: SymbolKind::Variable,
        range: span_to_range(node.span),
        selection_range: name_selection_range(node.span, "set ".size, name.size),
        detail: "block variable",
        children: children.empty? ? nil : children
      )
    end

    # Build symbol for a for loop
    private def build_for_symbol(node : AST::For) : DocumentSymbol
      target = target_name(node.target)
      iter = expr_preview(node.iter, 20)
      children = build_symbols(node.body)
      # Include else_body children too
      else_children = build_symbols(node.else_body)
      all_children = children + else_children

      DocumentSymbol.new(
        name: "for #{target} in #{iter}",
        kind: SymbolKind::Struct,
        range: span_to_range(node.span),
        selection_range: name_selection_range(node.span, "for ".size, target.size),
        detail: "loop",
        children: all_children.empty? ? nil : all_children
      )
    end

    # Build symbol for an if statement
    private def build_if_symbol(node : AST::If) : DocumentSymbol
      test = expr_preview(node.test, 30)
      children = build_symbols(node.body)
      # Include else_body children
      else_children = build_symbols(node.else_body)
      all_children = children + else_children

      DocumentSymbol.new(
        name: "if #{test}",
        kind: SymbolKind::Boolean,
        range: span_to_range(node.span),
        selection_range: name_selection_range(node.span, "if ".size, test.size),
        detail: "conditional",
        children: all_children.empty? ? nil : all_children
      )
    end

    # Build symbol for a custom tag
    private def build_custom_tag_symbol(node : AST::CustomTag) : DocumentSymbol
      children = build_symbols(node.body)
      DocumentSymbol.new(
        name: node.name,
        kind: SymbolKind::Event,
        range: span_to_range(node.span),
        selection_range: name_selection_range(node.span, 0, node.name.size),
        detail: "custom tag",
        children: children.empty? ? nil : children
      )
    end

    # Get name from target
    private def target_name(target : AST::Target) : String
      case target
      when AST::Name
        target.value
      when AST::TupleLiteral
        names = target.items.map do |item|
          item.is_a?(AST::Name) ? item.value : "..."
        end
        "(#{names.join(", ")})"
      else
        "..."
      end
    end

    # Get preview of expression (truncated)
    # max_depth prevents infinite recursion on deeply nested expressions
    private def expr_preview(expr : AST::Expr, max_len : Int32, depth : Int32 = 0) : String
      # Guard against deep recursion and negative max_len
      return "..." if depth > 10 || max_len <= 3

      preview = case expr
                when AST::Name
                  expr.value
                when AST::Literal
                  expr.value.inspect
                when AST::GetAttr
                  remaining = max_len - expr.name.size - 1
                  "#{expr_preview(expr.target, remaining, depth + 1)}.#{expr.name}"
                when AST::Call
                  "#{expr_preview(expr.callee, max_len - 5, depth + 1)}(...)"
                when AST::Filter
                  remaining = max_len - expr.name.size - 1
                  "#{expr_preview(expr.expr, remaining, depth + 1)}|#{expr.name}"
                when AST::Binary
                  "#{expr_preview(expr.left, 10, depth + 1)} #{expr.op} #{expr_preview(expr.right, 10, depth + 1)}"
                when AST::ListLiteral
                  "[...]"
                when AST::DictLiteral
                  "{...}"
                else
                  "..."
                end
      preview.size > max_len ? "#{preview[0, max_len - 3]}..." : preview
    end

    # Convert Span to LSP Range (1-based to 0-based)
    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column)
      )
    end

    # Create a selection range for a named element
    # offset: characters after the start of the tag to the name
    # length: length of the name
    private def name_selection_range(span : Span, offset : Int32, length : Int32) : Range
      # Start after {% and whitespace, plus the offset
      start_char = span.start_pos.column + 3 + offset
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: start_char),
        end_pos: Position.new(line: span.start_pos.line - 1, character: start_char + length)
      )
    end
  end
end
