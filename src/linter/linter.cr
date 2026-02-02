module Crinkle
  module Linter
    struct Issue
      getter id : String
      getter severity : Severity
      getter message : String
      getter span : Span
      getter source_type : DiagnosticType?

      def initialize(
        @id : String,
        @severity : Severity,
        @message : String,
        @span : Span,
        @source_type : DiagnosticType? = nil,
      ) : Nil
      end
    end

    class Context
      getter source : String
      getter template : AST::Template
      getter diagnostics : Array(Diagnostic)

      def initialize(
        @source : String,
        @template : AST::Template,
        @diagnostics : Array(Diagnostic),
      ) : Nil
      end
    end

    class Rule
      getter id : String
      getter severity : Severity

      def initialize(@id : String, @severity : Severity = Severity::Warning) : Nil
      end

      def check(_template : AST::Template, _context : Context) : Array(Issue)
        Array(Issue).new
      end

      protected def issue(span : Span, message : String, severity : Severity = @severity) : Issue
        Issue.new(@id, severity, message, span)
      end
    end

    class RuleSet
      def initialize : Nil
        @rules = Array(Rule).new
      end

      def add(rule : Rule) : Nil
        @rules << rule
      end

      def run(template : AST::Template, context : Context) : Array(Issue)
        issues = Array(Issue).new
        @rules.each do |rule|
          issues.concat(rule.check(template, context))
        end
        issues
      end
    end

    class Runner
      getter ruleset : RuleSet

      def initialize(@ruleset : RuleSet = Linter.default_ruleset) : Nil
      end

      def lint(
        template : AST::Template,
        source : String,
        diagnostics : Array(Diagnostic) = Array(Diagnostic).new,
      ) : Array(Issue)
        context = Context.new(source, template, diagnostics)
        issues = Linter.map_diagnostics(diagnostics)
        issues.concat(@ruleset.run(template, context))
        issues
      end
    end

    def self.default_ruleset : RuleSet
      ruleset = RuleSet.new
      ruleset.add(Rules::MultipleExtends.new)
      ruleset.add(Rules::ExtendsNotFirst.new)
      ruleset.add(Rules::DuplicateBlock.new)
      ruleset.add(Rules::DuplicateMacro.new)
      # UnusedMacro not included - macros may be imported by other files
      ruleset.add(Rules::TrailingWhitespace.new)
      ruleset.add(Rules::MixedIndentation.new)
      ruleset.add(Rules::ExcessiveBlankLines.new)
      ruleset.add(Rules::Formatting.new)
      ruleset
    end

    DIAGNOSTIC_MAP = {
      DiagnosticType::UnterminatedExpression => "Lexer/UnterminatedExpression",
      DiagnosticType::UnterminatedBlock      => "Lexer/UnterminatedBlock",
      DiagnosticType::UnterminatedString     => "Lexer/UnterminatedString",
      DiagnosticType::UnterminatedComment    => "Lexer/UnterminatedComment",
      DiagnosticType::UnexpectedChar         => "Lexer/UnexpectedChar",
      DiagnosticType::UnexpectedToken        => "Parser/UnexpectedToken",
      DiagnosticType::ExpectedToken          => "Parser/ExpectedToken",
      DiagnosticType::ExpectedExpression     => "Parser/ExpectedExpression",
      DiagnosticType::MissingEndTag          => "Parser/MissingEndTag",
      DiagnosticType::UnknownTag             => "Parser/UnknownTag",
      DiagnosticType::UnexpectedEndTag       => "Parser/UnexpectedEndTag",
      DiagnosticType::UnknownVariable        => "Renderer/UnknownVariable",
      DiagnosticType::UnknownFilter          => "Renderer/UnknownFilter",
      DiagnosticType::UnknownTest            => "Renderer/UnknownTest",
      DiagnosticType::UnknownFunction        => "Renderer/UnknownFunction",
      DiagnosticType::UnknownTagRenderer     => "Renderer/UnknownTagRenderer",
      DiagnosticType::InvalidOperand         => "Renderer/InvalidOperand",
      DiagnosticType::NotIterable            => "Renderer/NotIterable",
      DiagnosticType::UnsupportedNode        => "Renderer/UnsupportedNode",
      DiagnosticType::TemplateNotFound       => "Renderer/TemplateNotFound",
      DiagnosticType::UnknownMacro           => "Renderer/UnknownMacro",
      DiagnosticType::TemplateCycle          => "Renderer/TemplateCycle",
      DiagnosticType::HtmlUnexpectedEndTag   => "Formatter/HtmlUnexpectedEndTag",
      DiagnosticType::HtmlMismatchedEndTag   => "Formatter/HtmlMismatchedEndTag",
      DiagnosticType::HtmlUnclosedTag        => "Formatter/HtmlUnclosedTag",
    } of DiagnosticType => String

    def self.map_diagnostics(diagnostics : Array(Diagnostic)) : Array(Issue)
      diagnostics.map do |diag|
        id = DIAGNOSTIC_MAP[diag.type]? || "Lint/UnknownDiagnostic"
        Issue.new(id, diag.severity, diag.message, diag.span, diag.type)
      end
    end
  end
end
