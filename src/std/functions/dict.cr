module Crinkle::Std::Functions
  module Dict
    # Note: dict() accepts variadic positional args and kwargs
    # Each positional arg can be a [key, value] pair or a hash to merge
    # kwargs are added to the result dict
    Crinkle.define_function :dict,
      returns: Hash,
      doc: "Create a dictionary from keyword arguments or pairs" do
      result = Hash(String, Value).new

      # Handle kwargs (accessed via the generated code's kwargs variable)
      kwargs.each do |k, v|
        result[k] = v
      end

      # Handle positional args (list of key-value pairs)
      args.each do |arg|
        case arg
        when Array(Value)
          if arg.size == 2
            key = arg[0].to_s
            value = arg[1]
            result[key] = value
          end
        when Hash(String, Value)
          arg.each do |k, v|
            result[k] = v
          end
        when Hash(Value, Value)
          arg.each do |k, v|
            result[k.to_s] = v
          end
        end
      end

      result
    end

    Crinkle.define_function :namespace,
      returns: Hash,
      doc: "Create a namespace object from keyword arguments" do
      # Creates a namespace object (hash) for storing state
      result = Hash(String, Value).new
      kwargs.each do |k, v|
        result[k] = v
      end
      result
    end

    def self.register(env : Environment) : Nil
      register_function_dict(env)
      register_function_namespace(env)
    end
  end
end
