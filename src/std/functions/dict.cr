module Crinkle::Std::Functions
  module Dict
    def self.register(env : Environment) : Nil
      env.register_function("dict") do |args, kwargs|
        result = Hash(String, Value).new

        # Handle kwargs
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

      env.register_function("namespace") do |_args, kwargs|
        # Creates a namespace object (hash) for storing state
        result = Hash(String, Value).new
        kwargs.each do |k, v|
          result[k] = v
        end
        result
      end
    end
  end
end
