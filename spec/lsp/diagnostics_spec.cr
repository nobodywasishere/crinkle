require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::Diagnostics do
    it "converts linter issue to LSP diagnostic" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 5),
        Crinkle::Position.new(10, 1, 15)
      )
      issue = Crinkle::Linter::Issue.new(
        id: "Lint/TestRule",
        severity: Crinkle::Severity::Warning,
        message: "Test warning message",
        span: span
      )

      diag = Crinkle::LSP::Diagnostics.convert(issue)

      diag.range.start.line.should eq 0      # 1-based -> 0-based
      diag.range.start.character.should eq 4 # 5 -> 4
      diag.range.end_pos.line.should eq 0
      diag.range.end_pos.character.should eq 14
      diag.message.should eq "Test warning message"
      diag.severity.should eq Crinkle::LSP::DiagnosticSeverity::Warning
      diag.code.should eq "Lint/TestRule"
      diag.source.should eq "crinkle"
    end

    it "maps error severity correctly" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 1),
        Crinkle::Position.new(5, 1, 6)
      )
      issue = Crinkle::Linter::Issue.new(
        id: "Lexer/UnterminatedString",
        severity: Crinkle::Severity::Error,
        message: "Unterminated string",
        span: span
      )

      diag = Crinkle::LSP::Diagnostics.convert(issue)

      diag.severity.should eq Crinkle::LSP::DiagnosticSeverity::Error
    end

    it "maps info severity correctly" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 1),
        Crinkle::Position.new(5, 1, 6)
      )
      issue = Crinkle::Linter::Issue.new(
        id: "Lint/Info",
        severity: Crinkle::Severity::Info,
        message: "Info message",
        span: span
      )

      diag = Crinkle::LSP::Diagnostics.convert(issue)

      diag.severity.should eq Crinkle::LSP::DiagnosticSeverity::Information
    end

    it "converts multiple issues" do
      span1 = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 1),
        Crinkle::Position.new(5, 1, 6)
      )
      span2 = Crinkle::Span.new(
        Crinkle::Position.new(10, 2, 1),
        Crinkle::Position.new(15, 2, 6)
      )
      issues = [
        Crinkle::Linter::Issue.new("Lint/A", Crinkle::Severity::Error, "Error A", span1),
        Crinkle::Linter::Issue.new("Lint/B", Crinkle::Severity::Warning, "Warning B", span2),
      ]

      diagnostics = Crinkle::LSP::Diagnostics.convert_all(issues)

      diagnostics.size.should eq 2
      diagnostics[0].message.should eq "Error A"
      diagnostics[1].message.should eq "Warning B"
    end
  end
end
