require "./value"
require "./callable"

module Crinkle
  annotation Attribute
  end

  annotation Attributes
  end

  module Object
    # Returns a callable proc for the given method name, or nil if the method is not callable.
    # Objects can override this to expose methods that can be invoked from templates.
    #
    # Example:
    # ```
    # def jinja_call(name : String) : CallableProc?
    #   case name
    #   when "localize"
    #     ->(args : Arguments) : Value {
    #       key = args.varargs[0]?.try(&.to_s) || ""
    #       Crinkle.value(translate(key))
    #     }
    #   end
    # end
    # ```
    def jinja_call(name : String) : CallableProc?
      nil # Default: no callable methods
    end

    module Auto
      include ::Crinkle::Object

      def crinja_attribute(attr : ::Crinkle::Value) : ::Crinkle::Value
        {% begin %}
          {% exposed = [] of _ %}
          value = case attr.to_s
          {% for type in [@type] + @type.ancestors %}
            {% type_annotation = type.annotation(::Crinkle::Attributes) %}
            {% expose_all = type_annotation && !type_annotation[:expose] %}
            {% if type_exposed = type_annotation && type_annotation[:expose] %}
              {% exposed = exposed + type_exposed.map &.id %}
            {% end %}
            {% for method in type.methods %}
              {% ann = method.annotation(::Crinkle::Attribute) %}
              {% expose_this_method = (expose_all || ann || exposed.includes? method.name) && (!ann || !ann[:ignore]) %}
              {% if expose_this_method %}
                {% if method.name != "initialize" %}
                  {% if !method.accepts_block? %}
                    {% if method.args.all? { |arg| arg.default_value.class_name != "Nop" } %}
                      {% method_name = (ann && ann[:name]) || method.name %}
                      {% if !(ann && ann[:name]) && method.name.ends_with?("?") %}
                        when "is_{{ method_name.id[0..-2] }}"
                      {% else %}
                        when {{ method_name.id.stringify }}
                      {% end %}
                      self.{{ method.name.id }}
                    {% elsif ann %}
                      {% raise "Method #{method.name} annotated as @[Crinkle::Attribute] cannot be called without arguments" %}
                    {% end %}
                  {% elsif ann %}
                    {% raise "Method #{method.name} annotated as @[Crinkle::Attribute] requires block" %}
                  {% end %}
                {% elsif ann %}
                  {% raise "Method #{method.name} annotated as @[Crinkle::Attribute] has invalid name" %}
                {% end %}
              {% end %}
            {% end %}
          {% end %}
          else
            ::Crinkle::Undefined.new(attr.to_s)
          end

          ::Crinkle.value(value)
        {% end %}
      end
    end
  end
end
