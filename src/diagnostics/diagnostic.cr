module Jinja
  enum DiagnosticType
    UnterminatedExpression
    UnterminatedBlock
    UnterminatedString
    UnexpectedChar
  end

  enum Severity
    Error
    Warning
    Info
  end

  struct Position
    getter offset : Int32
    getter line : Int32
    getter column : Int32

    def initialize(@offset : Int32, @line : Int32, @column : Int32)
    end
  end

  struct Span
    getter start_pos : Position
    getter end_pos : Position

    def initialize(@start_pos : Position, @end_pos : Position)
    end
  end

  struct Diagnostic
    getter type : DiagnosticType
    getter severity : Severity
    getter message : String
    getter span : Span

    def initialize(@type : DiagnosticType, @severity : Severity, @message : String, @span : Span)
    end

    def id : String
      @type.to_s.underscore.capitalize
    end
  end
end
