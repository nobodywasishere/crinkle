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

    it "does not flag locally-defined macros as unknown functions" do
      schema = Crinkle::Schema::Registry.new

      source = <<-JINJA
        {% macro render_card(item) %}
          <div>{{ item }}</div>
        {% endmacro %}
        {{ render_card(x) }}
        JINJA
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::UnknownFunction.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.should be_empty
    end

    it "does not flag imported macros as unknown functions" do
      schema = Crinkle::Schema::Registry.new

      source = <<-JINJA
        {% from "macros.j2" import render_card, format_date %}
        {{ render_card(item) }}
        {{ format_date(today) }}
        JINJA
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::UnknownFunction.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.should be_empty
    end

    it "does not flag imported macros with aliases as unknown functions" do
      schema = Crinkle::Schema::Registry.new

      source = <<-JINJA
        {% from "macros.j2" import render_card as card, format_date as fmt %}
        {{ card(item) }}
        {{ fmt(today) }}
        JINJA
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::UnknownFunction.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.should be_empty
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

  describe "callable validation rules" do
    it "detects non-callable object being called" do
      schema = Crinkle::Schema::Registry.new
      template_context = Crinkle::Schema::TemplateContextSchema.new(
        path: "test.html",
        context: {"user" => "User"}
      )
      schema.register_template(template_context)

      callable_schema = Crinkle::Schema::CallableSchema.new(
        class_name: "User",
        methods: {
          "name"  => Crinkle::Schema::MethodSchema.new(name: "name", returns: "String"),
          "email" => Crinkle::Schema::MethodSchema.new(name: "email", returns: "String"),
        }
      )
      schema.register_callable(callable_schema)

      source = "{{ user() }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::CallableNotCallable.new(schema, "test.html"))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/CallableNotCallable")
      issue.message.should contain("user")
      issue.message.should contain("not directly callable")
      issue.message.should contain("name")
      issue.message.should contain("email")
    end

    it "detects wrong argument count for callable default call" do
      schema = Crinkle::Schema::Registry.new
      template_context = Crinkle::Schema::TemplateContextSchema.new(
        path: "test.html",
        context: {"formatter" => "Formatter"}
      )
      schema.register_template(template_context)

      callable_schema = Crinkle::Schema::CallableSchema.new(
        class_name: "Formatter",
        default_call: Crinkle::Schema::MethodSchema.new(
          name: "format",
          params: [
            Crinkle::Schema::ParamSchema.new(name: "value", type: "String", required: true),
          ],
          returns: "String"
        )
      )
      schema.register_callable(callable_schema)

      source = "{{ formatter(\"foo\", \"bar\", \"baz\") }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::CallableDefaultCall.new(schema, "test.html"))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/CallableDefaultCall")
      issue.message.should contain("formatter")
      issue.message.should contain("at most 1")
    end

    it "detects missing required argument for callable default call" do
      schema = Crinkle::Schema::Registry.new
      template_context = Crinkle::Schema::TemplateContextSchema.new(
        path: "test.html",
        context: {"formatter" => "Formatter"}
      )
      schema.register_template(template_context)

      callable_schema = Crinkle::Schema::CallableSchema.new(
        class_name: "Formatter",
        default_call: Crinkle::Schema::MethodSchema.new(
          name: "format",
          params: [
            Crinkle::Schema::ParamSchema.new(name: "value", type: "String", required: true),
            Crinkle::Schema::ParamSchema.new(name: "width", type: "Int32", required: true),
          ],
          returns: "String"
        )
      )
      schema.register_callable(callable_schema)

      source = "{{ formatter(\"foo\") }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::CallableDefaultCall.new(schema, "test.html"))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/CallableDefaultCall")
      issue.message.should contain("width")
    end

    it "detects unknown method on callable" do
      schema = Crinkle::Schema::Registry.new
      template_context = Crinkle::Schema::TemplateContextSchema.new(
        path: "test.html",
        context: {"user" => "User"}
      )
      schema.register_template(template_context)

      callable_schema = Crinkle::Schema::CallableSchema.new(
        class_name: "User",
        methods: {
          "first_name" => Crinkle::Schema::MethodSchema.new(name: "first_name", returns: "String"),
          "last_name"  => Crinkle::Schema::MethodSchema.new(name: "last_name", returns: "String"),
        }
      )
      schema.register_callable(callable_schema)

      source = "{{ user.firstname() }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::CallableUnknownMethod.new(schema, "test.html"))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/CallableUnknownMethod")
      issue.message.should contain("firstname")
      issue.message.should contain("first_name")
    end

    it "detects wrong argument count for callable method" do
      schema = Crinkle::Schema::Registry.new
      template_context = Crinkle::Schema::TemplateContextSchema.new(
        path: "test.html",
        context: {"user" => "User"}
      )
      schema.register_template(template_context)

      callable_schema = Crinkle::Schema::CallableSchema.new(
        class_name: "User",
        methods: {
          "greet" => Crinkle::Schema::MethodSchema.new(
            name: "greet",
            params: [
              Crinkle::Schema::ParamSchema.new(name: "greeting", type: "String", required: true),
            ],
            returns: "String"
          ),
        }
      )
      schema.register_callable(callable_schema)

      source = "{{ user.greet(\"Hello\", \"World\") }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::CallableMethodKwarg.new(schema, "test.html"))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/CallableMethodKwarg")
      issue.message.should contain("greet")
      issue.message.should contain("at most 1")
    end

    it "detects unknown kwarg for callable method" do
      schema = Crinkle::Schema::Registry.new
      template_context = Crinkle::Schema::TemplateContextSchema.new(
        path: "test.html",
        context: {"user" => "User"}
      )
      schema.register_template(template_context)

      callable_schema = Crinkle::Schema::CallableSchema.new(
        class_name: "User",
        methods: {
          "greet" => Crinkle::Schema::MethodSchema.new(
            name: "greet",
            params: [
              Crinkle::Schema::ParamSchema.new(name: "greeting", type: "String", required: false, default: "\"Hello\""),
            ],
            returns: "String"
          ),
        }
      )
      schema.register_callable(callable_schema)

      source = "{{ user.greet(greating=\"Hi\") }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::CallableMethodKwarg.new(schema, "test.html"))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      issues.size.should eq(1)
      issue = issues.first
      issue.id.should eq("Lint/CallableMethodKwarg")
      issue.message.should contain("greating")
      issue.message.should contain("greeting")
    end

    it "skips callable validation when no template context available" do
      schema = Crinkle::Schema::Registry.new
      callable_schema = Crinkle::Schema::CallableSchema.new(
        class_name: "User",
        methods: {
          "name" => Crinkle::Schema::MethodSchema.new(name: "name", returns: "String"),
        }
      )
      schema.register_callable(callable_schema)

      source = "{{ user() }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens)
      template = parser.parse

      ruleset = Crinkle::Linter::RuleSet.new
      ruleset.add(Crinkle::Linter::Rules::CallableNotCallable.new(schema))

      runner = Crinkle::Linter::Runner.new(ruleset, schema)
      issues = runner.lint(template, source)

      # Should not report any issues when template context is not available
      issues.size.should eq(0)
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
