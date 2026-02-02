module Crinkle
  class TemplateNotFoundError < Exception
    getter template_name : String
    getter loader : String?

    def initialize(@template_name : String, @loader : String? = nil, message : String? = nil) : Nil
      super(message || "Template '#{@template_name}' not found")
    end
  end

  class Template
    getter source : String
    getter ast : AST::Template
    getter name : String
    getter filename : String?
    getter environment : Environment?

    def initialize(
      @source : String,
      @ast : AST::Template,
      @name : String,
      @filename : String? = nil,
      @environment : Environment? = nil,
    ) : Nil
    end

    def render(context : Hash(String, Value) = Hash(String, Value).new) : String
      env = @environment || Environment.new
      renderer = Renderer.new(env)
      renderer.render(@ast, context)
    end

    def render(**variables) : String
      context = Hash(String, Value).new
      variables.each do |key, value|
        context[key.to_s] = Crinkle.value(value)
      end
      render(context)
    end
  end
end
