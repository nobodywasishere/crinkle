require "./types"

module Jinja
  module LSP
    class TextScanner
      def reference_from_text(text : String, position : LSProtocol::Position) : SymbolReference?
        line_index = position.line.to_i
        column_index = position.character.to_i
        lines = text.split('\n')
        return if line_index < 0 || line_index >= lines.size
        line = lines[line_index]
        return if column_index < 0 || column_index >= line.size

        start_index = column_index
        while start_index > 0 && word_char?(line[start_index - 1])
          start_index -= 1
        end
        end_index = column_index
        while end_index < line.size && word_char?(line[end_index])
          end_index += 1
        end
        return if start_index == end_index

        name = line[start_index...end_index]
        span = Jinja::Span.new(
          Jinja::Position.new(0, line_index + 1, start_index + 1),
          Jinja::Position.new(0, line_index + 1, end_index + 1),
        )
        SymbolReference.new(name, span)
      end

      def block_tags(text : String) : Array(BlockTag)
        tags = Array(BlockTag).new
        index = 0
        line = 1
        column = 1
        while index < text.size
          ch = text[index]
          if ch == '{' && index + 1 < text.size && text[index + 1] == '%'
            index += 2
            column += 2
            index, line, column = skip_whitespace(text, index, line, column)
            name, index, line, column = read_word(text, index, line, column)
            is_end = name.starts_with?("end")
            tag_name = is_end ? name[3..] : name
            tag_name = tag_name.to_s
            index, line, column = skip_whitespace(text, index, line, column)
            arg = ""
            arg_line = line
            arg_column = column
            if !tag_name.empty?
              arg, index, line, column = read_word(text, index, line, column)
            end
            tags << BlockTag.new(tag_name, is_end, line, column, arg, arg_line, arg_column)
          else
            if ch == '\n'
              line += 1
              column = 1
            else
              column += 1
            end
            index += 1
          end
        end
        tags
      end

      private def word_char?(char : Char) : Bool
        char.alphanumeric? || char == '_'
      end

      private def read_word(text : String, index : Int32, line : Int32, column : Int32) : {String, Int32, Int32, Int32}
        start = index
        while index < text.size
          char = text[index]
          break unless word_char?(char)
          index += 1
          column += 1
        end
        {text[start...index], index, line, column}
      end

      private def skip_whitespace(text : String, index : Int32, line : Int32, column : Int32) : {Int32, Int32, Int32}
        while index < text.size
          char = text[index]
          if char == '\n'
            line += 1
            column = 1
          elsif char.ascii_whitespace?
            column += 1
          else
            break
          end
          index += 1
        end
        {index, line, column}
      end
    end

    struct BlockTag
      getter name : String
      getter? is_end : Bool
      getter line : Int32
      getter column : Int32
      getter argument : String
      getter arg_line : Int32
      getter arg_column : Int32

      def initialize(
        @name : String,
        @is_end : Bool,
        @line : Int32,
        @column : Int32,
        @argument : String,
        @arg_line : Int32,
        @arg_column : Int32,
      ) : Nil
      end
    end
  end
end
