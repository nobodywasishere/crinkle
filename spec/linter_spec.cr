require "./spec_helper"

describe Crinkle::Linter do
  it "maps diagnostics to linter issues" do
    span = Crinkle::Span.new(
      Crinkle::Position.new(0, 1, 1),
      Crinkle::Position.new(1, 1, 2),
    )
    diag = Crinkle::Diagnostic.new(
      Crinkle::DiagnosticType::UnknownTag,
      Crinkle::Severity::Error,
      "unknown tag",
      span,
    )

    issues = Crinkle::Linter.map_diagnostics([diag])

    issues.size.should eq(1)
    issue = issues.first
    issue.id.should eq("Parser/UnknownTag")
    issue.severity.should eq(Crinkle::Severity::Error)
    issue.message.should eq("unknown tag")
    issue.span.should eq(span)
    issue.source_type.should eq(Crinkle::DiagnosticType::UnknownTag)
  end
end
