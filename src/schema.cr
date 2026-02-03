require "json"

module Crinkle
  module Schema
    VERSION = 1

    # Represents a parameter in a filter, test, function, or callable method
    struct ParamSchema
      include JSON::Serializable

      getter name : String
      getter type : String
      getter? required : Bool
      getter default : String?
      getter? variadic : Bool

      def initialize(
        @name : String,
        @type : String,
        @required : Bool = true,
        @default : String? = nil,
        @variadic : Bool = false,
      ) : Nil
      end
    end

    # Schema for a filter
    struct FilterSchema
      include JSON::Serializable

      getter name : String
      getter params : Array(ParamSchema)
      getter returns : String
      getter doc : String?
      getter? deprecated : Bool
      getter examples : Array(ExampleSchema)

      def initialize(
        @name : String,
        @params : Array(ParamSchema) = Array(ParamSchema).new,
        @returns : String = "Any",
        @doc : String? = nil,
        @deprecated : Bool = false,
        @examples : Array(ExampleSchema) = Array(ExampleSchema).new,
      ) : Nil
      end
    end

    # Schema for a test
    struct TestSchema
      include JSON::Serializable

      getter name : String
      getter params : Array(ParamSchema)
      getter doc : String?
      getter? deprecated : Bool

      def initialize(
        @name : String,
        @params : Array(ParamSchema) = Array(ParamSchema).new,
        @doc : String? = nil,
        @deprecated : Bool = false,
      ) : Nil
      end
    end

    # Schema for a function
    struct FunctionSchema
      include JSON::Serializable

      getter name : String
      getter params : Array(ParamSchema)
      getter returns : String
      getter doc : String?
      getter? deprecated : Bool

      def initialize(
        @name : String,
        @params : Array(ParamSchema) = Array(ParamSchema).new,
        @returns : String = "Any",
        @doc : String? = nil,
        @deprecated : Bool = false,
      ) : Nil
      end
    end

    # Schema for a method on a callable object
    struct MethodSchema
      include JSON::Serializable

      getter name : String
      getter params : Array(ParamSchema)
      getter returns : String
      getter doc : String?

      def initialize(
        @name : String,
        @params : Array(ParamSchema) = Array(ParamSchema).new,
        @returns : String = "Any",
        @doc : String? = nil,
      ) : Nil
      end
    end

    # Schema for a callable object (has methods that can be invoked from templates)
    struct CallableSchema
      include JSON::Serializable

      getter class_name : String
      getter default_call : MethodSchema?
      getter methods : Hash(String, MethodSchema)
      getter doc : String?

      def initialize(
        @class_name : String,
        @default_call : MethodSchema? = nil,
        @methods : Hash(String, MethodSchema) = Hash(String, MethodSchema).new,
        @doc : String? = nil,
      ) : Nil
      end
    end

    # Schema for template context
    struct TemplateContextSchema
      include JSON::Serializable

      getter path : String
      getter context : Hash(String, String)

      def initialize(
        @path : String,
        @context : Hash(String, String) = Hash(String, String).new,
      ) : Nil
      end
    end

    # Example for documentation
    struct ExampleSchema
      include JSON::Serializable

      getter input : String
      getter output : String

      def initialize(@input : String, @output : String) : Nil
      end
    end

    # Schema for a custom tag
    struct TagSchema
      include JSON::Serializable

      getter name : String
      getter doc : String?
      getter? has_body : Bool
      getter end_tag : String?

      def initialize(
        @name : String,
        @doc : String? = nil,
        @has_body : Bool = false,
        @end_tag : String? = nil,
      ) : Nil
      end
    end

    # The full schema containing all registered items
    class Registry
      include JSON::Serializable

      @[JSON::Field(key: "version")]
      getter version : Int32 = VERSION

      getter filters : Hash(String, FilterSchema)
      getter tests : Hash(String, TestSchema)
      getter functions : Hash(String, FunctionSchema)
      getter callables : Hash(String, CallableSchema)
      getter templates : Hash(String, TemplateContextSchema)
      getter tags : Hash(String, TagSchema)

      def initialize : Nil
        @filters = Hash(String, FilterSchema).new
        @tests = Hash(String, TestSchema).new
        @functions = Hash(String, FunctionSchema).new
        @callables = Hash(String, CallableSchema).new
        @templates = Hash(String, TemplateContextSchema).new
        @tags = Hash(String, TagSchema).new
      end

      def register_filter(schema : FilterSchema) : Nil
        @filters[schema.name] = schema
      end

      def register_test(schema : TestSchema) : Nil
        @tests[schema.name] = schema
      end

      def register_function(schema : FunctionSchema) : Nil
        @functions[schema.name] = schema
      end

      def register_callable(schema : CallableSchema) : Nil
        @callables[schema.class_name] = schema
      end

      def register_template(schema : TemplateContextSchema) : Nil
        @templates[schema.path] = schema
      end

      def register_tag(schema : TagSchema) : Nil
        @tags[schema.name] = schema
      end
    end

    # Global registry instance - populated at compile time by macros
    class_getter registry : Registry = Registry.new

    # Export schema as JSON
    def self.to_json : String
      String.build do |str|
        JSON.build(str) do |json|
          registry.to_json(json)
        end
      end
    end

    def self.to_pretty_json : String
      String.build do |str|
        JSON.build(str, indent: 2) do |json|
          registry.to_json(json)
        end
      end
    end
  end
end
