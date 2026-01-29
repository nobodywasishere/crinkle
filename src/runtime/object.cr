require "./value"

module Jinja
  annotation Attribute
  end

  annotation Attributes
  end

  module Object
    module Auto
      include ::Jinja::Object

      def crinja_attribute(attr : ::Jinja::Value) : ::Jinja::Value
        {% begin %}
          {% exposed = [] of _ %}
          value = case attr.to_s
          {% for type in [@type] + @type.ancestors %}
            {% type_annotation = type.annotation(::Jinja::Attributes) %}
            {% expose_all = type_annotation && !type_annotation[:expose] %}
            {% if type_exposed = type_annotation && type_annotation[:expose] %}
              {% exposed = exposed + type_exposed.map &.id %}
            {% end %}
            {% for method in type.methods %}
              {% ann = method.annotation(::Jinja::Attribute) %}
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
                      {% raise "Method #{method.name} annotated as @[Jinja::Attribute] cannot be called without arguments" %}
                    {% end %}
                  {% elsif ann %}
                    {% raise "Method #{method.name} annotated as @[Jinja::Attribute] requires block" %}
                  {% end %}
                {% elsif ann %}
                  {% raise "Method #{method.name} annotated as @[Jinja::Attribute] has invalid name" %}
                {% end %}
              {% end %}
            {% end %}
          {% end %}
          else
            ::Jinja::Undefined.new(attr.to_s)
          end

          ::Jinja.value(value)
        {% end %}
      end
    end
  end
end
