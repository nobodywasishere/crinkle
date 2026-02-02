module Crinkle
  alias FilterProc = Proc(Value, Array(Value), Hash(String, Value), RenderContext, Span, Value)
  alias TestProc = Proc(Value, Array(Value), Hash(String, Value), RenderContext, Span, Bool)
  alias FunctionProc = Proc(Array(Value), Hash(String, Value), RenderContext, Span, Value)

  alias TagHandler = Proc(Parser, Span, AST::Node?)
  alias TemplateLoader = Proc(String, String?)

  class TagExtension
    getter name : String
    getter handler : TagHandler
    getter end_tags : Array(String)
    getter? override : Bool

    def initialize(
      @name : String,
      @handler : TagHandler,
      @end_tags : Array(String),
      @override : Bool,
    ) : Nil
    end
  end

  class Environment
    getter tag_extensions : Hash(String, TagExtension)
    getter filters : Hash(String, FilterProc)
    getter tests : Hash(String, TestProc)
    getter functions : Hash(String, FunctionProc)
    getter? override_builtins : Bool
    property template_loader : TemplateLoader?
    getter? strict_undefined : Bool
    getter? strict_filters : Bool
    getter? strict_tests : Bool
    getter? strict_functions : Bool
    getter parent : Environment?
    getter globals : Hash(String, Value)

    def initialize(
      @override_builtins : Bool = false,
      @strict_undefined : Bool = true,
      @strict_filters : Bool = true,
      @strict_tests : Bool = true,
      @strict_functions : Bool = true,
      load_std : Bool = true,
      @parent : Environment? = nil,
    ) : Nil
      @tag_extensions = Hash(String, TagExtension).new
      @filters = Hash(String, FilterProc).new
      @tests = Hash(String, TestProc).new
      @functions = Hash(String, FunctionProc).new
      @globals = Hash(String, Value).new
      @template_loader = nil

      Std.load_all(self) if load_std
    end

    # Create a child environment that inherits from this one.
    # The child inherits filters, tests, functions, and the template loader.
    def new_child : Environment
      child = Environment.new(
        parent: self,
        override_builtins: @override_builtins,
        strict_undefined: @strict_undefined,
        strict_filters: @strict_filters,
        strict_tests: @strict_tests,
        strict_functions: @strict_functions,
        load_std: false,
      )
      child.filters.merge!(@filters)
      child.tests.merge!(@tests)
      child.functions.merge!(@functions)
      child.tag_extensions.merge!(@tag_extensions)
      child.template_loader = @template_loader
      child
    end

    # Look up a global variable, checking parent chain if not found locally.
    def global(name : String) : Value
      @globals[name]? || @parent.try(&.global(name)) || Undefined.new(name)
    end

    # Check if a global variable is defined in this environment or parent chain.
    def has_global?(name : String) : Bool
      @globals.has_key?(name) || (@parent.try(&.has_global?(name)) || false)
    end

    def register_tag(
      name : String,
      handler : TagHandler,
      end_tags : Array(String) = Array(String).new,
      override : Bool = false,
    ) : Nil
      @tag_extensions[name] = TagExtension.new(name, handler, end_tags, override)
    end

    def register_tag(
      name : String,
      end_tags : Array(String) = Array(String).new,
      override : Bool = false,
      &handler : TagHandler
    ) : Nil
      register_tag(name, handler, end_tags, override)
    end

    def register_filter(name : String, filter : FilterProc) : Nil
      @filters[name] = filter
    end

    def register_filter(name : String, &filter : FilterProc) : Nil
      register_filter(name, filter)
    end

    def register_test(name : String, test : TestProc) : Nil
      @tests[name] = test
    end

    def register_test(name : String, &test : TestProc) : Nil
      register_test(name, test)
    end

    def register_function(name : String, fn : FunctionProc) : Nil
      @functions[name] = fn
    end

    def register_function(name : String, &fn : FunctionProc) : Nil
      register_function(name, fn)
    end

    def set_loader(&loader : TemplateLoader) : Nil
      @template_loader = loader
    end

    def tag_extension(name : String) : TagExtension?
      @tag_extensions[name]?
    end

    def get_template(name : String) : Template
      source = load_template_source(name)
      parse_template(source, name)
    end

    def from_string(source : String, name : String? = nil) : Template
      parse_template(source, name || "<string>")
    end

    def render(template_name : String, context : Hash(String, Value) = Hash(String, Value).new) : String
      get_template(template_name).render(context)
    end

    def render(template_name : String, **variables) : String
      context = Hash(String, Value).new
      variables.each do |key, value|
        context[key.to_s] = Crinkle.value(value)
      end
      render(template_name, context)
    end

    private def load_template_source(name : String) : String
      if loader = @template_loader
        if source = loader.call(name)
          return source
        end
      end
      raise TemplateNotFoundError.new(name)
    end

    private def parse_template(source : String, name : String) : Template
      lexer = Lexer.new(source)
      tokens = lexer.lex_all
      parser = Parser.new(tokens, self)
      ast = parser.parse
      Template.new(source, ast, name, name, self)
    end
  end
end
