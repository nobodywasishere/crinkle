require "./protocol"
require "./document"

module Crinkle::LSP
  # Provides folding ranges for textDocument/foldingRange
  class FoldingProvider
    # Get folding ranges from a Document (uses cached AST)
    def folding_ranges(doc : Document) : Array(FoldingRange)
      ranges = Array(FoldingRange).new
      collect_folding_ranges(doc.ast.body, ranges)
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
      collect_folding_ranges(ast.body, ranges)
      ranges
    rescue
      Array(FoldingRange).new
    end

    # Collect folding ranges from AST nodes
    private def collect_folding_ranges(nodes : Array(AST::Node), ranges : Array(FoldingRange)) : Nil
      nodes.each do |node|
        case node
        when AST::Block
          add_region_range(node.span, ranges)
          collect_folding_ranges(node.body, ranges)
        when AST::Macro
          add_region_range(node.span, ranges)
          collect_folding_ranges(node.body, ranges)
        when AST::For
          add_region_range(node.span, ranges)
          collect_folding_ranges(node.body, ranges)
          collect_folding_ranges(node.else_body, ranges)
        when AST::If
          add_region_range(node.span, ranges)
          collect_folding_ranges(node.body, ranges)
          collect_folding_ranges(node.else_body, ranges)
        when AST::SetBlock
          add_region_range(node.span, ranges)
          collect_folding_ranges(node.body, ranges)
        when AST::CallBlock
          add_region_range(node.span, ranges)
          collect_folding_ranges(node.body, ranges)
        when AST::Raw
          add_region_range(node.span, ranges)
        when AST::Comment
          # Multi-line comments are foldable
          if node.span.start_pos.line != node.span.end_pos.line
            add_comment_range(node.span, ranges)
          end
        when AST::CustomTag
          unless node.body.empty?
            add_region_range(node.span, ranges)
            collect_folding_ranges(node.body, ranges)
          end
        end
      end
    end

    # Add a region folding range (for block tags)
    private def add_region_range(span : Span, ranges : Array(FoldingRange)) : Nil
      # Only add if it spans multiple lines
      return if span.start_pos.line == span.end_pos.line

      ranges << FoldingRange.new(
        start_line: span.start_pos.line - 1,
        end_line: span.end_pos.line - 1,
        kind: FoldingRangeKind::Region
      )
    end

    # Add a comment folding range
    private def add_comment_range(span : Span, ranges : Array(FoldingRange)) : Nil
      ranges << FoldingRange.new(
        start_line: span.start_pos.line - 1,
        end_line: span.end_pos.line - 1,
        kind: FoldingRangeKind::Comment
      )
    end
  end
end
