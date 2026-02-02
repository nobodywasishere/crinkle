require "./schema"

module Crinkle
  # Macros for defining filters, tests, functions, and callable methods with type metadata.
  # These generate both runtime registration and compile-time schema for tooling.

  # Define a filter with typed parameters and schema metadata.
  #
  # Usage:
  # ```
  # Crinkle.define_filter :truncate,
  #   params: {value: String, length: Int32},
  #   defaults: {length: 80},
  #   returns: String,
  #   doc: "Truncate string to length" do |env, value, length|
  #   value.size > length ? value[0...length] + "..." : value
  # end
  # ```
  #
  # The macro generates:
  # 1. A method that registers the filter with an Environment
  # 2. Schema metadata added to the global registry
  macro define_filter(name, params = nil, defaults = nil, returns = nil, doc = nil, deprecated = false, examples = nil, &block)
    {% filter_name = name.is_a?(SymbolLiteral) ? name.id.stringify : name %}

    # Build schema at compile time
    {% param_schemas = [] of Nil %}
    {% if params %}
      {% for key, type in params %}
        {% default_value = defaults && defaults[key] %}
        {% required = !default_value %}
        {% param_schemas << {name: key.id.stringify, type: type.id.stringify, required: required, default: default_value ? default_value.stringify : nil} %}
      {% end %}
    {% end %}

    # Register schema at load time
    ::Crinkle::Schema.registry.register_filter(
      ::Crinkle::Schema::FilterSchema.new(
        name: {{ filter_name }},
        params: [
          {% for p in param_schemas %}
            ::Crinkle::Schema::ParamSchema.new(
              name: {{ p[:name] }},
              type: {{ p[:type] }},
              required: {{ p[:required] }},
              default: {{ p[:default] }},
            ),
          {% end %}
        ],
        returns: {{ returns ? returns.id.stringify : "Any" }},
        doc: {{ doc }},
        deprecated: {{ deprecated }},
        examples: {% if examples %}[
          {% for ex in examples %}
            ::Crinkle::Schema::ExampleSchema.new(
              input: {{ ex[:input] }},
              output: {{ ex[:output] }},
            ),
          {% end %}
        ]{% else %}[] of ::Crinkle::Schema::ExampleSchema{% end %},
      )
    )

    # Define the registration method
    def self.__register_filter_{{ name.id }}(env : ::Crinkle::Environment) : Nil
      {% if params %}
        # Typed filter with parameter extraction
        env.register_filter({{ filter_name }}) do |value, args, kwargs, ctx|
          {% param_names = [] of Nil %}
          {% for key, type in params %}
            {% param_names << key %}
          {% end %}

          # Extract parameters
          {% i = 0 %}
          {% for key, type in params %}
            {% default_value = defaults && defaults[key] %}
            {% is_first = i == 0 %}
            {% if is_first %}
              # First param is the filter value
              __param_{{ key.id }} = value
            {% else %}
              # Subsequent params from args/kwargs
              {% arg_index = i - 1 %}
              __raw_{{ key.id }} = kwargs[{{ key.id.stringify }}]? || args[{{ arg_index }}]?
              {% if default_value %}
                __param_{{ key.id }} = __raw_{{ key.id }} || ::Crinkle.value({{ default_value }})
              {% else %}
                __param_{{ key.id }} = __raw_{{ key.id }} || ::Crinkle::Undefined.new({{ key.id.stringify }})
              {% end %}
            {% end %}
            {% i = i + 1 %}
          {% end %}

          # Call the block with extracted parameters
          __result = begin
            {{ yield }}
          end
          ::Crinkle.value(__result)
        end
      {% else %}
        # Simple filter without typed parameters
        env.register_filter({{ filter_name }}) do |value, args, kwargs, ctx|
          __result = begin
            {{ yield }}
          end
          ::Crinkle.value(__result)
        end
      {% end %}
    end
  end

  # Define a test with typed parameters and schema metadata.
  #
  # Usage:
  # ```
  # Crinkle.define_test :divisible_by,
  #   params: {value: Number, divisor: Number},
  #   doc: "Check if value is divisible by divisor" do |env, value, divisor|
  #   (value.to_i % divisor.to_i) == 0
  # end
  # ```
  macro define_test(name, params = nil, defaults = nil, doc = nil, deprecated = false, &block)
    {% test_name = name.is_a?(SymbolLiteral) ? name.id.stringify : name %}

    # Build schema at compile time
    {% param_schemas = [] of Nil %}
    {% if params %}
      {% for key, type in params %}
        {% default_value = defaults && defaults[key] %}
        {% required = !default_value %}
        {% param_schemas << {name: key.id.stringify, type: type.id.stringify, required: required, default: default_value ? default_value.stringify : nil} %}
      {% end %}
    {% end %}

    # Register schema at load time
    ::Crinkle::Schema.registry.register_test(
      ::Crinkle::Schema::TestSchema.new(
        name: {{ test_name }},
        params: [
          {% for p in param_schemas %}
            ::Crinkle::Schema::ParamSchema.new(
              name: {{ p[:name] }},
              type: {{ p[:type] }},
              required: {{ p[:required] }},
              default: {{ p[:default] }},
            ),
          {% end %}
        ],
        doc: {{ doc }},
        deprecated: {{ deprecated }},
      )
    )

    # Define the registration method
    def self.__register_test_{{ name.id }}(env : ::Crinkle::Environment) : Nil
      {% if params %}
        # Typed test with parameter extraction
        env.register_test({{ test_name }}) do |value, args, kwargs, ctx|
          {% param_names = [] of Nil %}
          {% for key, type in params %}
            {% param_names << key %}
          {% end %}

          # Extract parameters
          {% i = 0 %}
          {% for key, type in params %}
            {% default_value = defaults && defaults[key] %}
            {% is_first = i == 0 %}
            {% if is_first %}
              # First param is the test value
              __param_{{ key.id }} = value
            {% else %}
              # Subsequent params from args/kwargs
              {% arg_index = i - 1 %}
              __raw_{{ key.id }} = kwargs[{{ key.id.stringify }}]? || args[{{ arg_index }}]?
              {% if default_value %}
                __param_{{ key.id }} = __raw_{{ key.id }} || ::Crinkle.value({{ default_value }})
              {% else %}
                __param_{{ key.id }} = __raw_{{ key.id }} || ::Crinkle::Undefined.new({{ key.id.stringify }})
              {% end %}
            {% end %}
            {% i = i + 1 %}
          {% end %}

          # Call the block with extracted parameters - must return Bool
          __result = begin
            {{ yield }}
          end
          __result.is_a?(Bool) ? __result : !!__result
        end
      {% else %}
        # Simple test without typed parameters
        env.register_test({{ test_name }}) do |value, args, kwargs, ctx|
          __result = begin
            {{ yield }}
          end
          __result.is_a?(Bool) ? __result : !!__result
        end
      {% end %}
    end
  end

  # Define a function with typed parameters and schema metadata.
  #
  # Usage:
  # ```
  # Crinkle.define_function :range,
  #   params: {start: Int32, stop: Int32, step: Int32},
  #   defaults: {step: 1},
  #   returns: Array,
  #   doc: "Create a range of numbers" do |env, start, stop, step|
  #   (start.to_i...stop.to_i).step(step.to_i).to_a
  # end
  # ```
  macro define_function(name, params = nil, defaults = nil, returns = nil, doc = nil, deprecated = false, &block)
    {% func_name = name.is_a?(SymbolLiteral) ? name.id.stringify : name %}

    # Build schema at compile time
    {% param_schemas = [] of Nil %}
    {% if params %}
      {% for key, type in params %}
        {% default_value = defaults && defaults[key] %}
        {% required = !default_value %}
        {% param_schemas << {name: key.id.stringify, type: type.id.stringify, required: required, default: default_value ? default_value.stringify : nil} %}
      {% end %}
    {% end %}

    # Register schema at load time
    ::Crinkle::Schema.registry.register_function(
      ::Crinkle::Schema::FunctionSchema.new(
        name: {{ func_name }},
        params: [
          {% for p in param_schemas %}
            ::Crinkle::Schema::ParamSchema.new(
              name: {{ p[:name] }},
              type: {{ p[:type] }},
              required: {{ p[:required] }},
              default: {{ p[:default] }},
            ),
          {% end %}
        ],
        returns: {{ returns ? returns.id.stringify : "Any" }},
        doc: {{ doc }},
        deprecated: {{ deprecated }},
      )
    )

    # Define the registration method
    def self.__register_function_{{ name.id }}(env : ::Crinkle::Environment) : Nil
      {% if params %}
        # Typed function with parameter extraction
        env.register_function({{ func_name }}) do |args, kwargs, ctx|
          # Extract parameters
          {% i = 0 %}
          {% for key, type in params %}
            {% default_value = defaults && defaults[key] %}
            __raw_{{ key.id }} = kwargs[{{ key.id.stringify }}]? || args[{{ i }}]?
            {% if default_value %}
              __param_{{ key.id }} = __raw_{{ key.id }} || ::Crinkle.value({{ default_value }})
            {% else %}
              __param_{{ key.id }} = __raw_{{ key.id }} || ::Crinkle::Undefined.new({{ key.id.stringify }})
            {% end %}
            {% i = i + 1 %}
          {% end %}

          # Call the block with extracted parameters
          __result = begin
            {{ yield }}
          end
          ::Crinkle.value(__result)
        end
      {% else %}
        # Simple function without typed parameters
        env.register_function({{ func_name }}) do |args, kwargs, ctx|
          __result = begin
            {{ yield }}
          end
          ::Crinkle.value(__result)
        end
      {% end %}
    end
  end

  # Annotation for marking methods as callable from templates
  annotation Method
  end

  # Annotation for the default call method
  annotation DefaultCall
  end

  # Module to include for objects with callable methods
  module Callable
    include Object

    # Macro to define a callable method on a class
    #
    # Usage inside a class:
    # ```
    # class Formatter
    #   include Crinkle::Callable
    #
    #   @[Crinkle::Method(
    #     params: {value: Number, currency: String},
    #     defaults: {currency: "USD"},
    #     returns: String,
    #     doc: "Format as currency"
    #   )]
    #   def price(args : Crinkle::Arguments) : String
    #     ...
    #   end
    # end
    # ```
    macro included
      macro finished
        {% verbatim do %}
          # Generate jinja_call dispatch from @[Crinkle::Method] annotated methods
          def jinja_call(method_name : String) : ::Crinkle::CallableProc?
            {% methods = [] of Nil %}
            {% for method in @type.methods %}
              {% ann = method.annotation(::Crinkle::Method) %}
              {% if ann %}
                {% methods << {name: (ann[:name] || method.name).id.stringify, method: method.name} %}
              {% end %}
            {% end %}

            {% if !methods.empty? %}
              case method_name
              {% for m in methods %}
              when {{ m[:name] }}
                ->(args : ::Crinkle::Arguments) : ::Crinkle::Value {
                  ::Crinkle.value(self.{{ m[:method].id }}(args))
                }
              {% end %}
              else
                nil
              end
            {% else %}
              nil
            {% end %}
          end

          # Generate __crinkle_callable_schema class method
          def self.__crinkle_callable_schema : ::Crinkle::Schema::CallableSchema
            methods_hash = {} of String => ::Crinkle::Schema::MethodSchema

            {% for method in @type.methods %}
              {% ann = method.annotation(::Crinkle::Method) %}
              {% if ann %}
                {% method_name = (ann[:name] || method.name).id.stringify %}
                {% params_def = ann[:params] %}
                {% defaults_def = ann[:defaults] %}
                {% returns_def = ann[:returns] %}
                {% doc_def = ann[:doc] %}

                methods_hash[{{ method_name }}] = ::Crinkle::Schema::MethodSchema.new(
                  name: {{ method_name }},
                  params: [
                    {% if params_def %}
                      {% for key, type in params_def %}
                        {% default_value = defaults_def && defaults_def[key] %}
                        {% required = !default_value %}
                        ::Crinkle::Schema::ParamSchema.new(
                          name: {{ key.id.stringify }},
                          type: {{ type.id.stringify }},
                          required: {{ required }},
                          default: {{ default_value ? default_value.stringify : nil }},
                        ),
                      {% end %}
                    {% end %}
                  ],
                  returns: {{ returns_def ? returns_def.id.stringify : "Any" }},
                  doc: {{ doc_def }},
                )
              {% end %}
            {% end %}

            {% default_call_method = nil %}
            {% for method in @type.methods %}
              {% dc_ann = method.annotation(::Crinkle::DefaultCall) %}
              {% if dc_ann %}
                {% default_call_method = {params: dc_ann[:params], defaults: dc_ann[:defaults], returns: dc_ann[:returns], doc: dc_ann[:doc]} %}
              {% end %}
            {% end %}

            default_call_schema = {% if default_call_method %}
              ::Crinkle::Schema::MethodSchema.new(
                name: "__call__",
                params: [
                  {% if default_call_method[:params] %}
                    {% for key, type in default_call_method[:params] %}
                      {% default_value = default_call_method[:defaults] && default_call_method[:defaults][key] %}
                      {% required = !default_value %}
                      ::Crinkle::Schema::ParamSchema.new(
                        name: {{ key.id.stringify }},
                        type: {{ type.id.stringify }},
                        required: {{ required }},
                        default: {{ default_value ? default_value.stringify : nil }},
                      ),
                    {% end %}
                  {% end %}
                ],
                returns: {{ default_call_method[:returns] ? default_call_method[:returns].id.stringify : "Any" }},
                doc: {{ default_call_method[:doc] }},
              )
            {% else %}
              nil
            {% end %}

            ::Crinkle::Schema::CallableSchema.new(
              class_name: {{ @type.name.stringify }},
              default_call: default_call_schema,
              methods: methods_hash,
            )
          end
        {% end %}
      end
    end
  end

  # Helper to register a callable's schema with the global registry
  macro register_callable(klass)
    ::Crinkle::Schema.registry.register_callable({{ klass }}.__crinkle_callable_schema)
  end
end
