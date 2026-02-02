module Crinkle::Std::Tests
  module Comparison
    def self.register(env : Environment) : Nil
      env.register_test("eq") do |value, args, _kwargs, _ctx|
        other = args.first?
        value == other
      end

      env.register_test("equalto") do |value, args, _kwargs, _ctx|
        other = args.first?
        value == other
      end

      env.register_test("ne") do |value, args, _kwargs, _ctx|
        other = args.first?
        value != other
      end

      env.register_test("lt") do |value, args, _kwargs, _ctx|
        other = args.first?
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

      env.register_test("le") do |value, args, _kwargs, _ctx|
        other = args.first?
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

      env.register_test("gt") do |value, args, _kwargs, _ctx|
        other = args.first?
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

      env.register_test("ge") do |value, args, _kwargs, _ctx|
        other = args.first?
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

      env.register_test("greaterthan") do |value, args, _kwargs, _ctx|
        other = args.first?
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

      env.register_test("lessthan") do |value, args, _kwargs, _ctx|
        other = args.first?
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

      env.register_test("in") do |value, args, _kwargs, _ctx|
        container = args.first?
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
    end
  end
end
