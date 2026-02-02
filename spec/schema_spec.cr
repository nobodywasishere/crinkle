require "./spec_helper"

# Test callable class using annotations
class TestFormatter
  include Crinkle::Callable

  @[Crinkle::Method(
    params: {value: Number, currency: String},
    defaults: {currency: "USD"},
    returns: String,
    doc: "Format a number as currency"
  )]
  def price(args : Crinkle::Arguments) : String
    value = args.varargs[0]?.try(&.as?(Int64 | Float64)) || 0
    currency_val = args.kwargs["currency"]?
    currency = currency_val ? currency_val.to_s : "USD"
    sprintf("%.2f %s", value, currency)
  end

  @[Crinkle::Method(
    params: {value: Time, format: String},
    defaults: {format: "%Y-%m-%d"},
    returns: String,
    doc: "Format a date"
  )]
  def date(args : Crinkle::Arguments) : String
    format_val = args.kwargs["format"]?
    format = format_val ? format_val.to_s : "%Y-%m-%d"
    Time.utc.to_s(format)
  end

  @[Crinkle::DefaultCall(
    params: {value: Number},
    returns: String,
    doc: "Default format"
  )]
  def call(args : Crinkle::Arguments) : String
    value = args.varargs[0]?.try(&.as?(Int64 | Float64)) || 0
    value.to_s
  end
end

# Register a typed filter using macros
module TestTypedFilters
  Crinkle.define_filter :typed_upper,
    params: {value: String},
    returns: String,
    doc: "Convert string to uppercase" do |value|
    value.to_s.upcase
  end

  # Debug: manually implement what the macro should generate
  def self.register_filter_typed_truncate_manual(env : Crinkle::Environment) : Nil
    env.register_filter("typed_truncate_manual") do |value, args, kwargs, _ctx|
      # First param: value (is_first = true)
      __param_value = value

      # Second param: length (is_first = false, arg_index = 0)
      __raw_length = kwargs["length"]? || args[0]?
      __param_length = __raw_length || Crinkle.value(80)

      # Block body
      str = __param_value.to_s
      len = case __param_length
            when Int64   then __param_length.to_i
            when Int32   then __param_length.to_i
            when Float64 then __param_length.to_i
            else              80
            end
      result = str.size > len ? str[0...len] + "..." : str
      Crinkle.value(result)
    end
  end

  Crinkle.define_filter :typed_truncate,
    params: {value: String, length: Int32},
    defaults: {length: 80},
    returns: String,
    doc: "Truncate string to length" do |value, length|
    str = value.to_s
    len = length.to_s.to_i? || 80
    str.size > len ? str[0...len] + "..." : str
  end

  def self.register(env : Crinkle::Environment) : Nil
    register_filter_typed_upper(env)
    register_filter_typed_truncate(env)
    register_filter_typed_truncate_manual(env)
  end
end

# Register a typed test using macros
module TestTypedTests
  Crinkle.define_test :typed_even,
    params: {value: Number},
    doc: "Check if number is even" do |value|
    val = value.to_s.to_i64? || 0_i64
    val % 2 == 0
  end

  def self.register(env : Crinkle::Environment) : Nil
    register_test_typed_even(env)
  end
end

# Register a typed function using macros
module TestTypedFunctions
  Crinkle.define_function :typed_greet,
    params: {name: String, greeting: String},
    defaults: {greeting: "Hello"},
    returns: String,
    doc: "Create a greeting" do |name, greeting|
    "#{greeting}, #{name}!"
  end

  def self.register(env : Crinkle::Environment) : Nil
    register_function_typed_greet(env)
  end
end

