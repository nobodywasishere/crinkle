require "./spec_helper"

describe Jinja::Linter do
  it "maps diagnostics to linter issues" do
    span = Jinja::Span.new(
      Jinja::Position.new(0, 1, 1),
      Jinja::Position.new(1, 1, 2),
    )
    diag = Jinja::Diagnostic.new(
      Jinja::DiagnosticType::UnknownTag,
      Jinja::Severity::Error,
      "unknown tag",
      span,
    )

    issues = Jinja::Linter.map_diagnostics([diag])

    issues.size.should eq(1)
    issue = issues.first
    issue.id.should eq("Parser/UnknownTag")
    issue.severity.should eq(Jinja::Severity::Error)
    issue.message.should eq("unknown tag")
    issue.span.should eq(span)
    issue.source_type.should eq(Jinja::DiagnosticType::UnknownTag)
  end
end
