require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe "Linter::Issue.from_diagnostic" do
    it "creates Issue from Diagnostic" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 5),
        Crinkle::Position.new(10, 1, 15)
      )
      diag = Crinkle::Diagnostic.new(
        Crinkle::DiagnosticType::UnknownFilter,
        Crinkle::Severity::Warning,
        "Unknown filter 'foo'",
        span
      )

      issue = Crinkle::Linter::Issue.from_diagnostic(diag)

      issue.id.should eq "E_UNKNOWN_FILTER"
      issue.severity.should eq Crinkle::Severity::Warning
      issue.message.should eq "Unknown filter 'foo'"
      issue.span.should eq span
      issue.source_type.should eq Crinkle::DiagnosticType::UnknownFilter
    end

    it "preserves error severity" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 1, 1),
        Crinkle::Position.new(5, 1, 6)
      )
      diag = Crinkle::Diagnostic.new(
        Crinkle::DiagnosticType::UnterminatedExpression,
        Crinkle::Severity::Error,
        "Unterminated expression",
        span
      )

      issue = Crinkle::Linter::Issue.from_diagnostic(diag)

      issue.severity.should eq Crinkle::Severity::Error
    end
  end
end
