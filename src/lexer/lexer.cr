module Jinja
  class Lexer
    enum Mode
      Text
      Expr
      Block
    end

    getter diagnostics : Array(Diagnostic)

    def initialize(source : String)
      @source = source
      @bytes = source.to_slice
      @length = @bytes.size
      @i = 0
      @line = 1
      @column = 1
      @mode = Mode::Text
      @mode_start_offset = 0
      @mode_start_line = 1
      @mode_start_col = 1
      @diagnostics = [] of Diagnostic
    end

    def lex_all : Array(Token)
      tokens = [] of Token
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
      return eof_token if @i >= @length

      if starts_var?
        return lex_var_start
      elsif starts_block?
        return lex_block_start
      end

      start_offset = @i
      start_line = @line
      start_col = @column

      while @i < @length
        break if starts_var? || starts_block?
        advance_byte
      end

      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::Text, lexeme, span)
    end

    private def lex_expr_or_block(end_type : TokenType, next_mode : Mode) : Token
      loop do
        return unterminated(end_type) if @i >= @length

        if end_type == TokenType::VarEnd && starts_var_end?
          return lex_var_end(next_mode)
        elsif end_type == TokenType::BlockEnd && starts_block_end?
          return lex_block_end(next_mode)
        end

        if whitespace_byte?(@bytes[@i])
          return lex_whitespace
        end

        if identifier_start?(@bytes[@i])
          return lex_identifier
        end

        if digit?(@bytes[@i])
          return lex_number
        end

        if quote?(@bytes[@i])
          return lex_string
        end

        if operator_or_punct?
          return lex_operator_or_punct
        end

        emit_unexpected_char
        advance_byte
      end
    end

    private def starts_var? : Bool
      return false if @i + 1 >= @length
      @bytes[@i] == '{'.ord.to_u8 && @bytes[@i + 1] == '{'.ord.to_u8
    end

    private def starts_block? : Bool
      return false if @i + 1 >= @length
      @bytes[@i] == '{'.ord.to_u8 && @bytes[@i + 1] == '%'.ord.to_u8
    end

    private def starts_var_end? : Bool
      return false if @i + 1 >= @length
      if @bytes[@i] == '-'.ord.to_u8
        return false if @i + 2 >= @length
        return @bytes[@i + 1] == '}'.ord.to_u8 && @bytes[@i + 2] == '}'.ord.to_u8
      end
      @bytes[@i] == '}'.ord.to_u8 && @bytes[@i + 1] == '}'.ord.to_u8
    end

    private def starts_block_end? : Bool
      return false if @i + 1 >= @length
      if @bytes[@i] == '-'.ord.to_u8
        return false if @i + 2 >= @length
        return @bytes[@i + 1] == '%'.ord.to_u8 && @bytes[@i + 2] == '}'.ord.to_u8
      end
      @bytes[@i] == '%'.ord.to_u8 && @bytes[@i + 1] == '}'.ord.to_u8
    end

    private def lex_var_start : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      # {{ or {{-
      advance_byte
      advance_byte
      if @i < @length && @bytes[@i] == '-'.ord.to_u8
        advance_byte
      end

      @mode = Mode::Expr
      @mode_start_offset = start_offset
      @mode_start_line = start_line
      @mode_start_col = start_col
      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::VarStart, lexeme, span)
    end

    private def lex_block_start : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      # {% or {%-
      advance_byte
      advance_byte
      if @i < @length && @bytes[@i] == '-'.ord.to_u8
        advance_byte
      end

      @mode = Mode::Block
      @mode_start_offset = start_offset
      @mode_start_line = start_line
      @mode_start_col = start_col
      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::BlockStart, lexeme, span)
    end

    private def lex_var_end(next_mode : Mode) : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      if @bytes[@i] == '-'.ord.to_u8
        advance_byte
      end
      advance_byte
      advance_byte

      @mode = next_mode
      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::VarEnd, lexeme, span)
    end

    private def lex_block_end(next_mode : Mode) : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      if @bytes[@i] == '-'.ord.to_u8
        advance_byte
      end
      advance_byte
      advance_byte

      @mode = next_mode
      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::BlockEnd, lexeme, span)
    end

    private def lex_whitespace : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      while @i < @length && whitespace_byte?(@bytes[@i])
        advance_byte
      end

      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::Whitespace, lexeme, span)
    end

    private def lex_identifier : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      advance_byte
      while @i < @length && identifier_part?(@bytes[@i])
        advance_byte
      end

      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::Identifier, lexeme, span)
    end

    private def lex_number : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      while @i < @length && digit?(@bytes[@i])
        advance_byte
      end

      if @i < @length && @bytes[@i] == '.'.ord.to_u8
        advance_byte
        while @i < @length && digit?(@bytes[@i])
          advance_byte
        end
      end

      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::Number, lexeme, span)
    end

    private def lex_string : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      quote = @bytes[@i]
      advance_byte

      while @i < @length
        if @bytes[@i] == '\\'.ord.to_u8
          advance_byte
          advance_byte if @i < @length
          next
        end
        break if @bytes[@i] == quote
        advance_byte
      end

      if @i >= @length
        emit_diagnostic("E_UNTERMINATED_STRING", "Unterminated string literal.", start_offset, start_line, start_col)
        span = make_span(start_offset, start_line, start_col)
        lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
        return Token.new(TokenType::String, lexeme, span)
      end

      advance_byte

      span = make_span(start_offset, start_line, start_col)
      lexeme = @source.byte_slice(start_offset, span.end_pos.offset - start_offset)
      Token.new(TokenType::String, lexeme, span)
    end

    private def operator_or_punct? : Bool
      byte = @bytes[@i]
      return true if byte == '+'.ord.to_u8
      return true if byte == '-'.ord.to_u8
      return true if byte == '*'.ord.to_u8
      return true if byte == '/'.ord.to_u8
      return true if byte == '%'.ord.to_u8
      return true if byte == '|'.ord.to_u8
      return true if byte == '.'.ord.to_u8
      return true if byte == '~'.ord.to_u8
      return true if byte == '<'.ord.to_u8
      return true if byte == '>'.ord.to_u8
      return true if byte == '='.ord.to_u8
      return true if byte == '!'.ord.to_u8
      return true if byte == '('.ord.to_u8
      return true if byte == ')'.ord.to_u8
      return true if byte == '['.ord.to_u8
      return true if byte == ']'.ord.to_u8
      return true if byte == '{'.ord.to_u8
      return true if byte == '}'.ord.to_u8
      return true if byte == ','.ord.to_u8
      return true if byte == ':'.ord.to_u8
      false
    end

    private def lex_operator_or_punct : Token
      start_offset = @i
      start_line = @line
      start_col = @column

      if two_char_operator?
        advance_byte
        advance_byte
      else
        advance_byte
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
      return false if @i + 1 >= @length
      a = @bytes[@i]
      b = @bytes[@i + 1]
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
      return true if lexeme == "("
      return true if lexeme == ")"
      return true if lexeme == "["
      return true if lexeme == "]"
      return true if lexeme == "{" 
      return true if lexeme == "}"
      return true if lexeme == ","
      return true if lexeme == ":"
      false
    end

    private def unterminated(end_type : TokenType) : Token
      if end_type == TokenType::VarEnd
        emit_diagnostic("E_UNTERMINATED_EXPRESSION", "Unterminated expression; expected '}}'.", @mode_start_offset, @mode_start_line, @mode_start_col)
      else
        emit_diagnostic("E_UNTERMINATED_BLOCK", "Unterminated block; expected '%}'.", @mode_start_offset, @mode_start_line, @mode_start_col)
      end
      eof_token
    end

    private def emit_unexpected_char
      start_offset = @i
      start_line = @line
      start_col = @column
      byte = @bytes[@i]
      end_offset = start_offset + 1
      if byte == '\n'.ord.to_u8
        end_line = start_line + 1
        end_col = 1
      else
        end_line = start_line
        end_col = start_col + 1
      end
      span = Span.new(Position.new(start_offset, start_line, start_col), Position.new(end_offset, end_line, end_col))
      message = "Unexpected character '#{@source.byte_slice(start_offset, 1)}' in expression."
      @diagnostics << Diagnostic.new("E_UNEXPECTED_CHAR", Severity::Error, message, span)
    end

    private def emit_diagnostic(id : String, message : String, start_offset : Int32? = nil, start_line : Int32? = nil, start_col : Int32? = nil)
      if start_offset
        span = make_span(start_offset, start_line.not_nil!, start_col.not_nil!)
      else
        span = make_span(@i, @line, @column)
      end
      @diagnostics << Diagnostic.new(id, Severity::Error, message, span)
    end

    private def make_span(start_offset : Int32, start_line : Int32, start_col : Int32) : Span
      Span.new(Position.new(start_offset, start_line, start_col), Position.new(@i, @line, @column))
    end

    private def eof_token : Token
      start_offset = @i
      start_line = @line
      start_col = @column
      span = Span.new(Position.new(start_offset, start_line, start_col), Position.new(start_offset, start_line, start_col))
      Token.new(TokenType::EOF, "", span)
    end

    private def advance_byte
      byte = @bytes[@i]
      @i += 1
      if byte == '\n'.ord.to_u8
        @line += 1
        @column = 1
      else
        @column += 1
      end
    end

    private def whitespace_byte?(byte : UInt8) : Bool
      byte == ' '.ord.to_u8 || byte == '\t'.ord.to_u8 || byte == '\n'.ord.to_u8 || byte == '\r'.ord.to_u8
    end

    private def identifier_start?(byte : UInt8) : Bool
      (byte >= 'A'.ord.to_u8 && byte <= 'Z'.ord.to_u8) ||
        (byte >= 'a'.ord.to_u8 && byte <= 'z'.ord.to_u8) ||
        byte == '_'.ord.to_u8
    end

    private def identifier_part?(byte : UInt8) : Bool
      identifier_start?(byte) || digit?(byte)
    end

    private def digit?(byte : UInt8) : Bool
      byte >= '0'.ord.to_u8 && byte <= '9'.ord.to_u8
    end

    private def quote?(byte : UInt8) : Bool
      byte == '\''.ord.to_u8 || byte == '"'.ord.to_u8
    end
  end
end
