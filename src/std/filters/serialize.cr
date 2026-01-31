module Crinkle::Std::Filters
  module Serialize
    def self.register(env : Environment) : Nil
      env.register_filter("tojson") do |value, args, _kwargs|
        indent = args.first?.as?(Int64)

        json_str = if indent
                     value_to_json(value).to_pretty_json
                   else
                     value_to_json(value).to_json
                   end

        SafeString.new(json_str)
      end

      env.register_filter("pprint") do |value, _args, _kwargs|
        SafeString.new(value_to_json(value).to_pretty_json)
      end

      env.register_filter("list") do |value, _args, _kwargs|
        case value
        when Array(Value)
          value
        when String
          value.chars.map { |char| char.to_s.as(Value) }.to_a.as(Array(Value))
        when Hash(String, Value)
          result = Array(Value).new
          value.each_key { |k| result << k }
          result
        when Hash(Value, Value)
          result = Array(Value).new
          value.each_key { |k| result << k }
          result
        else
          [value].as(Array(Value))
        end
      end

      env.register_filter("string") do |value, _args, _kwargs|
        value.to_s
      end

      env.register_filter("attr") do |value, args, _kwargs|
        name = args.first?.to_s
        case value
        when Hash
          value[name]?
        end
      end

      env.register_filter("dictsort") do |value, args, kwargs|
        case_sensitive = kwargs["case_sensitive"]?.as?(Bool) || false
        by = args.first?.to_s || "key"
        reverse = kwargs["reverse"]?.as?(Bool) || false

        case value
        when Hash(String, Value)
          # Convert to array of pairs for sorting
          pairs = Array(Array(Value)).new
          value.each do |k, v|
            pair = Array(Value).new
            pair << k
            pair << v
            pairs << pair
          end

          # Sort pairs
          sorted = pairs.sort do |a, b|
            compare_val_a = by == "value" ? a[1] : a[0]
            compare_val_b = by == "value" ? b[1] : b[0]

            str_a = compare_val_a.to_s
            str_b = compare_val_b.to_s

            unless case_sensitive
              str_a = str_a.downcase
              str_b = str_b.downcase
            end

            str_a <=> str_b
          end

          result = reverse ? sorted.reverse : sorted
          result.map(&.as(Value)).to_a.as(Value)
        when Hash(Value, Value)
          pairs = Array(Array(Value)).new
          value.each do |k, v|
            pair = Array(Value).new
            pair << k
            pair << v
            pairs << pair
          end

          sorted = pairs.sort do |a, b|
            compare_val_a = by == "value" ? a[1] : a[0]
            compare_val_b = by == "value" ? b[1] : b[0]

            str_a = compare_val_a.to_s
            str_b = compare_val_b.to_s

            unless case_sensitive
              str_a = str_a.downcase
              str_b = str_b.downcase
            end

            str_a <=> str_b
          end

          result = reverse ? sorted.reverse : sorted
          result.map(&.as(Value)).to_a.as(Value)
        else
          value
        end
      end

      env.register_filter("items") do |value, _args, _kwargs|
        case value
        when Hash(String, Value)
          result = Array(Value).new
          value.each do |k, v|
            pair = Array(Value).new
            pair << k
            pair << v
            result << pair.as(Value)
          end
          result.as(Value)
        when Hash(Value, Value)
          result = Array(Value).new
          value.each do |k, v|
            pair = Array(Value).new
            pair << k
            pair << v
            result << pair.as(Value)
          end
          result.as(Value)
        else
          Array(Value).new
        end
      end
    end

    private def self.value_to_json(value : Value) : JSON::Any
      case value
      when String
        JSON::Any.new(value)
      when Int64
        JSON::Any.new(value)
      when Float64
        JSON::Any.new(value)
      when Bool
        JSON::Any.new(value)
      when Nil
        JSON::Any.new(nil)
      when Array(Value)
        JSON::Any.new(value.map { |v| value_to_json(v) })
      when Hash(String, Value)
        result = Hash(String, JSON::Any).new
        value.each { |k, v| result[k] = value_to_json(v) }
        JSON::Any.new(result)
      when Hash(Value, Value)
        result = Hash(String, JSON::Any).new
        value.each { |k, v| result[k.to_s] = value_to_json(v) }
        JSON::Any.new(result)
      else
        JSON::Any.new(value.to_s)
      end
    end
  end
end
