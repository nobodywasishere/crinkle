require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::Analyzer do
    it "analyzes template with syntax error" do
      analyzer = Crinkle::LSP::Analyzer.new

      # Template with unterminated expression
      issues = analyzer.analyze("Hello {{ name")

      issues.size.should be > 0
      issues.any? { |i| i.id.includes?("Lexer/") || i.id.includes?("Parser/") }.should be_true
    end

    it "analyzes valid template" do
      analyzer = Crinkle::LSP::Analyzer.new

      issues = analyzer.analyze("Hello {{ name }}")

      # May have lint issues (like formatting) but no syntax errors
      syntax_errors = issues.select { |i| i.id.starts_with?("Lexer/") || i.id.starts_with?("Parser/") }
      syntax_errors.size.should eq 0
    end

    it "returns LSP diagnostics directly" do
      analyzer = Crinkle::LSP::Analyzer.new

      diagnostics = analyzer.analyze_to_lsp("Hello {{ name")

      diagnostics.size.should be > 0
      diagnostics.all? { |diag| diag.source == "crinkle" }.should be_true
    end

    it "includes linter rules in analysis" do
      analyzer = Crinkle::LSP::Analyzer.new

      # Template with duplicate block names
      template = <<-JINJA
        {% block content %}Hello{% endblock %}
        {% block content %}World{% endblock %}
        JINJA

      issues = analyzer.analyze(template)

      # Should have duplicate block lint issue
      issues.any? { |issue| issue.id == "Lint/DuplicateBlock" }.should be_true
    end
  end
end
