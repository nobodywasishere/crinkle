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
    getter? strict_undefined : Bool
    getter? strict_filters : Bool
    getter? strict_tests : Bool
    getter? strict_functions : Bool

    def initialize(
      @override_builtins : Bool = false,
      @strict_undefined : Bool = true,
      @strict_filters : Bool = true,
      @strict_tests : Bool = true,
      @strict_functions : Bool = true,
    ) : Nil
      @tag_extensions = Hash(String, TagExtension).new
      @filters = Hash(String, FilterProc).new
      @tests = Hash(String, TestProc).new
      @functions = Hash(String, FunctionProc).new
      @template_loader = nil
      register_builtin_filters_tests
    end

    private def register_builtin_filters_tests : Nil
      unless @filters.has_key?("upper")
        @filters["upper"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
          value.to_s.upcase
        end
      end

      unless @filters.has_key?("lower")
        @filters["lower"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
          value.to_s.downcase
        end
      end

      unless @filters.has_key?("length")
        @filters["length"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
          case value
          when String
            value.size.to_i64
          when Array(Value)
            value.size.to_i64
          when Hash(String, Value)
            value.size.to_i64
          else
            0_i64
          end
        end
      end

      unless @filters.has_key?("default")
        @filters["default"] = ->(value : Value, args : Array(Value), _kwargs : Hash(String, Value)) : Value do
          fallback = args.first? || ""
          empty = case value
                  when Nil
                    true
                  when String
                    value.empty?
                  when Array(Value)
                    value.empty?
                  when Hash(String, Value)
                    value.empty?
                  else
                    false
                  end
          empty ? fallback : value
        end
      end

      unless @filters.has_key?("escape")
        @filters["escape"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
          value.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub("\"", "&quot;")
            .gsub("'", "&#39;")
        end
      end

      unless @tests.has_key?("lower")
        @tests["lower"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Bool do
          str = value.to_s
          !str.empty? && str == str.downcase
        end
      end

      unless @tests.has_key?("upper")
        @tests["upper"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Bool do
          str = value.to_s
          !str.empty? && str == str.upcase
        end
      end
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
