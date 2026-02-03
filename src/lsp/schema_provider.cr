module Crinkle::LSP
  # Provides access to schema data for LSP semantic features.
  # Uses the built-in standard library schema by default, with optional
  # override from a custom schema file for projects with custom extensions.
  class SchemaProvider
    getter custom_schema : Schema::Registry?
    @config : Config
    @root_path : String

    def initialize(@config : Config, @root_path : String) : Nil
      @custom_schema = load_custom_schema
    end

    # Load custom schema from file if it exists
    private def load_custom_schema : Schema::Registry?
      schema_path = File.join(@root_path, @config.schema.path)

      return unless File.exists?(schema_path)

      begin
        json_content = File.read(schema_path)
        Schema::Registry.from_json(json_content)
      rescue
        # Return nil if schema can't be loaded - will fall back to built-in
        nil
      end
    end

    # Reload custom schema from disk
    def reload : Nil
      @custom_schema = load_custom_schema
    end

    # Get the effective schema (custom if available, otherwise built-in)
    private def schema : Schema::Registry
      @custom_schema || Schema.registry
    end

    # Get all filters with their schemas
    def filters : Hash(String, Schema::FilterSchema)
      schema.filters
    end

    # Get all tests with their schemas
    def tests : Hash(String, Schema::TestSchema)
      schema.tests
    end

    # Get all functions with their schemas
    def functions : Hash(String, Schema::FunctionSchema)
      schema.functions
    end

    # Get all callables with their schemas
    def callables : Hash(String, Schema::CallableSchema)
      schema.callables
    end

    # Get all custom tags with their schemas
    def tags : Hash(String, Schema::TagSchema)
      schema.tags
    end

    # Get template context schema
    def template_context(path : String) : Hash(String, String)?
      schema.templates[path]?.try(&.context)
    end

    # Get a specific filter schema by name
    def filter(name : String) : Schema::FilterSchema?
      filters[name]?
    end

    # Get a specific test schema by name
    def test(name : String) : Schema::TestSchema?
      tests[name]?
    end

    # Get a specific function schema by name
    def function(name : String) : Schema::FunctionSchema?
      functions[name]?
    end

    # Get a specific callable schema by class name
    def callable(class_name : String) : Schema::CallableSchema?
      callables[class_name]?
    end

    # Check if schema is loaded
    def loaded? : Bool
      !@schema.nil?
    end

    # Build a signature string for a filter (includes piped value as first param)
    def filter_signature(filter : Schema::FilterSchema) : String
      params = filter.params.map do |param|
        param_str = "#{param.name}: #{param.type}"
        param_str += " = #{param.default}" if param.default
        param_str
      end.join(", ")
      "#{filter.name}(#{params}) -> #{filter.returns}"
    end

    # Build a signature string for filter arguments only (excludes piped value)
    # Used for completions and signature help where the first param is implicit
    def filter_args_signature(filter : Schema::FilterSchema) : String
      # Skip the first parameter (the piped value)
      args = filter.params.skip(1)
      if args.empty?
        "#{filter.name} -> #{filter.returns}"
      else
        params = args.map do |param|
          param_str = "#{param.name}: #{param.type}"
          param_str += " = #{param.default}" if param.default
          param_str
        end.join(", ")
        "#{filter.name}(#{params}) -> #{filter.returns}"
      end
    end

    # Build a signature string for a test (includes tested value as first param)
    def test_signature(test : Schema::TestSchema) : String
      params = test.params.map do |param|
        param_str = "#{param.name}: #{param.type}"
        param_str += " = #{param.default}" if param.default
        param_str
      end.join(", ")
      "#{test.name}(#{params})"
    end

    # Build a signature string for test arguments only (excludes tested value)
    # Used for completions where the first param is implicit via `is`
    def test_args_signature(test : Schema::TestSchema) : String
      # Skip the first parameter (the tested value)
      args = test.params.skip(1)
      if args.empty?
        test.name
      else
        params = args.map do |param|
          param_str = "#{param.name}: #{param.type}"
          param_str += " = #{param.default}" if param.default
          param_str
        end.join(", ")
        "#{test.name}(#{params})"
      end
    end

    # Build a signature string for a function
    def function_signature(func : Schema::FunctionSchema) : String
      params = func.params.map do |param|
        param_str = "#{param.name}: #{param.type}"
        param_str += " = #{param.default}" if param.default
        param_str
      end.join(", ")
      "#{func.name}(#{params}) -> #{func.returns}"
    end

    # Build a signature string for a method
    def method_signature(method : Schema::MethodSchema) : String
      params = method.params.map do |param|
        param_str = "#{param.name}: #{param.type}"
        param_str += " = #{param.default}" if param.default
        param_str
      end.join(", ")
      "#{method.name}(#{params}) -> #{method.returns}"
    end
  end
end
