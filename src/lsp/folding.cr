module Crinkle::LSP
  # Provides folding ranges for textDocument/foldingRange
  class FoldingProvider
    # Get folding ranges from a Document (uses cached AST)
    def folding_ranges(doc : Document) : Array(FoldingRange)
      ranges = Array(FoldingRange).new
      visitor = FoldingVisitor.new(ranges)
      visitor.visit_nodes(doc.ast.body)
      ranges
    rescue
      # Parse error - return empty
      Array(FoldingRange).new
    end

    # Get folding ranges from raw text (parses from scratch - for testing)
    def folding_ranges(text : String) : Array(FoldingRange)
      lexer = Lexer.new(text)
      tokens = lexer.lex_all
      parser = Parser.new(tokens)
      ast = parser.parse
      ranges = Array(FoldingRange).new
      visitor = FoldingVisitor.new(ranges)
      visitor.visit_nodes(ast.body)
      ranges
    rescue
      Array(FoldingRange).new
    end

    private class FoldingVisitor < AST::Visitor
      def initialize(@ranges : Array(FoldingRange)) : Nil
      end

      protected def enter_node(node : AST::Node) : Nil
        case node
        when AST::Block
          add_region_range(node.span)
        when AST::Macro
          add_region_range(node.span)
        when AST::For
          add_region_range(node.span)
        when AST::If
          add_region_range(node.span)
        when AST::SetBlock
          add_region_range(node.span)
        when AST::CallBlock
          add_region_range(node.span)
        when AST::Raw
          add_region_range(node.span)
        when AST::Comment
          if node.span.start_pos.line != node.span.end_pos.line
            add_comment_range(node.span)
          end
        when AST::CustomTag
          unless node.body.empty?
            add_region_range(node.span)
          end
        end
      end

      private def add_region_range(span : Span) : Nil
        # Only add if it spans multiple lines
        return if span.start_pos.line == span.end_pos.line

        @ranges << FoldingRange.new(
          start_line: span.start_pos.line - 1,
          end_line: span.end_pos.line - 1,
          kind: FoldingRangeKind::Region
        )
      end

      private def add_comment_range(span : Span) : Nil
        @ranges << FoldingRange.new(
          start_line: span.start_pos.line - 1,
          end_line: span.end_pos.line - 1,
          kind: FoldingRangeKind::Comment
        )
      end
    end
  end
end
