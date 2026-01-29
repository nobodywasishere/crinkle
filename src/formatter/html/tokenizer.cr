module Jinja
  module HTML
    enum TokenKind
      StartTag
      EndTag
      SelfClosingTag
      Text
      Comment
      Doctype
      JinjaHole
    end

    struct Token
      getter kind : TokenKind
      getter name : String
      getter lexeme : String
      getter span : Span

      def initialize(@kind : TokenKind, @name : String, @lexeme : String, @span : Span) : Nil
      end
    end

    class Tokenizer
      def tokens(text : String) : Array(Token)
        tokens = Array(Token).new
        size = text.bytesize
        i = 0
        line = 1
        col = 1
        buffer_start = 0
        buffer_line = line
        buffer_col = col

        while i < size
          if text.byte_at(i) == '{'.ord
            if hole = parse_jinja_hole(text, i)
              hole_start, hole_end = hole
              if hole_start > buffer_start
                tokens << Token.new(
                  TokenKind::Text,
                  "",
                  text.byte_slice(buffer_start, hole_start - buffer_start),
                  span_from(buffer_start, buffer_line, buffer_col, hole_start, line, col),
                )
              end
              end_line, end_col = advance_position(text, i, hole_end, line, col)
              lexeme = text.byte_slice(hole_start, hole_end - hole_start)
              tokens << Token.new(
                TokenKind::JinjaHole,
                "",
                lexeme,
                span_from(hole_start, line, col, hole_end, end_line, end_col),
              )
              i = hole_end
              line = end_line
              col = end_col
              buffer_start = i
              buffer_line = line
              buffer_col = col
              next
            end
          end

          if text.byte_at(i) == '<'.ord
            if i > buffer_start
              tokens << Token.new(
                TokenKind::Text,
                "",
                text.byte_slice(buffer_start, i - buffer_start),
                span_from(buffer_start, buffer_line, buffer_col, i, line, col),
              )
            end

            buffer_start = i
            buffer_line = line
            buffer_col = col

            if starts_with?(text, i, "<!--")
              if end_idx = text.index("-->", i + 4)
                lexeme = text.byte_slice(i, end_idx + 3 - i)
                end_line, end_col = advance_position(text, i, end_idx + 3, line, col)
                tokens << Token.new(TokenKind::Comment, "", lexeme, span_from(i, line, col, end_idx + 3, end_line, end_col))
                i = end_idx + 3
                line = end_line
                col = end_col
                buffer_start = i
                buffer_line = line
                buffer_col = col
                next
              else
                break
              end
            elsif starts_with?(text, i, "</")
              if name_info = parse_tag_name(text, i + 2)
                name, name_end = name_info
                if end_idx = scan_to_gt(text, name_end)
                  lexeme = text.byte_slice(i, end_idx - i + 1)
                  end_line, end_col = advance_position(text, i, end_idx + 1, line, col)
                  tokens << Token.new(TokenKind::EndTag, name, lexeme, span_from(i, line, col, end_idx + 1, end_line, end_col))
                  i = end_idx + 1
                  line = end_line
                  col = end_col
                  buffer_start = i
                  buffer_line = line
                  buffer_col = col
                  next
                else
                  break
                end
              end
            elsif starts_with?(text, i, "<!")
              if end_idx = scan_to_gt(text, i + 2)
                lexeme = text.byte_slice(i, end_idx - i + 1)
                end_line, end_col = advance_position(text, i, end_idx + 1, line, col)
                tokens << Token.new(TokenKind::Doctype, "", lexeme, span_from(i, line, col, end_idx + 1, end_line, end_col))
                i = end_idx + 1
                line = end_line
                col = end_col
                buffer_start = i
                buffer_line = line
                buffer_col = col
                next
              else
                break
              end
            elsif starts_with?(text, i, "<?")
              # Processing instructions are treated as text for now.
            else
              if name_info = parse_tag_name(text, i + 1)
                name, name_end = name_info
                if end_idx = scan_to_gt(text, name_end)
                  lexeme = text.byte_slice(i, end_idx - i + 1)
                  kind = self_closing?(lexeme) ? TokenKind::SelfClosingTag : TokenKind::StartTag
                  end_line, end_col = advance_position(text, i, end_idx + 1, line, col)
                  tokens << Token.new(kind, name, lexeme, span_from(i, line, col, end_idx + 1, end_line, end_col))
                  i = end_idx + 1
                  line = end_line
                  col = end_col
                  buffer_start = i
                  buffer_line = line
                  buffer_col = col
                  next
                else
                  break
                end
              end
            end
          end

          line, col = advance_position(text, i, i + 1, line, col)
          i += 1
        end

        if buffer_start < size
          tokens << Token.new(
            TokenKind::Text,
            "",
            text.byte_slice(buffer_start, size - buffer_start),
            span_from(buffer_start, buffer_line, buffer_col, size, line, col),
          )
        end

        tokens
      end

      private def parse_jinja_hole(text : String, start : Int32) : {Int32, Int32}?
        return if start + 1 >= text.bytesize
        kind = text.byte_at(start + 1)
        close = case kind
                when '{'.ord then "}}"
                when '%'.ord then "%}"
                when '#'.ord then "#}"
                else
                  return
                end
        end_idx = text.index(close, start + 2)
        return unless end_idx
        {start, end_idx + close.bytesize}
      end

      private def starts_with?(text : String, index : Int32, value : String) : Bool
        value_size = value.bytesize
        return false if index + value_size > text.bytesize
        text.byte_slice(index, value_size) == value
      end

      private def scan_to_gt(text : String, start : Int32) : Int32?
        quote = 0
        i = start
        while i < text.bytesize
          ch = text.byte_at(i)
          if quote == 0
            if ch == '"'.ord || ch == '\''.ord
              quote = ch
            elsif ch == '>'.ord
              return i
            end
          else
            quote = 0 if ch == quote
          end
          i += 1
        end
        nil
      end

      private def parse_tag_name(text : String, start : Int32) : {String, Int32}?
        return if start >= text.bytesize
        first = text.byte_at(start)
        return unless alpha?(first)
        i = start + 1
        while i < text.bytesize && tag_name_char?(text.byte_at(i))
          i += 1
        end
        name = text.byte_slice(start, i - start).downcase
        {name, i}
      end

      private def alpha?(ch : UInt8) : Bool
        (ch >= 'a'.ord && ch <= 'z'.ord) || (ch >= 'A'.ord && ch <= 'Z'.ord)
      end

      private def tag_name_char?(ch : UInt8) : Bool
        alpha?(ch) || (ch >= '0'.ord && ch <= '9'.ord) || ch == '-'.ord || ch == ':'.ord || ch == '_'.ord
      end

      private def self_closing?(lexeme : String) : Bool
        i = lexeme.bytesize - 1
        while i >= 0
          ch = lexeme.byte_at(i)
          if ch == ' '.ord || ch == '\t'.ord || ch == '\n'.ord || ch == '\r'.ord
            i -= 1
            next
          end
          return false if ch != '>'.ord
          return i > 0 && lexeme.byte_at(i - 1) == '/'.ord
        end
        false
      end

      private def advance_position(text : String, start_index : Int32, end_index : Int32, line : Int32, col : Int32) : {Int32, Int32}
        idx = start_index
        current_line = line
        current_col = col
        while idx < end_index && idx < text.bytesize
          byte = text.byte_at(idx)
          if byte == '\n'.ord
            current_line += 1
            current_col = 1
          else
            current_col += 1
          end
          idx += 1
        end
        {current_line, current_col}
      end

      private def span_from(
        start_offset : Int32,
        start_line : Int32,
        start_col : Int32,
        end_offset : Int32,
        end_line : Int32,
        end_col : Int32,
      ) : Span
        Span.new(
          Position.new(start_offset, start_line, start_col),
          Position.new(end_offset, end_line, end_col),
        )
      end
    end
  end
end
