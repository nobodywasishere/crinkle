module Crinkle
  enum TokenType
    Text
    Comment
    VarStart
    VarEnd
    BlockStart
    BlockEnd
    Identifier
    Number
    String
    Operator
    Punct
    Whitespace
    EOF
  end

  struct Token
    getter type : TokenType
    getter lexeme : String
    getter span : Span

    def initialize(@type : TokenType, @lexeme : String, @span : Span) : Nil
    end
  end
end
