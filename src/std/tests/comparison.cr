module Crinkle::Std::Tests
  module Comparison
    Crinkle.define_test :eq,
      params: {value: Value, other: Value},
      doc: "Check if value equals other" do |value, other|
      value == other
    end

    Crinkle.define_test :equalto,
      params: {value: Value, other: Value},
      doc: "Check if value equals other (alias for eq)" do |value, other|
      value == other
    end

    Crinkle.define_test :ne,
      params: {value: Value, other: Value},
      doc: "Check if value does not equal other" do |value, other|
      value != other
    end

    Crinkle.define_test :lt,
      params: {value: Value, other: Value},
      doc: "Check if value is less than other" do |value, other|
      case value
      when Int64, Float64
        case other
        when Int64, Float64
          value < other
        else
          false
        end
      when String
        other.is_a?(String) && value < other
      else
        false
      end
    end

    Crinkle.define_test :le,
      params: {value: Value, other: Value},
      doc: "Check if value is less than or equal to other" do |value, other|
      case value
      when Int64, Float64
        case other
        when Int64, Float64
          value <= other
        else
          false
        end
      when String
        other.is_a?(String) && value <= other
      else
        false
      end
    end

    Crinkle.define_test :gt,
      params: {value: Value, other: Value},
      doc: "Check if value is greater than other" do |value, other|
      case value
      when Int64, Float64
        case other
        when Int64, Float64
          value > other
        else
          false
        end
      when String
        other.is_a?(String) && value > other
      else
        false
      end
    end

    Crinkle.define_test :ge,
      params: {value: Value, other: Value},
      doc: "Check if value is greater than or equal to other" do |value, other|
      case value
      when Int64, Float64
        case other
        when Int64, Float64
          value >= other
        else
          false
        end
      when String
        other.is_a?(String) && value >= other
      else
        false
      end
    end

    Crinkle.define_test :greaterthan,
      params: {value: Value, other: Value},
      doc: "Check if value is greater than other (alias for gt)" do |value, other|
      case value
      when Int64, Float64
        case other
        when Int64, Float64
          value > other
        else
          false
        end
      when String
        other.is_a?(String) && value > other
      else
        false
      end
    end

    Crinkle.define_test :lessthan,
      params: {value: Value, other: Value},
      doc: "Check if value is less than other (alias for lt)" do |value, other|
      case value
      when Int64, Float64
        case other
        when Int64, Float64
          value < other
        else
          false
        end
      when String
        other.is_a?(String) && value < other
      else
        false
      end
    end

    # Note: Using string name because 'in' is a keyword
    Crinkle.define_test "in",
      params: {value: Value, container: Value},
      doc: "Check if value is in container" do |value, container|
      case container
      when Array
        container.includes?(value)
      when Hash
        container.has_key?(value.to_s)
      when String
        container.includes?(value.to_s)
      else
        false
      end
    end

    def self.register(env : Environment) : Nil
      register_test_eq(env)
      register_test_equalto(env)
      register_test_ne(env)
      register_test_lt(env)
      register_test_le(env)
      register_test_gt(env)
      register_test_ge(env)
      register_test_greaterthan(env)
      register_test_lessthan(env)
      register_test_in(env)
    end
  end
end
