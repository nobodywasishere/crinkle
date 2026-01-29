module Jinja
  alias Value = (String | Int64 | Float64 | Bool | Array(Value) | Hash(String, Value))?

  alias FilterProc = Proc(Value, Array(Value), Hash(String, Value), Value)
  alias TestProc = Proc(Value, Array(Value), Hash(String, Value), Bool)
  alias FunctionProc = Proc(Array(Value), Hash(String, Value), Value)

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
    getter template_loader : TemplateLoader?

    def initialize(@override_builtins : Bool = false) : Nil
      @tag_extensions = Hash(String, TagExtension).new
      @filters = Hash(String, FilterProc).new
      @tests = Hash(String, TestProc).new
      @functions = Hash(String, FunctionProc).new
      @template_loader = nil
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
  end
end
