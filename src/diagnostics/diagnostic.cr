module Jinja
  enum DiagnosticType
    UnterminatedExpression
    UnterminatedBlock
    UnterminatedString
    UnexpectedChar
    UnexpectedToken
    ExpectedToken
    ExpectedExpression
    MissingEndTag
    UnknownTag
    UnexpectedEndTag
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

    def initialize(@offset : Int32, @line : Int32, @column : Int32) : Nil
    end
  end

  struct Span
    getter start_pos : Position
    getter end_pos : Position

    def initialize(@start_pos : Position, @end_pos : Position) : Nil
    end
  end

  struct Diagnostic
    getter type : DiagnosticType
    getter severity : Severity
    getter message : String
    getter span : Span

    def initialize(@type : DiagnosticType, @severity : Severity, @message : String, @span : Span) : Nil
    end

    def id : String
      case @type
      when DiagnosticType::UnterminatedExpression
        "E_UNTERMINATED_EXPRESSION"
      when DiagnosticType::UnterminatedBlock
        "E_UNTERMINATED_BLOCK"
      when DiagnosticType::UnterminatedString
        "E_UNTERMINATED_STRING"
      when DiagnosticType::UnexpectedChar
        "E_UNEXPECTED_CHAR"
      when DiagnosticType::UnexpectedToken
        "E_UNEXPECTED_TOKEN"
      when DiagnosticType::ExpectedToken
        "E_EXPECTED_TOKEN"
      when DiagnosticType::ExpectedExpression
        "E_EXPECTED_EXPRESSION"
      when DiagnosticType::MissingEndTag
        "E_MISSING_END_TAG"
      when DiagnosticType::UnknownTag
        "E_UNKNOWN_TAG"
      when DiagnosticType::UnexpectedEndTag
        "E_UNEXPECTED_END_TAG"
      else
        "E_UNKNOWN_DIAGNOSTIC"
      end
    end
  end
end
