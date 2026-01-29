module Jinja
  class Lexer
    enum Mode
      Text
      Expr
      Block
    end

    getter diagnostics : Array(Diagnostic)

    def initialize(source : String) : Nil
      @source = source
      @reader = Char::Reader.new(source)
      @length = source.bytesize
      @line = 1
      @column = 1
      @mode = Mode::Text
      @mode_start_offset = 0
      @mode_start_line = 1
      @mode_start_col = 1
      @diagnostics = Array(Diagnostic).new
    end

    def lex_all : Array(Token)
      tokens = Array(Token).new
      loop do
        token = next_token
        tokens << token
        break if token.type == TokenType::EOF
      end
      tokens
    end

    private def next_token : Token
      case @mode
      when Mode::Text
        lex_text
      when Mode::Expr
        lex_expr_or_block(TokenType::VarEnd, Mode::Text)
      when Mode::Block
        lex_expr_or_block(TokenType::BlockEnd, Mode::Text)
      else
        eof_token
      end
    end

    private def lex_text : Token
      return eof_token if at_eof?

      if starts_var?
        return lex_var_start
      elsif starts_block?
        return lex_block_start
      end

      start_offset = current_offset
      start_line = @line
      start_col = @column

      while !at_eof?
        break if starts_var? || starts_block?
        advance_char
      end

      token_from(TokenType::Text, start_offset, start_line, start_col)
    end

    private def lex_expr_or_block(end_type : TokenType, next_mode : Mode) : Token
      loop do
        return unterminated(end_type) if at_eof?

        if end_type == TokenType::VarEnd && starts_var_end?
          return lex_var_end(next_mode)
        elsif end_type == TokenType::BlockEnd && starts_block_end?
          return lex_block_end(next_mode)
        end

        if starts_var? || starts_block?
          return recover_to_text(end_type)
        end

        ch = current_char

        if whitespace_char?(ch)
          return lex_whitespace
        end

        if identifier_start?(ch)
          return lex_identifier
        end

        if digit?(ch)
          return lex_number
        end

        if quote?(ch)
          return lex_string
        end

        if operator_or_punct?(ch)
          return lex_operator_or_punct
        end

        emit_unexpected_char
        advance_char
      end
    end

    private def starts_var? : Bool
      b0 = byte_at(current_offset)
      b1 = byte_at(current_offset + 1)
      b0 == '{'.ord.to_u8 && b1 == '{'.ord.to_u8
    end

    private def starts_block? : Bool
      b0 = byte_at(current_offset)
      b1 = byte_at(current_offset + 1)
      b0 == '{'.ord.to_u8 && b1 == '%'.ord.to_u8
    end

    private def starts_var_end? : Bool
      pos = current_offset
      b0 = byte_at(pos)
      if b0 == '-'.ord.to_u8
        b1 = byte_at(pos + 1)
        b2 = byte_at(pos + 2)
        return b1 == '}'.ord.to_u8 && b2 == '}'.ord.to_u8
      end
      b1 = byte_at(pos + 1)
      b0 == '}'.ord.to_u8 && b1 == '}'.ord.to_u8
    end

    private def starts_block_end? : Bool
      pos = current_offset
      b0 = byte_at(pos)
      if b0 == '-'.ord.to_u8
        b1 = byte_at(pos + 1)
        b2 = byte_at(pos + 2)
        return b1 == '%'.ord.to_u8 && b2 == '}'.ord.to_u8
      end
      b1 = byte_at(pos + 1)
      b0 == '%'.ord.to_u8 && b1 == '}'.ord.to_u8
    end

    private def lex_var_start : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      # {{ or {{-
      advance_char
      advance_char
      if current_char == '-'
        advance_char
      end

      @mode = Mode::Expr
      mark_mode_start(start_offset, start_line, start_col)
      token_from(TokenType::VarStart, start_offset, start_line, start_col)
    end

    private def lex_block_start : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      # {% or {% -
      advance_char
      advance_char
      if current_char == '-'
        advance_char
      end

      @mode = Mode::Block
      mark_mode_start(start_offset, start_line, start_col)
      token_from(TokenType::BlockStart, start_offset, start_line, start_col)
    end

    private def lex_var_end(next_mode : Mode) : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      if current_char == '-'
        advance_char
      end
      advance_char
      advance_char

      @mode = next_mode
      token_from(TokenType::VarEnd, start_offset, start_line, start_col)
    end

    private def lex_block_end(next_mode : Mode) : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      if current_char == '-'
        advance_char
      end
      advance_char
      advance_char

      @mode = next_mode
      token_from(TokenType::BlockEnd, start_offset, start_line, start_col)
    end

    private def lex_whitespace : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      while !at_eof? && whitespace_char?(current_char)
        advance_char
      end

      token_from(TokenType::Whitespace, start_offset, start_line, start_col)
    end

    private def lex_identifier : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      advance_char
      while !at_eof? && identifier_part?(current_char)
        advance_char
      end

      token_from(TokenType::Identifier, start_offset, start_line, start_col)
    end

    private def lex_number : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      while !at_eof? && digit?(current_char)
        advance_char
      end

      if current_char == '.'
        advance_char
        while !at_eof? && digit?(current_char)
          advance_char
        end
      end

      token_from(TokenType::Number, start_offset, start_line, start_col)
    end

    private def lex_string : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      quote = current_char
      advance_char

      while !at_eof?
        if starts_end_for_mode?
          emit_diagnostic(DiagnosticType::UnterminatedString, "Unterminated string literal.", start_offset, start_line, start_col)
          return token_from(TokenType::String, start_offset, start_line, start_col)
        end

        if current_char == '\\'
          advance_char
          advance_char unless at_eof?
          next
        end
        break if current_char == quote
        advance_char
      end

      if at_eof?
        emit_diagnostic(DiagnosticType::UnterminatedString, "Unterminated string literal.", start_offset, start_line, start_col)
        return token_from(TokenType::String, start_offset, start_line, start_col)
      end

      advance_char

      token_from(TokenType::String, start_offset, start_line, start_col)
    end

    private def operator_or_punct?(ch : Char) : Bool
      case ch
      when '+', '-', '*', '/', '%', '|', '&', '.', '~', '<', '>', '=', '!', '(', ')', '[', ']', '{', '}', ',', ':'
        true
      else
        false
      end
    end

    private def lex_operator_or_punct : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column

      if two_char_operator?
        advance_char
        advance_char
      else
        advance_char
      end

      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)

      if punct?(lexeme)
        Token.new(TokenType::Punct, lexeme, span)
      else
        Token.new(TokenType::Operator, lexeme, span)
      end
    end

    private def two_char_operator? : Bool
      pos = current_offset
      a = byte_at(pos)
      b = byte_at(pos + 1)
      return false unless a && b
      return true if a == '='.ord.to_u8 && b == '='.ord.to_u8
      return true if a == '!'.ord.to_u8 && b == '='.ord.to_u8
      return true if a == '>'.ord.to_u8 && b == '='.ord.to_u8
      return true if a == '<'.ord.to_u8 && b == '='.ord.to_u8
      return true if a == '/'.ord.to_u8 && b == '/'.ord.to_u8
      return true if a == '*'.ord.to_u8 && b == '*'.ord.to_u8
      return true if a == '|'.ord.to_u8 && b == '|'.ord.to_u8
      return true if a == '&'.ord.to_u8 && b == '&'.ord.to_u8
      false
    end

    private def punct?(lexeme : String) : Bool
      case lexeme
      when "(", ")", "[", "]", "{", "}", ",", ":"
        true
      else
        false
      end
    end

    private def unterminated(end_type : TokenType) : Token
      if end_type == TokenType::VarEnd
        emit_diagnostic(DiagnosticType::UnterminatedExpression, "Unterminated expression; expected '}}'.", @mode_start_offset, @mode_start_line, @mode_start_col)
      else
        emit_diagnostic(DiagnosticType::UnterminatedBlock, "Unterminated block; expected '%}'.", @mode_start_offset, @mode_start_line, @mode_start_col)
      end
      eof_token
    end

    private def recover_to_text(end_type : TokenType) : Token
      if end_type == TokenType::VarEnd
        emit_diagnostic(DiagnosticType::UnterminatedExpression, "Unterminated expression; expected '}}'.", @mode_start_offset, @mode_start_line, @mode_start_col)
      else
        emit_diagnostic(DiagnosticType::UnterminatedBlock, "Unterminated block; expected '%}'.", @mode_start_offset, @mode_start_line, @mode_start_col)
      end

      @mode = Mode::Text
      span = Span.new(
        Position.new(current_offset, @line, @column),
        Position.new(current_offset, @line, @column)
      )
      Token.new(end_type, "", span)
    end

    private def emit_unexpected_char : Nil
      start_offset = current_offset
      start_line = @line
      start_col = @column
      ch = current_char
      span = span_for_char(start_offset, start_line, start_col, ch)
      message = "Unexpected character '#{ch}' in expression."
      @diagnostics << Diagnostic.new(DiagnosticType::UnexpectedChar, Severity::Error, message, span)
    end

    private def emit_diagnostic(type : DiagnosticType, message : String) : Nil
      span = make_span(current_offset, @line, @column)
      @diagnostics << Diagnostic.new(type, Severity::Error, message, span)
    end

    private def emit_diagnostic(type : DiagnosticType, message : String, start_offset : Int32, start_line : Int32, start_col : Int32) : Nil
      span = make_span(start_offset, start_line, start_col)
      @diagnostics << Diagnostic.new(type, Severity::Error, message, span)
    end

    private def make_span(start_offset : Int32, start_line : Int32, start_col : Int32) : Span
      Span.new(Position.new(start_offset, start_line, start_col), Position.new(current_offset, @line, @column))
    end

    private def span_for_char(start_offset : Int32, start_line : Int32, start_col : Int32, ch : Char) : Span
      end_offset = start_offset + ch.bytesize
      if ch == '\n'
        end_line = start_line + 1
        end_col = 1
      else
        end_line = start_line
        end_col = start_col + 1
      end
      Span.new(Position.new(start_offset, start_line, start_col), Position.new(end_offset, end_line, end_col))
    end

    private def token_from(type : TokenType, start_offset : Int32, start_line : Int32, start_col : Int32) : Token
      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(type, lexeme, span)
    end

    private def mark_mode_start(start_offset : Int32, start_line : Int32, start_col : Int32) : Nil
      @mode_start_offset = start_offset
      @mode_start_line = start_line
      @mode_start_col = start_col
    end

    private def starts_end_for_mode? : Bool
      case @mode
      when Mode::Expr
        starts_var_end?
      when Mode::Block
        starts_block_end?
      else
        false
      end
    end

    private def current_char : Char
      @reader.current_char
    end

    private def current_offset : Int32
      @reader.pos
    end

    private def at_eof? : Bool
      current_char == '\0'
    end

    private def advance_char : Nil
      ch = current_char
      @reader.next_char
      if ch == '\n'
        @line += 1
        @column = 1
      else
        @column += 1
      end
    end

    private def byte_at(index : Int32) : UInt8?
      return if index < 0 || index >= @length
      @source.byte_at(index)
    end

    private def whitespace_char?(ch : Char) : Bool
      ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
    end

    private def identifier_start?(ch : Char) : Bool
      (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_'
    end

    private def identifier_part?(ch : Char) : Bool
      identifier_start?(ch) || digit?(ch)
    end

    private def digit?(ch : Char) : Bool
      ch >= '0' && ch <= '9'
    end

    private def quote?(ch : Char) : Bool
      ch == '\'' || ch == '"'
    end

    private def eof_token : Token
      start_offset = current_offset
      start_line = @line
      start_col = @column
      span = Span.new(Position.new(start_offset, start_line, start_col), Position.new(start_offset, start_line, start_col))
      Token.new(TokenType::EOF, "", span)
    end
  end
end
