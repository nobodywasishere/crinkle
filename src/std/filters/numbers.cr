module Crinkle::Std::Filters
  module Numbers
    Crinkle.define_filter :int,
      params: {value: Value, default: Int64, base: Int64},
      defaults: {default: 0_i64, base: 10_i64},
      returns: Int64,
      doc: "Convert value to integer" do |value, default, base|
      default = default.as?(Int64) || 0_i64
      base = base.as?(Int64) || 10_i64

      case value
      when Int64
        value
      when Float64
        value.to_i64
      when String
        value.to_i64?(base.to_i) || default
      when Bool
        value ? 1_i64 : 0_i64
      else
        default
      end
    end

    Crinkle.define_filter :float,
      params: {value: Value, default: Float64},
      defaults: {default: 0.0},
      returns: Float64,
      doc: "Convert value to float" do |value, default|
      default = default.as?(Float64) || 0.0
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

    Crinkle.define_filter :abs,
      params: {value: Number},
      returns: Number,
      doc: "Return absolute value" do |value|
      case value
      when Int64
        value.abs
      when Float64
        value.abs
      else
        value
      end
    end

    Crinkle.define_filter :round,
      params: {value: Number, precision: Int64, method: String},
      defaults: {precision: 0_i64, method: "common"},
      returns: Float64,
      doc: "Round number to given precision" do |value, precision, method|
      precision = precision.as?(Int64) || 0_i64
      method = method.to_s
      method = "common" if method.empty?

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

    Crinkle.define_filter :min,
      params: {value: Array},
      returns: Value,
      doc: "Return minimum value from array" do |value|
      case value
      when Array
        value.min_by? { |v| v.as?(Int64 | Float64) || Float64::MAX }
      else
        value
      end
    end

    Crinkle.define_filter :max,
      params: {value: Array},
      returns: Value,
      doc: "Return maximum value from array" do |value|
      case value
      when Array
        value.max_by? { |v| v.as?(Int64 | Float64) || Float64::MIN }
      else
        value
      end
    end

    Crinkle.define_filter :pow,
      params: {value: Number, exponent: Number},
      defaults: {exponent: 2_i64},
      returns: Number,
      doc: "Raise value to power of exponent" do |value, exponent|
      exp = exponent.as?(Int64 | Float64) || 2_i64
      case value
      when Int64
        (value ** exp).to_i64
      when Float64
        value ** exp
      else
        value
      end
    end

    def self.register(env : Environment) : Nil
      register_filter_int(env)
      register_filter_float(env)
      register_filter_abs(env)
      register_filter_round(env)
      register_filter_min(env)
      register_filter_max(env)
      register_filter_pow(env)
    end
  end
end
