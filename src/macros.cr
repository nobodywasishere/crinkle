require "./schema"

module Crinkle
  PRIMITIVES = ["String", "Int64", "Float64", "Bool"]

  macro define_filter(name, params = nil, defaults = nil, returns = nil, doc = nil, deprecated = false, examples = nil, &block)
    {% filter_name = name.is_a?(SymbolLiteral) ? name.id.stringify : name %}

    ::Crinkle::Schema.registry.register_filter(::Crinkle::Schema::FilterSchema.new(
      name: {{ filter_name }},
      params: {% if params %}[
        {% for key, type in params %}
          {% has_default = defaults && defaults.keys.includes?(key) %}
          {% dv = defaults && defaults[key] %}
          ::Crinkle::Schema::ParamSchema.new(
            name: {{ key.id.stringify }},
            type: {{ type.id.stringify }},
            required: {{ !has_default }},
            default: {{ has_default ? (dv == nil ? nil : dv.stringify) : nil }}
          ),
        {% end %}
      ]{% else %}[] of ::Crinkle::Schema::ParamSchema{% end %},
      returns: {{ returns ? returns.id.stringify : "Value" }},
      doc: {{ doc }},
      deprecated: {{ deprecated }},
      examples: {% if examples %}[
        {% for ex in examples %}
          ::Crinkle::Schema::ExampleSchema.new(input: {{ ex[:input] }}, output: {{ ex[:output] }}),
        {% end %}
      ]{% else %}[] of ::Crinkle::Schema::ExampleSchema{% end %},
    ))

    def self.register_filter_{{ name.id }}(env : ::Crinkle::Environment) : Nil
      env.register_filter({{ filter_name }}) do |value, args, kwargs, ctx, span|
        {% if params %}
          {% primitives = ["String", "Int64", "Float64", "Bool"] %}
          %has_error = false

          {% i = 0 %}
          {% for key, type in params %}
            {% has_default = defaults && defaults.keys.includes?(key) %}
            {% dv = defaults && defaults[key] %}
            {% nullable = dv == nil && has_default %}

            {% if i == 0 %}
              %raw{key.id} = value
            {% else %}
              %raw{key.id} = kwargs[{{ key.id.stringify }}]? || args[{{ i - 1 }}]? || \
                {% if has_default %}::Crinkle.value({{ dv }}){% else %}::Crinkle::Undefined.new({{ key.id.stringify }}){% end %}
            {% end %}

            {% if type.id == "String".id %}
              %param{key.id} = {% if nullable %}%raw{key.id}.nil? ? nil : %raw{key.id}.to_s{% else %}%raw{key.id}.to_s{% end %}

            {% elsif type.id == "Int64".id || type.id == "Float64".id %}
              %param{key.id} = begin
                if %raw{key.id}.is_a?(::Crinkle::Undefined)
                  {% if has_default %}
                    {{ dv }}
                  {% else %}
                    ctx.add_diagnostic(::Crinkle::DiagnosticType::MissingArgument,
                      "Filter #{{{ filter_name }}}: '{{ key.id }}' is required", span)
                    %has_error = true
                    {{ type.id }}.zero
                  {% end %}
                {% if nullable %}
                elsif %raw{key.id}.nil?
                  nil
                {% end %}
                elsif (v = %raw{key.id}.as?({{ type.id }}))
                  v
                else
                  ctx.add_diagnostic(::Crinkle::DiagnosticType::TypeMismatch,
                    "Filter #{{{ filter_name }}}: '{{ key.id }}' expected {{ type.id }}, got #{%raw{key.id}.class}", span)
                  %has_error = true
                  {{ type.id }}.zero
                end
              end

            {% elsif type.id == "Bool".id %}
              %param{key.id} = begin
                if %raw{key.id}.is_a?(::Crinkle::Undefined)
                  {% if has_default %}
                    {{ dv }}
                  {% else %}
                    ctx.add_diagnostic(::Crinkle::DiagnosticType::MissingArgument,
                      "Filter #{{{ filter_name }}}: '{{ key.id }}' is required", span)
                    %has_error = true
                    false
                  {% end %}
                elsif %raw{key.id}.is_a?(Bool)
                  %raw{key.id}.as(Bool)
                else
                  ctx.add_diagnostic(::Crinkle::DiagnosticType::TypeMismatch,
                    "Filter #{{{ filter_name }}}: '{{ key.id }}' expected Bool, got #{%raw{key.id}.class}", span)
                  %has_error = true
                  false
                end
              end

            {% else %}
              %param{key.id} = %raw{key.id}
            {% end %}

            {% i = i + 1 %}
          {% end %}

          next value if %has_error
          %proc = ->({% i = 0 %}{% for key, type in params %}{% if i > 0 %}, {% end %}{{ key.id }} : {% nullable = defaults && defaults[key] == nil %}{% if primitives.includes?(type.id.stringify) %}{{ type.id }}{% if nullable %}?{% end %}{% else %}::Crinkle::Value{% end %}{% i = i + 1 %}{% end %}) { {{ yield }} }
          ::Crinkle.value(%proc.call({% i = 0 %}{% for key, _ in params %}{% if i > 0 %}, {% end %}%param{key.id}{% i = i + 1 %}{% end %}))
        {% else %}
          ::Crinkle.value({{ yield }})
        {% end %}
      end
    end
  end

  macro define_test(name, params = nil, defaults = nil, doc = nil, deprecated = false, &block)
    {% test_name = name.is_a?(SymbolLiteral) ? name.id.stringify : name %}

    ::Crinkle::Schema.registry.register_test(::Crinkle::Schema::TestSchema.new(
      name: {{ test_name }},
      params: {% if params %}[
        {% for key, type in params %}
          {% has_default = defaults && defaults.keys.includes?(key) %}
          {% dv = defaults && defaults[key] %}
          ::Crinkle::Schema::ParamSchema.new(
            name: {{ key.id.stringify }},
            type: {{ type.id.stringify }},
            required: {{ !has_default }},
            default: {{ has_default ? (dv == nil ? nil : dv.stringify) : nil }}
          ),
        {% end %}
      ]{% else %}[] of ::Crinkle::Schema::ParamSchema{% end %},
      doc: {{ doc }},
      deprecated: {{ deprecated }},
    ))

    def self.register_test_{{ name.id }}(env : ::Crinkle::Environment) : Nil
      env.register_test({{ test_name }}) do |value, args, kwargs, ctx, span|
        {% primitives = ["String", "Int64", "Float64", "Bool"] %}
        {% if params %}
          %has_error = false

          {% i = 0 %}
          {% for key, type in params %}
            {% has_default = defaults && defaults.keys.includes?(key) %}
            {% dv = defaults && defaults[key] %}
            {% nullable = dv == nil && has_default %}

            {% if i == 0 %}
              %raw{key.id} = value
            {% else %}
              %raw{key.id} = kwargs[{{ key.id.stringify }}]? || args[{{ i - 1 }}]? || \
                {% if has_default %}::Crinkle.value({{ dv }}){% else %}::Crinkle::Undefined.new({{ key.id.stringify }}){% end %}
            {% end %}

            {% if type.id == "String".id %}
              %param{key.id} = {% if nullable %}%raw{key.id}.nil? ? nil : %raw{key.id}.to_s{% else %}%raw{key.id}.to_s{% end %}

            {% elsif type.id == "Int64".id || type.id == "Float64".id %}
              %param{key.id} = begin
                if %raw{key.id}.is_a?(::Crinkle::Undefined)
                  {% if has_default %}
                    {{ dv }}
                  {% else %}
                    ctx.add_diagnostic(::Crinkle::DiagnosticType::MissingArgument,
                      "Test #{{{ test_name }}}: '{{ key.id }}' is required", span)
                    %has_error = true
                    {{ type.id }}.zero
                  {% end %}
                {% if nullable %}
                elsif %raw{key.id}.nil?
                  nil
                {% end %}
                elsif (v = %raw{key.id}.as?({{ type.id }}))
                  v
                else
                  ctx.add_diagnostic(::Crinkle::DiagnosticType::TypeMismatch,
                    "Test #{{{ test_name }}}: '{{ key.id }}' expected {{ type.id }}, got #{%raw{key.id}.class}", span)
                  %has_error = true
                  {{ type.id }}.zero
                end
              end

            {% elsif type.id == "Bool".id %}
              %param{key.id} = begin
                if %raw{key.id}.is_a?(::Crinkle::Undefined)
                  {% if has_default %}
                    {{ dv }}
                  {% else %}
                    ctx.add_diagnostic(::Crinkle::DiagnosticType::MissingArgument,
                      "Test #{{{ test_name }}}: '{{ key.id }}' is required", span)
                    %has_error = true
                    false
                  {% end %}
                elsif %raw{key.id}.is_a?(Bool)
                  %raw{key.id}.as(Bool)
                else
                  ctx.add_diagnostic(::Crinkle::DiagnosticType::TypeMismatch,
                    "Test #{{{ test_name }}}: '{{ key.id }}' expected Bool, got #{%raw{key.id}.class}", span)
                  %has_error = true
                  false
                end
              end

            {% else %}
              %param{key.id} = %raw{key.id}
            {% end %}

            {% i = i + 1 %}
          {% end %}

          next false if %has_error
          %proc = ->({% i = 0 %}{% for key, type in params %}{% if i > 0 %}, {% end %}{{ key.id }} : {% nullable = defaults && defaults[key] == nil %}{% if primitives.includes?(type.id.stringify) %}{{ type.id }}{% if nullable %}?{% end %}{% else %}::Crinkle::Value{% end %}{% i = i + 1 %}{% end %}) { {{ yield }} }
          %result = %proc.call({% i = 0 %}{% for key, _ in params %}{% if i > 0 %}, {% end %}%param{key.id}{% i = i + 1 %}{% end %})
        {% else %}
          %result = {{ yield }}
        {% end %}

        %result.is_a?(Bool) ? %result : !!%result
      end
    end
  end

  macro define_function(name, params = nil, defaults = nil, returns = nil, doc = nil, deprecated = false, &block)
    {% func_name = name.is_a?(SymbolLiteral) ? name.id.stringify : name %}

    ::Crinkle::Schema.registry.register_function(::Crinkle::Schema::FunctionSchema.new(
      name: {{ func_name }},
      params: {% if params %}[
        {% for key, type in params %}
          {% has_default = defaults && defaults.keys.includes?(key) %}
          {% dv = defaults && defaults[key] %}
          ::Crinkle::Schema::ParamSchema.new(
            name: {{ key.id.stringify }},
            type: {{ type.id.stringify }},
            required: {{ !has_default }},
            default: {{ has_default ? (dv == nil ? nil : dv.stringify) : nil }}
          ),
        {% end %}
      ]{% else %}[] of ::Crinkle::Schema::ParamSchema{% end %},
      returns: {{ returns ? returns.id.stringify : "Value" }},
      doc: {{ doc }},
      deprecated: {{ deprecated }},
    ))

    def self.register_function_{{ name.id }}(env : ::Crinkle::Environment) : Nil
      env.register_function({{ func_name }}) do |args, kwargs, ctx, span|
        {% if params %}
          {% primitives = ["String", "Int64", "Float64", "Bool"] %}
          %has_error = false

          {% i = 0 %}
          {% for key, type in params %}
            {% has_default = defaults && defaults.keys.includes?(key) %}
            {% dv = defaults && defaults[key] %}
            {% nullable = dv == nil && has_default %}

            %raw{key.id} = kwargs[{{ key.id.stringify }}]? || args[{{ i }}]? || \
              {% if has_default %}::Crinkle.value({{ dv }}){% else %}::Crinkle::Undefined.new({{ key.id.stringify }}){% end %}

            {% if type.id == "String".id %}
              %param{key.id} = {% if nullable %}%raw{key.id}.nil? ? nil : %raw{key.id}.to_s{% else %}%raw{key.id}.to_s{% end %}

            {% elsif type.id == "Int64".id || type.id == "Float64".id %}
              %param{key.id} = begin
                if %raw{key.id}.is_a?(::Crinkle::Undefined)
                  {% if has_default %}
                    {{ dv }}
                  {% else %}
                    ctx.add_diagnostic(::Crinkle::DiagnosticType::MissingArgument,
                      "Function #{{{ func_name }}}: '{{ key.id }}' is required", span)
                    %has_error = true
                    {{ type.id }}.zero
                  {% end %}
                {% if nullable %}
                elsif %raw{key.id}.nil?
                  nil
                {% end %}
                elsif (v = %raw{key.id}.as?({{ type.id }}))
                  v
                else
                  ctx.add_diagnostic(::Crinkle::DiagnosticType::TypeMismatch,
                    "Function #{{{ func_name }}}: '{{ key.id }}' expected {{ type.id }}, got #{%raw{key.id}.class}", span)
                  %has_error = true
                  {{ type.id }}.zero
                end
              end

            {% elsif type.id == "Bool".id %}
              %param{key.id} = begin
                if %raw{key.id}.is_a?(::Crinkle::Undefined)
                  {% if has_default %}
                    {{ dv }}
                  {% else %}
                    ctx.add_diagnostic(::Crinkle::DiagnosticType::MissingArgument,
                      "Function #{{{ func_name }}}: '{{ key.id }}' is required", span)
                    %has_error = true
                    false
                  {% end %}
                elsif %raw{key.id}.is_a?(Bool)
                  %raw{key.id}.as(Bool)
                else
                  ctx.add_diagnostic(::Crinkle::DiagnosticType::TypeMismatch,
                    "Function #{{{ func_name }}}: '{{ key.id }}' expected Bool, got #{%raw{key.id}.class}", span)
                  %has_error = true
                  false
                end
              end

            {% else %}
              %param{key.id} = %raw{key.id}
            {% end %}

            {% i = i + 1 %}
          {% end %}

          next ::Crinkle::Undefined.new({{ func_name }}) if %has_error
          %proc = ->({% i = 0 %}{% for key, type in params %}{% if i > 0 %}, {% end %}{{ key.id }} : {% nullable = defaults && defaults[key] == nil %}{% if primitives.includes?(type.id.stringify) %}{{ type.id }}{% if nullable %}?{% end %}{% else %}::Crinkle::Value{% end %}{% i = i + 1 %}{% end %}) { {{ yield }} }
          ::Crinkle.value(%proc.call({% i = 0 %}{% for key, _ in params %}{% if i > 0 %}, {% end %}%param{key.id}{% i = i + 1 %}{% end %}))
        {% else %}
          ::Crinkle.value({{ yield }})
        {% end %}
      end
    end
  end

  annotation Method
  end

  annotation DefaultCall
  end

  module Callable
    include Object

    macro included
      macro finished
        {% verbatim do %}
          def jinja_call(method_name : String) : ::Crinkle::CallableProc?
            {% methods = @type.methods.select(&.annotation(::Crinkle::Method)).map { |method| {name: (method.annotation(::Crinkle::Method)[:name] || method.name).id.stringify, method: method.name} } %}
            {% if !methods.empty? %}
              case method_name
              {% for m in methods %}when {{ m[:name] }} then ->(args : ::Crinkle::Arguments) : ::Crinkle::Value { ::Crinkle.value(self.{{ m[:method].id }}(args)) }
              {% end %}else nil
              end
            {% else %}nil{% end %}
          end

          def self.callable_schema : ::Crinkle::Schema::CallableSchema
            {% begin %}{% dc = @type.methods.find(&.annotation(::Crinkle::DefaultCall)) %}{% dc_ann = dc ? dc.annotation(::Crinkle::DefaultCall) : nil %}
            ::Crinkle::Schema::CallableSchema.new(
              class_name: {{ @type.name.stringify }},
              default_call: {% if dc_ann %}::Crinkle::Schema::MethodSchema.new(
                name: "__call__",
                params: [{% for key, type in dc_ann[:params] || {} of Nil => Nil %}{% has_default = dc_ann[:defaults] && dc_ann[:defaults].keys.includes?(key) %}{% dv = dc_ann[:defaults] && dc_ann[:defaults][key] %}::Crinkle::Schema::ParamSchema.new(name: {{ key.id.stringify }}, type: {{ type.id.stringify }}, required: {{ !has_default }}, default: {{ has_default ? (dv == nil ? nil : dv.stringify) : nil }}), {% end %}],
                returns: {{ dc_ann[:returns] ? dc_ann[:returns].id.stringify : "Value" }},
                doc: {{ dc_ann[:doc] }}
              ){% else %}nil{% end %},
              methods: {
                {% for method in @type.methods %}{% ann = method.annotation(::Crinkle::Method) %}{% if ann %}{% method_name = (ann[:name] || method.name).id.stringify %}{{ method_name }} => ::Crinkle::Schema::MethodSchema.new(
                  name: {{ method_name }},
                  params: [{% for key, type in ann[:params] || {} of Nil => Nil %}{% has_default = ann[:defaults] && ann[:defaults].keys.includes?(key) %}{% dv = ann[:defaults] && ann[:defaults][key] %}::Crinkle::Schema::ParamSchema.new(name: {{ key.id.stringify }}, type: {{ type.id.stringify }}, required: {{ !has_default }}, default: {{ has_default ? (dv == nil ? nil : dv.stringify) : nil }}), {% end %}],
                  returns: {{ ann[:returns] ? ann[:returns].id.stringify : "Value" }},
                  doc: {{ ann[:doc] }}
                ), {% end %}{% end %}
              } of String => ::Crinkle::Schema::MethodSchema,
            ){% end %}
          end
        {% end %}
      end
    end
  end

  macro register_callable(klass)
    ::Crinkle::Schema.registry.register_callable({{ klass }}.callable_schema)
  end
end