describe "Crinkle::Schema" do
  describe "ParamSchema" do
    it "creates parameter with all fields" do
      param = Crinkle::Schema::ParamSchema.new(
        name: "value",
        type: "String",
        required: true,
        default: nil
      )
      param.name.should eq("value")
      param.type.should eq("String")
      param.required?.should be_true
      param.default.should be_nil
    end

    it "creates optional parameter with default" do
      param = Crinkle::Schema::ParamSchema.new(
        name: "length",
        type: "Int32",
        required: false,
        default: "80"
      )
      param.name.should eq("length")
      param.required?.should be_false
      param.default.should eq("80")
    end
  end

  describe "FilterSchema" do
    it "creates filter schema" do
      schema = Crinkle::Schema::FilterSchema.new(
        name: "truncate",
        params: [
          Crinkle::Schema::ParamSchema.new(name: "value", type: "String", required: true),
          Crinkle::Schema::ParamSchema.new(name: "length", type: "Int32", required: false, default: "80"),
        ],
        returns: "String",
        doc: "Truncate string to length"
      )
      schema.name.should eq("truncate")
      schema.params.size.should eq(2)
      schema.returns.should eq("String")
      schema.doc.should eq("Truncate string to length")
    end
  end

  describe "Registry" do
    it "stores and retrieves filters" do
      registry = Crinkle::Schema::Registry.new
      schema = Crinkle::Schema::FilterSchema.new(name: "test_filter", returns: "String")
      registry.register_filter(schema)
      registry.filters["test_filter"].should eq(schema)
    end

    it "stores and retrieves tests" do
      registry = Crinkle::Schema::Registry.new
      schema = Crinkle::Schema::TestSchema.new(name: "test_test")
      registry.register_test(schema)
      registry.tests["test_test"].should eq(schema)
    end

    it "stores and retrieves functions" do
      registry = Crinkle::Schema::Registry.new
      schema = Crinkle::Schema::FunctionSchema.new(name: "test_func", returns: "String")
      registry.register_function(schema)
      registry.functions["test_func"].should eq(schema)
    end

    it "serializes to JSON" do
      registry = Crinkle::Schema::Registry.new
      registry.register_filter(Crinkle::Schema::FilterSchema.new(name: "upper", returns: "String"))
      json = String.build { |str| JSON.build(str) { |builder| registry.to_json(builder) } }
      parsed = JSON.parse(json)
      parsed["version"].as_i.should eq(1)
      parsed["filters"]["upper"]["name"].as_s.should eq("upper")
    end
  end

  describe "Global Registry" do
    it "has global registry instance" do
      Crinkle::Schema.registry.should be_a(Crinkle::Schema::Registry)
    end

    it "exports to JSON" do
      json = Crinkle::Schema.to_json
      parsed = JSON.parse(json)
      parsed["version"].as_i.should eq(1)
    end
  end
end

