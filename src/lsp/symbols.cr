module Crinkle::LSP
  # Provides document symbols (outline) for textDocument/documentSymbol
  class SymbolProvider
    # Get symbols from a Document (uses cached AST)
    def document_symbols(doc : Document) : Array(DocumentSymbol)
      visitor = SymbolVisitor.new
      visitor.visit_nodes(doc.ast.body)
      visitor.symbols
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
      visitor = SymbolVisitor.new
      visitor.visit_nodes(ast.body)
      visitor.symbols
    rescue
      Array(DocumentSymbol).new
    end

    # Get symbols from a workspace index entry (for unopened files).
    def document_symbols(entry : WorkspaceIndex::Entry) : Array(DocumentSymbol)
      symbols = Array(DocumentSymbol).new

      entry.macros.each do |macro_info|
        if span = macro_info.definition_span
          symbols << DocumentSymbol.new(
            name: "#{macro_info.name}(#{macro_info.params.join(", ")})",
            kind: SymbolKind::Method,
            range: span_to_range(span),
            selection_range: span_to_range(span),
            detail: "macro"
          )
        end
      end

      entry.blocks.each do |block_info|
        if span = block_info.definition_span
          symbols << DocumentSymbol.new(
            name: block_info.name,
            kind: SymbolKind::Class,
            range: span_to_range(span),
            selection_range: span_to_range(span),
            detail: "block"
          )
        end
      end

      entry.variables.each do |var_info|
        next unless var_info.source.set? || var_info.source.set_block?
        if span = var_info.definition_span
          symbols << DocumentSymbol.new(
            name: var_info.name,
            kind: SymbolKind::Variable,
            range: span_to_range(span),
            selection_range: span_to_range(span),
            detail: "variable"
          )
        end
      end

      symbols
    end

    private class SymbolVisitor < AST::Visitor
      getter symbols : Array(DocumentSymbol)

      def initialize : Nil
        @symbols = Array(DocumentSymbol).new
        @stack = Array(Array(DocumentSymbol)).new
        @node_stack = Array(AST::Node).new
      end

      protected def enter_node(node : AST::Node) : Nil
        case node
        when AST::Block
          add_container(symbol_for_block(node), node)
        when AST::Macro
          add_container(symbol_for_macro(node), node)
        when AST::Set
          add_leaf(symbol_for_set(node))
        when AST::SetBlock
          add_container(symbol_for_set_block(node), node)
        when AST::For
          add_container(symbol_for_for(node), node)
        when AST::If
          if node.is_elif?
            add_container(symbol_for_elif(node), node)
          else
            add_container(symbol_for_if(node), node)
          end
        when AST::CustomTag
          unless node.body.empty?
            add_container(symbol_for_custom_tag(node), node)
          end
        end
      end

      protected def exit_node(node : AST::Node) : Nil
        return if @node_stack.empty?
        return unless @node_stack.last == node
        @node_stack.pop
        @stack.pop

        if node.is_a?(AST::If)
          visit_nodes(node.else_body)
        end
      end

      private def add_container(symbol : DocumentSymbol, node : AST::Node) : Nil
        add_symbol(symbol)
        if children = symbol.children
          @stack << children
          @node_stack << node
        end
      end

      private def add_leaf(symbol : DocumentSymbol) : Nil
        add_symbol(symbol)
      end

      private def add_symbol(symbol : DocumentSymbol) : Nil
        if @stack.empty?
          @symbols << symbol
        else
          @stack.last << symbol
        end
      end

      protected def visit_node_children(node : AST::Node) : Nil
        case node
        when AST::If
          visit_nodes(node.body)
        else
          super
        end
      end

      private def symbol_for_block(node : AST::Block) : DocumentSymbol
        children = Array(DocumentSymbol).new
        DocumentSymbol.new(
          name: node.name,
          kind: SymbolKind::Class,
          range: span_to_range(node.span),
          selection_range: name_selection_range(node.span, "block ".size, node.name.size),
          detail: "block",
          children: children
        )
      end

      private def symbol_for_macro(node : AST::Macro) : DocumentSymbol
        param_str = node.params.map(&.name).join(", ")
        children = Array(DocumentSymbol).new
        DocumentSymbol.new(
          name: "#{node.name}(#{param_str})",
          kind: SymbolKind::Method,
          range: span_to_range(node.span),
          selection_range: name_selection_range(node.span, "macro ".size, node.name.size),
          detail: "macro",
          children: children
        )
      end

      private def symbol_for_set(node : AST::Set) : DocumentSymbol
        name = target_name(node.target)
        DocumentSymbol.new(
          name: name,
          kind: SymbolKind::Variable,
          range: span_to_range(node.span),
          selection_range: name_selection_range(node.span, "set ".size, name.size),
          detail: "variable"
        )
      end

      private def symbol_for_set_block(node : AST::SetBlock) : DocumentSymbol
        name = target_name(node.target)
        children = Array(DocumentSymbol).new
        DocumentSymbol.new(
          name: name,
          kind: SymbolKind::Variable,
          range: span_to_range(node.span),
          selection_range: name_selection_range(node.span, "set ".size, name.size),
          detail: "block variable",
          children: children
        )
      end

      private def symbol_for_for(node : AST::For) : DocumentSymbol
        target = target_name(node.target)
        iter = expr_preview(node.iter, 20)
        children = Array(DocumentSymbol).new
        DocumentSymbol.new(
          name: "for #{target} in #{iter}",
          kind: SymbolKind::Struct,
          range: span_to_range(node.span),
          selection_range: name_selection_range(node.span, "for ".size, target.size),
          detail: "loop",
          children: children
        )
      end

      private def symbol_for_if(node : AST::If) : DocumentSymbol
        test = expr_preview(node.test, 30)
        children = Array(DocumentSymbol).new
        DocumentSymbol.new(
          name: "if #{test}",
          kind: SymbolKind::Boolean,
          range: span_to_range(node.span),
          selection_range: name_selection_range(node.span, "if ".size, test.size),
          detail: "conditional",
          children: children
        )
      end

      private def symbol_for_elif(node : AST::If) : DocumentSymbol
        test = expr_preview(node.test, 30)
        children = Array(DocumentSymbol).new
        DocumentSymbol.new(
          name: "elif #{test}",
          kind: SymbolKind::Boolean,
          range: span_to_range(node.span),
          selection_range: name_selection_range(node.span, "elif ".size, test.size),
          detail: "conditional",
          children: children
        )
      end

      private def symbol_for_custom_tag(node : AST::CustomTag) : DocumentSymbol
        children = Array(DocumentSymbol).new
        DocumentSymbol.new(
          name: node.name,
          kind: SymbolKind::Event,
          range: span_to_range(node.span),
          selection_range: name_selection_range(node.span, 0, node.name.size),
          detail: "custom tag",
          children: children
        )
      end

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

      private def expr_preview(expr : AST::Expr, max_len : Int32, depth : Int32 = 0) : String
        return "..." if depth > 5

        result = case expr
                 when AST::Name
                   expr.value
                 when AST::Literal
                   value = expr.value
                   case value
                   when String
                     %("#{value}")
                   when nil
                     "none"
                   else
                     value.to_s
                   end
                 when AST::Binary
                   left = expr_preview(expr.left, max_len, depth + 1)
                   right = expr_preview(expr.right, max_len, depth + 1)
                   "#{left} #{expr.op} #{right}"
                 when AST::Unary
                   "#{expr.op}#{expr_preview(expr.expr, max_len, depth + 1)}"
                 when AST::Group
                   "(#{expr_preview(expr.expr, max_len, depth + 1)})"
                 when AST::Call
                   name = expr_preview(expr.callee, max_len, depth + 1)
                   "#{name}(...)"
                 when AST::Filter
                   left = expr_preview(expr.expr, max_len, depth + 1)
                   "#{left} | #{expr.name}"
                 when AST::Test
                   left = expr_preview(expr.expr, max_len, depth + 1)
                   "#{left} is #{expr.name}"
                 when AST::GetAttr
                   target = expr_preview(expr.target, max_len, depth + 1)
                   "#{target}.#{expr.name}"
                 when AST::GetItem
                   target = expr_preview(expr.target, max_len, depth + 1)
                   "#{target}[...]"
                 when AST::ListLiteral
                   "[...]"
                 when AST::DictLiteral
                   "{...}"
                 when AST::TupleLiteral
                   "(...)"
                 else
                   "..."
                 end

        result.size > max_len ? result[0, max_len] + "..." : result
      end

      private def name_selection_range(span : Span, offset : Int32, name_size : Int32) : Range
        start = Position.new(
          line: span.start_pos.line - 1,
          character: span.start_pos.column + offset
        )
        Range.new(
          start: start,
          end_pos: Position.new(line: start.line, character: start.character + name_size)
        )
      end

      private def span_to_range(span : Span) : Range
        Range.new(
          start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column - 1),
          end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column - 1)
        )
      end
    end

    # Convert Span to LSP Range (1-based to 0-based)
    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column - 1),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column - 1)
      )
    end
  end
end
