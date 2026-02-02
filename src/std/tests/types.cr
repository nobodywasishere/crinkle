module Crinkle::Std::Tests
  module Types
    Crinkle.define_test :defined,
      params: {value: Any},
      doc: "Check if value is defined" do |value|
      !value.is_a?(Undefined)
    end

    Crinkle.define_test :undefined,
      params: {value: Any},
      doc: "Check if value is undefined" do |value|
      value.is_a?(Undefined)
    end

    Crinkle.define_test :none,
      params: {value: Any},
      doc: "Check if value is none/nil" do |value|
      value.nil?
    end

    Crinkle.define_test :boolean,
      params: {value: Any},
      doc: "Check if value is a boolean" do |value|
      value.is_a?(Bool)
    end

    # Note: Using string name because 'false' is a keyword
    Crinkle.define_test "false",
      params: {value: Any},
      doc: "Check if value is false" do |value|
      value == false
    end

    # Note: Using string name because 'true' is a keyword
    Crinkle.define_test "true",
      params: {value: Any},
      doc: "Check if value is true" do |value|
      value == true
    end

    Crinkle.define_test :number,
      params: {value: Any},
      doc: "Check if value is a number" do |value|
      value.is_a?(Int64) || value.is_a?(Float64)
    end

    Crinkle.define_test :integer,
      params: {value: Any},
      doc: "Check if value is an integer" do |value|
      value.is_a?(Int64)
    end

    Crinkle.define_test :float,
      params: {value: Any},
      doc: "Check if value is a float" do |value|
      value.is_a?(Float64)
    end

    Crinkle.define_test :string,
      params: {value: Any},
      doc: "Check if value is a string" do |value|
      value.is_a?(String)
    end

    Crinkle.define_test :sequence,
      params: {value: Any},
      doc: "Check if value is a sequence (array or string)" do |value|
      value.is_a?(Array) || value.is_a?(String)
    end

    Crinkle.define_test :iterable,
      params: {value: Any},
      doc: "Check if value is iterable" do |value|
      value.is_a?(Array) || value.is_a?(Hash) || value.is_a?(String)
    end

    Crinkle.define_test :mapping,
      params: {value: Any},
      doc: "Check if value is a mapping (hash/dict)" do |value|
      value.is_a?(Hash)
    end

    Crinkle.define_test :callable,
      params: {value: Any},
      doc: "Check if value is callable" do |value|
      # Check if the value is an Object that can have callable methods
      value.is_a?(Crinkle::Object)
    end

    Crinkle.define_test :sameas,
      params: {value: Any, other: Any},
      doc: "Check if value is same object as other" do |value, other|
      # Identity comparison - same object reference
      # For reference types, use same?; for value types, use ==
      case value
      when Reference
        case other
        when Reference
          value.same?(other)
        else
          false
        end
      else
        # For value types (primitives), identity is the same as equality
        value == other
      end
    end

    Crinkle.define_test :escaped,
      params: {value: Any},
      doc: "Check if value is escaped (SafeString)" do |value|
      value.is_a?(SafeString)
    end

    Crinkle.define_test :odd,
      params: {value: Any},
      doc: "Check if value is odd" do |value|
      case value
      when Int64
        value.odd?
      else
        false
      end
    end

    Crinkle.define_test :even,
      params: {value: Any},
      doc: "Check if value is even" do |value|
      case value
      when Int64
        value.even?
      else
        false
      end
    end

    Crinkle.define_test :divisibleby,
      params: {value: Any, num: Int64},
      doc: "Check if value is divisible by num" do |value, num|
      divisor = num.as?(Int64)
      if divisor
        case value
        when Int64
          value % divisor == 0
        else
          false
        end
      else
        false
      end
    end

    def self.register(env : Environment) : Nil
      register_test_defined(env)
      register_test_undefined(env)
      register_test_none(env)
      register_test_boolean(env)
      register_test_false(env)
      register_test_true(env)
      register_test_number(env)
      register_test_integer(env)
      register_test_float(env)
      register_test_string(env)
      register_test_sequence(env)
      register_test_iterable(env)
      register_test_mapping(env)
      register_test_callable(env)
      register_test_sameas(env)
      register_test_escaped(env)
      register_test_odd(env)
      register_test_even(env)
      register_test_divisibleby(env)
    end
  end
end