describe "Crinkle typed macros" do
  describe "define_filter" do
    it "registers filter schema in global registry" do
      # The schema is registered at load time
      Crinkle::Schema.registry.filters.has_key?("typed_upper").should be_true
      schema = Crinkle::Schema.registry.filters["typed_upper"]
      schema.doc.should eq("Convert string to uppercase")
      schema.returns.should eq("String")
    end

    it "registers filter with params and defaults" do
      schema = Crinkle::Schema.registry.filters["typed_truncate"]
      schema.params.size.should eq(2)
      schema.params[0].name.should eq("value")
      schema.params[0].required?.should be_true
      schema.params[1].name.should eq("length")
      schema.params[1].required?.should be_false
      schema.params[1].default.should eq("80")
    end

    it "creates working filter" do
      env = Crinkle::Environment.new(load_std: false)
      TestTypedFilters.register(env)

      source = "{{ name | typed_upper }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      context = {"name" => "ada"} of String => Crinkle::Value
      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("ADA")
    end

    it "creates filter with default parameters" do
      env = Crinkle::Environment.new(load_std: false)
      TestTypedFilters.register(env)

      # Verify filters are registered
      env.filters.has_key?("typed_truncate").should be_true
      env.filters.has_key?("typed_truncate_manual").should be_true

      # Call both filters directly to compare
      ctx = Crinkle::RenderContext.new(env, Crinkle::Renderer.new(env), Hash(String, Crinkle::Value).new)
      test_value = Crinkle.value("Hello World, this is a long text")
      test_args = [Crinkle.value(10)] of Crinkle::Value
      test_kwargs = Hash(String, Crinkle::Value).new

      # Manual implementation should work
      manual_filter = env.filters["typed_truncate_manual"]
      manual_result = manual_filter.call(test_value, test_args, test_kwargs, ctx)
      manual_result.to_s.should eq("Hello Worl...")

      # Macro-generated filter should also work
      typed_filter = env.filters["typed_truncate"]
      typed_result = typed_filter.call(test_value, test_args, test_kwargs, ctx)
      typed_result.to_s.should eq("Hello Worl...")
    end
  end

  describe "define_test" do
    it "registers test schema in global registry" do
      Crinkle::Schema.registry.tests.has_key?("typed_even").should be_true
      schema = Crinkle::Schema.registry.tests["typed_even"]
      schema.doc.should eq("Check if number is even")
    end

    it "creates working test" do
      env = Crinkle::Environment.new(load_std: false)
      TestTypedTests.register(env)

      source = "{% if n is typed_even %}even{% else %}odd{% endif %}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      renderer = Crinkle::Renderer.new(env)

      context_even = {"n" => 4_i64} of String => Crinkle::Value
      renderer.render(template, context_even).should eq("even")

      context_odd = {"n" => 3_i64} of String => Crinkle::Value
      renderer.render(template, context_odd).should eq("odd")
    end
  end

  describe "define_function" do
    it "registers function schema in global registry" do
      Crinkle::Schema.registry.functions.has_key?("typed_greet").should be_true
      schema = Crinkle::Schema.registry.functions["typed_greet"]
      schema.doc.should eq("Create a greeting")
      schema.params.size.should eq(2)
    end

    it "creates working function with defaults" do
      env = Crinkle::Environment.new(load_std: false)
      TestTypedFunctions.register(env)

      source = "{{ typed_greet(\"World\") }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      context = Hash(String, Crinkle::Value).new
      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("Hello, World!")
    end

    it "creates function with custom parameters" do
      env = Crinkle::Environment.new(load_std: false)
      TestTypedFunctions.register(env)

      source = "{{ typed_greet(\"World\", greeting=\"Hi\") }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      context = Hash(String, Crinkle::Value).new
      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("Hi, World!")
    end
  end

  describe "Callable with annotations" do
    it "generates callable schema" do
      schema = TestFormatter.callable_schema
      schema.class_name.should eq("TestFormatter")
      schema.methods.has_key?("price").should be_true
      schema.methods.has_key?("date").should be_true
      schema.default_call.should_not be_nil
    end

    it "has correct method schema" do
      schema = TestFormatter.callable_schema
      price_schema = schema.methods["price"]
      price_schema.params.size.should eq(2)
      price_schema.params[0].name.should eq("value")
      price_schema.params[1].name.should eq("currency")
      price_schema.params[1].default.should eq("\"USD\"")
      price_schema.doc.should eq("Format a number as currency")
    end

    it "has default call schema" do
      schema = TestFormatter.callable_schema
      schema.default_call.should_not be_nil
      dc = schema.default_call.as(Crinkle::Schema::MethodSchema)
      dc.params.size.should eq(1)
      dc.params[0].name.should eq("value")
      dc.doc.should eq("Default format")
    end

    it "generates jinja_call dispatch" do
      formatter = TestFormatter.new
      price_proc = formatter.jinja_call("price")
      price_proc.should_not be_nil

      date_proc = formatter.jinja_call("date")
      date_proc.should_not be_nil

      unknown_proc = formatter.jinja_call("unknown")
      unknown_proc.should be_nil
    end

    it "callable works in template" do
      env = Crinkle::Environment.new
      context = Hash(String, Crinkle::Value).new
      context["fmt"] = TestFormatter.new

      source = "{{ fmt.price(100) }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("100.00 USD")
    end

    it "callable with kwargs works in template" do
      env = Crinkle::Environment.new
      context = Hash(String, Crinkle::Value).new
      context["fmt"] = TestFormatter.new

      source = "{{ fmt.price(42, currency=\"EUR\") }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("42.00 EUR")
    end
  end

  describe "register_callable macro" do
    it "registers callable schema in global registry" do
      Crinkle.register_callable(TestFormatter)
      Crinkle::Schema.registry.callables.has_key?("TestFormatter").should be_true
      schema = Crinkle::Schema.registry.callables["TestFormatter"]
      schema.methods.has_key?("price").should be_true
    end
  end
end
