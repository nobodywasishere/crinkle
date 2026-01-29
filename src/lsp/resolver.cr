require "./types"
require "./text_scanner"

module Jinja
  module LSP
    class Resolver
      def initialize(@document : Document) : Nil
        @scanner = TextScanner.new
      end

      def reference_at(position : LSProtocol::Position) : SymbolReference?
        symbols = @document.symbols
        if symbols
          reference = symbols.references.find do |entry|
            position_in_span?(position, entry.span)
          end
          return reference if reference
        end
        @scanner.reference_from_text(@document.text, position)
      end

      def definition_for(name : String) : SymbolDefinition?
        symbols = @document.symbols
        return if symbols.nil?
        definitions = symbols.definitions[name]?
        return if definitions.nil? || definitions.empty?
        definitions.last
      end

      def document_symbols : Array(SymbolDefinition)
        symbols = @document.symbols
        if symbols && !symbols.definitions.empty?
          return symbols.definitions.values.flatten
        end
        symbols_from_text(@document.text)
      end

      def folding_spans : Array(Jinja::Span)
        symbols = @document.symbols
        if symbols && !symbols.foldable_spans.empty?
          return symbols.foldable_spans
        end
        foldable_spans_from_text(@document.text)
      end

      private def position_in_span?(position : LSProtocol::Position, span : Jinja::Span) : Bool
        line = position.line.to_i + 1
        column = position.character.to_i + 1
        start_pos = span.start_pos
        end_pos = span.end_pos
        before_or_equal?(start_pos.line, start_pos.column, line, column) &&
          before_or_equal?(line, column, end_pos.line, end_pos.column)
      end

      private def before_or_equal?(line_a : Int32, col_a : Int32, line_b : Int32, col_b : Int32) : Bool
        line_a < line_b || (line_a == line_b && col_a <= col_b)
      end

      private def symbols_from_text(text : String) : Array(SymbolDefinition)
        tags = @scanner.block_tags(text)
        symbols = Array(SymbolDefinition).new
        tags.each do |tag|
          kind = case tag.name
                 when "block"
                   LSProtocol::SymbolKind::Class
                 when "macro"
                   LSProtocol::SymbolKind::Function
                 when "set"
                   LSProtocol::SymbolKind::Variable
                 else
                   next
                 end
          next if tag.argument.empty?
          span = Jinja::Span.new(
            Jinja::Position.new(0, tag.arg_line, tag.arg_column),
            Jinja::Position.new(0, tag.arg_line, tag.arg_column + tag.argument.size),
          )
          symbols << SymbolDefinition.new(tag.argument, kind, span)
        end
        symbols
      end

      private def foldable_spans_from_text(text : String) : Array(Jinja::Span)
        tags = @scanner.block_tags(text)
        spans = Array(Jinja::Span).new
        stack = Array(Tuple(String, Int32)).new
        tags.each do |tag|
          if tag.is_end?
            if start = stack.reverse.find { |entry| entry[0] == tag.name }
              stack.delete(start)
              start_line = start[1]
              end_line = tag.line
              if end_line > start_line
                spans << Jinja::Span.new(
                  Jinja::Position.new(0, start_line, 1),
                  Jinja::Position.new(0, end_line, 1),
                )
              end
            end
          else
            case tag.name
            when "if", "for", "block", "macro", "set", "call", "raw"
              stack << {tag.name, tag.line}
            end
          end
        end
        spans
      end
    end
  end
end
