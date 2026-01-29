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

  it "matches linter snapshots for fixtures" do
    Dir.glob("fixtures/templates/lint_*.j2").sort.each do |path|
      source = File.read(path)
      lexer = Jinja::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Jinja::Parser.new(tokens)
      template = parser.parse
      diagnostics = lexer.diagnostics + parser.diagnostics
      issues = Jinja::Linter::Runner.new.lint(template, source, diagnostics)

      snapshot_path = File.join(
        "fixtures",
        "linter_diagnostics",
        "#{File.basename(path, ".j2")}.json",
      )
      assert_lint_snapshot(snapshot_path, issues)
    end
  end
end
