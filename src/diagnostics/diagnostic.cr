module Jinja
  enum DiagnosticType
    UnterminatedExpression
    UnterminatedBlock
    UnterminatedString
    UnterminatedComment
    UnexpectedChar
    UnexpectedToken
    ExpectedToken
    ExpectedExpression
    MissingEndTag
    UnknownTag
    UnexpectedEndTag
    UnknownVariable
    UnknownFilter
    UnknownTest
    UnknownFunction
    UnknownTagRenderer
    InvalidOperand
    NotIterable
    UnsupportedNode
    TemplateNotFound
    UnknownMacro
    TemplateCycle
    HtmlUnexpectedEndTag
    HtmlMismatchedEndTag
    HtmlUnclosedTag
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
      in DiagnosticType::UnterminatedExpression then "E_UNTERMINATED_EXPRESSION"
      in DiagnosticType::UnterminatedBlock      then "E_UNTERMINATED_BLOCK"
      in DiagnosticType::UnterminatedString     then "E_UNTERMINATED_STRING"
      in DiagnosticType::UnterminatedComment    then "E_UNTERMINATED_COMMENT"
      in DiagnosticType::UnexpectedChar         then "E_UNEXPECTED_CHAR"
      in DiagnosticType::UnexpectedToken        then "E_UNEXPECTED_TOKEN"
      in DiagnosticType::ExpectedToken          then "E_EXPECTED_TOKEN"
      in DiagnosticType::ExpectedExpression     then "E_EXPECTED_EXPRESSION"
      in DiagnosticType::MissingEndTag          then "E_MISSING_END_TAG"
      in DiagnosticType::UnknownTag             then "E_UNKNOWN_TAG"
      in DiagnosticType::UnexpectedEndTag       then "E_UNEXPECTED_END_TAG"
      in DiagnosticType::UnknownVariable        then "E_UNKNOWN_VARIABLE"
      in DiagnosticType::UnknownFilter          then "E_UNKNOWN_FILTER"
      in DiagnosticType::UnknownTest            then "E_UNKNOWN_TEST"
      in DiagnosticType::UnknownFunction        then "E_UNKNOWN_FUNCTION"
      in DiagnosticType::UnknownTagRenderer     then "E_UNKNOWN_TAG_RENDERER"
      in DiagnosticType::InvalidOperand         then "E_INVALID_OPERAND"
      in DiagnosticType::NotIterable            then "E_NOT_ITERABLE"
      in DiagnosticType::UnsupportedNode        then "E_UNSUPPORTED_NODE"
      in DiagnosticType::TemplateNotFound       then "E_TEMPLATE_NOT_FOUND"
      in DiagnosticType::UnknownMacro           then "E_UNKNOWN_MACRO"
      in DiagnosticType::TemplateCycle          then "E_TEMPLATE_CYCLE"
      in DiagnosticType::HtmlUnexpectedEndTag   then "E_HTML_UNEXPECTED_END_TAG"
      in DiagnosticType::HtmlMismatchedEndTag   then "E_HTML_MISMATCHED_END_TAG"
      in DiagnosticType::HtmlUnclosedTag        then "E_HTML_UNCLOSED_TAG"
      end
    end
  end
end
