module Crinkle::Std::Tests
  module Types
    def self.register(env : Environment) : Nil
      env.register_test("defined") do |value, _args, _kwargs|
        !value.is_a?(Undefined)
      end

      env.register_test("undefined") do |value, _args, _kwargs|
        value.is_a?(Undefined)
      end

      env.register_test("none") do |value, _args, _kwargs|
        value.nil?
      end

      env.register_test("boolean") do |value, _args, _kwargs|
        value.is_a?(Bool)
      end

      env.register_test("false") do |value, _args, _kwargs|
        value == false
      end

      env.register_test("true") do |value, _args, _kwargs|
        value == true
      end

      env.register_test("number") do |value, _args, _kwargs|
        value.is_a?(Int64) || value.is_a?(Float64)
      end

      env.register_test("integer") do |value, _args, _kwargs|
        value.is_a?(Int64)
      end

      env.register_test("float") do |value, _args, _kwargs|
        value.is_a?(Float64)
      end

      env.register_test("string") do |value, _args, _kwargs|
        value.is_a?(String)
      end

      env.register_test("sequence") do |value, _args, _kwargs|
        value.is_a?(Array)
      end

      env.register_test("iterable") do |value, _args, _kwargs|
        value.is_a?(Array) || value.is_a?(Hash) || value.is_a?(String)
      end

      env.register_test("mapping") do |value, _args, _kwargs|
        value.is_a?(Hash)
      end

      env.register_test("callable") do |_value, _args, _kwargs|
        # In this context, functions registered in env are callable
        false
      end

      env.register_test("odd") do |value, _args, _kwargs|
        case value
        when Int64
          value.odd?
        else
          false
        end
      end

      env.register_test("even") do |value, _args, _kwargs|
        case value
        when Int64
          value.even?
        else
          false
        end
      end

      env.register_test("divisibleby") do |value, args, _kwargs|
        divisor = args.first?.as?(Int64)
        next false unless divisor

        case value
        when Int64
          value % divisor == 0
        else
          false
        end
      end
    end
  end
end
