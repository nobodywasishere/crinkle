module Crinkle::Std::Filters
  module Numbers
    def self.register(env : Environment) : Nil
      env.register_filter("int") do |value, args, kwargs|
        default = kwargs["default"]? || args.first? || 0_i64
        default = default.as?(Int64) || 0_i64
        base_arg = kwargs["base"]? || args[1]?
        base = base_arg ? (base_arg.as?(Int64) || base_arg.to_s.to_i? || 10) : 10

        case value
        when Int64
          value
        when Float64
          value.to_i64
        when String
          value.to_i64?(base) || default
        when Bool
          value ? 1_i64 : 0_i64
        else
          default
        end
      end

      env.register_filter("float") do |value, args, _kwargs|
        default = args.first?.as?(Float64) || 0.0
        case value
        when Float64
          value
        when Int64
          value.to_f64
        when String
          value.to_f64? || default
        when Bool
          value ? 1.0 : 0.0
        else
          default
        end
      end

      env.register_filter("abs") do |value, _args, _kwargs|
        case value
        when Int64
          value.abs
        when Float64
          value.abs
        else
          value
        end
      end

      env.register_filter("round") do |value, args, kwargs|
        precision = args.first?.as?(Int64) || 0_i64
        method = kwargs["method"]?.to_s || "common"

        case value
        when Float64
          case method
          when "ceil"
            (value * (10 ** precision)).ceil / (10 ** precision)
          when "floor"
            (value * (10 ** precision)).floor / (10 ** precision)
          else # "common"
            value.round(precision.to_i)
          end
        when Int64
          value.to_f64
        else
          value
        end
      end

      env.register_filter("min") do |value, _args, _kwargs|
        case value
        when Array
          value.min_by? { |v| v.as?(Int64 | Float64) || Float64::MAX }
        else
          value
        end
      end

      env.register_filter("max") do |value, _args, _kwargs|
        case value
        when Array
          value.max_by? { |v| v.as?(Int64 | Float64) || Float64::MIN }
        else
          value
        end
      end

      env.register_filter("pow") do |value, args, _kwargs|
        exp = args.first?.as?(Int64 | Float64) || 2_i64
        case value
        when Int64
          (value ** exp).to_i64
        when Float64
          value ** exp
        else
          value
        end
      end
    end
  end
end
