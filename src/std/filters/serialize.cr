module Crinkle::Std::Filters
  module Serialize
    Crinkle.define_filter :tojson,
      params: {value: Value, indent: Int64},
      defaults: {indent: nil},
      returns: SafeString,
      doc: "Convert value to JSON string" do |value, indent|
      indent = indent.as?(Int64)

      json_str = if indent
                   value_to_json(value).to_pretty_json
                 else
                   value_to_json(value).to_json
                 end

      SafeString.new(json_str)
    end

    Crinkle.define_filter :pprint,
      params: {value: Value},
      returns: SafeString,
      doc: "Pretty-print value as JSON" do |value|
      SafeString.new(value_to_json(value).to_pretty_json)
    end

    Crinkle.define_filter :list,
      params: {value: Value},
      returns: Array,
      doc: "Convert value to list" do |value|
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

    Crinkle.define_filter :string,
      params: {value: Value},
      returns: String,
      doc: "Convert value to string" do |value|
      value.to_s
    end

    Crinkle.define_filter :attr,
      params: {value: Value, name: String},
      returns: Value,
      doc: "Get attribute from object" do |value, name|
      name = name.to_s
      case value
      when Hash
        value[name]?
      end
    end

    Crinkle.define_filter :dictsort,
      params: {value: Hash, by: String, case_sensitive: Bool, reverse: Bool},
      defaults: {by: "key", case_sensitive: false, reverse: false},
      returns: Array,
      doc: "Sort dictionary items" do |value, by, case_sensitive, reverse|
      case_sensitive = case_sensitive.as?(Bool) || false
      by_str = by.to_s
      by_str = "key" if by_str.empty?
      reverse = reverse.as?(Bool) || false

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
          compare_val_a = by_str == "value" ? a[1] : a[0]
          compare_val_b = by_str == "value" ? b[1] : b[0]

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
          compare_val_a = by_str == "value" ? a[1] : a[0]
          compare_val_b = by_str == "value" ? b[1] : b[0]

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

    Crinkle.define_filter :items,
      params: {value: Hash},
      returns: Array,
      doc: "Return list of key-value pairs from dictionary" do |value|
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

    def self.register(env : Environment) : Nil
      register_filter_tojson(env)
      register_filter_pprint(env)
      register_filter_list(env)
      register_filter_string(env)
      register_filter_attr(env)
      register_filter_dictsort(env)
      register_filter_items(env)
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
