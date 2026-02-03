module Crinkle::Std::Functions
  module Macro
    Crinkle.define_function :caller,
      returns: String,
      doc: "Returns the content passed to a macro via {% call %}. Only valid inside macro bodies." do
      # The actual caller content is injected by the renderer when evaluating
      # a macro invoked via {% call macro_name() %}...{% endcall %}
      # At static analysis time, we just need to recognize it as a valid function.
      ""
    end

    def self.register(env : Environment) : Nil
      register_function_caller(env)
    end
  end
end
