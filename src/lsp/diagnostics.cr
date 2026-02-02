# Diagnostic conversion utilities for LSP.
# Converts Crinkle linter issues to LSP diagnostic format.

module Crinkle::LSP
  # Converts linter issues to LSP diagnostics.
  module Diagnostics
    # Convert a single linter issue to an LSP diagnostic.
    def self.convert(issue : Linter::Issue) : Diagnostic
      Diagnostic.new(
        range: span_to_range(issue.span),
        message: issue.message,
        severity: map_severity(issue.severity),
        code: issue.id,
        source: "crinkle"
      )
    end

    # Convert a collection of linter issues to LSP diagnostics.
    def self.convert_all(issues : Array(Linter::Issue)) : Array(Diagnostic)
      issues.map { |issue| convert(issue) }
    end

    # Convert a Crinkle span to an LSP range.
    # Crinkle uses 1-based lines/columns, LSP uses 0-based.
    private def self.span_to_range(span : Span) : Range
      start_pos = Position.new(
        line: span.start_pos.line - 1,
        character: span.start_pos.column - 1
      )
      end_pos = Position.new(
        line: span.end_pos.line - 1,
        character: span.end_pos.column - 1
      )
      Range.new(start: start_pos, end_pos: end_pos)
    end

    # Map Crinkle severity to LSP severity.
    private def self.map_severity(severity : Severity) : DiagnosticSeverity
      case severity
      when .error?   then DiagnosticSeverity::Error
      when .warning? then DiagnosticSeverity::Warning
      else                DiagnosticSeverity::Information
      end
    end
  end

  # Analyzer runs the full analysis pipeline: lex → parse → lint.
  class Analyzer
    getter linter : Linter::Runner

    def initialize(@linter : Linter::Runner = Linter::Runner.new) : Nil
    end

    # Analyze a template and return linter issues.
    def analyze(text : String) : Array(Linter::Issue)
      # Lex the template
      lexer = Lexer.new(text)
      tokens = lexer.lex_all
      lex_diagnostics = lexer.diagnostics

      # Parse the template
      parser = Parser.new(tokens)
      ast = parser.parse
      parse_diagnostics = parser.diagnostics

      # Combine lexer and parser diagnostics
      all_diagnostics = lex_diagnostics + parse_diagnostics

      # Run linter (includes mapped diagnostics + lint rules)
      @linter.lint(ast, text, all_diagnostics)
    end

    # Analyze a template and return LSP diagnostics.
    def analyze_to_lsp(text : String) : Array(Diagnostic)
      issues = analyze(text)
      Diagnostics.convert_all(issues)
    end
  end
end
