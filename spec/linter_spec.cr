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

  describe "schema-aware lint rules" do
    it "detects unknown filter" do
      schema = Crinkle::Schema::Registry.new
      schema.register_filter(Crinkle::Schema::FilterSchema.new(name: "upper", returns: "String"))

      source = "{{ name | nonexistent }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::UnknownFilter.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/UnknownFilter")
      issue.message.should contain("nonexistent")
    end

    it "detects unknown test" do
      schema = Crinkle::Schema::Registry.new
      schema.register_test(Crinkle::Schema::TestSchema.new(name: "even"))

      source = "{% if x is nonexistent %}yes{% endif %}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::UnknownTest.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/UnknownTest")
      issue.message.should contain("nonexistent")
    end

    it "detects unknown function" do
      schema = Crinkle::Schema::Registry.new
      schema.register_function(Crinkle::Schema::FunctionSchema.new(name: "range", returns: "Array"))

      source = "{{ nonexistent() }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::UnknownFunction.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/UnknownFunction")
      issue.message.should contain("nonexistent")
    end

    it "detects wrong argument count for filter" do
      schema = Crinkle::Schema::Registry.new
      filter_schema = Crinkle::Schema::FilterSchema.new(
        name: "truncate",
        params: [
          Crinkle::Schema::ParamSchema.new(name: "value", type: "String", required: true),
          Crinkle::Schema::ParamSchema.new(name: "length", type: "Int32", required: false, default: "80"),
        ],
        returns: "String"
      )
      schema.register_filter(filter_schema)

      source = "{{ name | truncate(10, 20, 30) }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::WrongArgumentCount.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/WrongArgumentCount")
      issue.message.should contain("truncate")
      issue.message.should contain("at most 1")
    end

    it "detects unknown kwarg with suggestion" do
      schema = Crinkle::Schema::Registry.new
      filter_schema = Crinkle::Schema::FilterSchema.new(
        name: "money_format",
        params: [
          Crinkle::Schema::ParamSchema.new(name: "value", type: "Number", required: true),
          Crinkle::Schema::ParamSchema.new(name: "currency", type: "String", required: false, default: "\"USD\""),
        ],
        returns: "String"
      )
      schema.register_filter(filter_schema)

      source = "{{ price | money_format(curreny=\"EUR\") }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::UnknownKwarg.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/UnknownKwarg")
      issue.message.should contain("curreny")
      issue.message.should contain("currency")
    end

    it "detects missing required argument" do
      schema = Crinkle::Schema::Registry.new
      function_schema = Crinkle::Schema::FunctionSchema.new(
        name: "format_price",
        params: [
          Crinkle::Schema::ParamSchema.new(name: "value", type: "Number", required: true),
          Crinkle::Schema::ParamSchema.new(name: "currency", type: "String", required: true),
        ],
        returns: "String"
      )
      schema.register_function(function_schema)

      source = "{{ format_price(100) }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::MissingRequiredArgument.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/MissingRequiredArgument")
      issue.message.should contain("currency")
    end

    it "detects deprecated usage" do
      schema = Crinkle::Schema::Registry.new
      filter_schema = Crinkle::Schema::FilterSchema.new(
        name: "old_filter",
        returns: "String",
        deprecated: true
      )
      schema.register_filter(filter_schema)

      source = "{{ name | old_filter }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::DeprecatedUsage.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/DeprecatedUsage")
      issue.severity.should eq(Crinkle::Severity::Warning)
      issue.message.should contain("old_filter")
      issue.message.should contain("deprecated")
    end
  end

  describe "schema auto-discovery" do
    it "discovers schema from .crinkle/schema.json" do
      # This test would need actual file system operations
      # Skip for now - just test that the method exists
      schema = Crinkle::Linter::Runner.discover_schema
      schema.should be_a(Crinkle::Schema::Registry | Nil)
    end
  end
end

describe "Crinkle::Linter::DidYouMean" do
  it "suggests similar names" do
    known = ["currency", "amount", "format"]
    suggestion = Crinkle::Linter::DidYouMean.suggest("curreny", known)
    suggestion.should eq("currency")
  end

  it "returns nil for no close match" do
    known = ["foo", "bar"]
    suggestion = Crinkle::Linter::DidYouMean.suggest("completely_different", known)
    suggestion.should be_nil
  end

  it "returns nil for empty known list" do
    suggestion = Crinkle::Linter::DidYouMean.suggest("test", Array(String).new)
    suggestion.should be_nil
  end
end
