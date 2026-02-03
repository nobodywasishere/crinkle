module Crinkle::Std::Filters
  module Lists
    Crinkle.define_filter :first,
      params: {value: Value},
      returns: Value,
      doc: "Return first element of sequence" do |value|
      case value
      when Array
        value.first?
      when String
        value.empty? ? "" : value[0].to_s
      end
    end

    Crinkle.define_filter :last,
      params: {value: Value},
      returns: Value,
      doc: "Return last element of sequence" do |value|
      case value
      when Array
        value.last?
      when String
        value.empty? ? "" : value[-1].to_s
      end
    end

    Crinkle.define_filter :join,
      params: {value: Array, d: String},
      defaults: {d: ""},
      returns: String,
      doc: "Join array elements with separator" do |value, d|
      sep = d.to_s
      case value
      when Array
        value.map(&.to_s).join(sep)
      else
        value.to_s
      end
    end

    Crinkle.define_filter :length,
      params: {value: Value},
      returns: Int64,
      doc: "Return length of sequence" do |value|
      case value
      when String
        value.size.to_i64
      when Array
        value.size.to_i64
      when Hash
        value.size.to_i64
      else
        0_i64
      end
    end

    Crinkle.define_filter :sort,
      params: {value: Array, reverse: Bool},
      defaults: {reverse: false},
      returns: Array,
      doc: "Sort array elements" do |value, reverse|
      reverse = reverse.as?(Bool) || false
      case value
      when Array
        sorted = value.sort do |a, b|
          a.to_s <=> b.to_s
        end
        reverse ? sorted.reverse : sorted
      else
        value
      end
    end

    Crinkle.define_filter :unique,
      params: {value: Array},
      returns: Array,
      doc: "Remove duplicate elements" do |value|
      case value
      when Array(Value)
        # Manually implement unique using string representation
        # since Value type is too complex for Set/Hash keys
        seen = Hash(String, Bool).new
        result = Array(Value).new
        value.each do |item|
          key = item.to_s
          unless seen.has_key?(key)
            seen[key] = true
            result << item
          end
        end
        result
      else
        value
      end
    end

    Crinkle.define_filter :batch,
      params: {value: Array, linecount: Int64, fill_with: Value},
      defaults: {linecount: 2_i64, fill_with: nil},
      returns: Array,
      doc: "Batch items into fixed-size lists" do |value, linecount, fill_with|
      case value
      when Array(Value)
        size = linecount.as?(Int64) || 2_i64

        result = Array(Value).new
        batch = Array(Value).new

        value.each_with_index do |item, i|
          batch << item
          if batch.size == size || i == value.size - 1
            # Pad if needed and at last batch
            if fill_with && !fill_with.is_a?(Undefined) && batch.size < size
              while batch.size < size
                batch << fill_with
              end
            end
            result << batch.as(Value)
            batch = Array(Value).new
          end
        end

        result.as(Value)
      else
        value
      end
    end

    Crinkle.define_filter :slice,
      params: {value: Array, slices: Int64, fill_with: Value},
      defaults: {slices: 2_i64, fill_with: nil},
      returns: Array,
      doc: "Slice array into fixed number of slices" do |value, slices, fill_with|
      case value
      when Array(Value)
        slices = slices.as?(Int64) || 2_i64

        if slices <= 0
          value
        else
          result = Array(Value).new
          slice_size = (value.size.to_f / slices).ceil.to_i

          slices.times do |i|
            start_idx = i * slice_size
            end_idx = [(i + 1) * slice_size, value.size].min

            if start_idx < value.size
              slice = value[start_idx...end_idx]

              # Pad if needed and fill_with is provided
              if fill_with && !fill_with.is_a?(Undefined) && slice.size < slice_size
                slice = slice.dup
                while slice.size < slice_size
                  slice << fill_with
                end
              end

              result << slice.as(Value)
            end
          end

          result.as(Value)
        end
      else
        value
      end
    end

    Crinkle.define_filter :sum,
      params: {value: Array, start: Number, attribute: String},
      defaults: {start: 0_i64, attribute: nil},
      returns: Number,
      doc: "Sum array values" do |value, start, attribute|
      case value
      when Array
        start = start.as?(Int64 | Float64) || 0_i64
        attribute_str = attribute.to_s if attribute && !attribute.is_a?(Undefined)

        if attribute_str
          value.reduce(start) do |acc, item|
            case item
            when Hash
              acc + (item[attribute_str]?.as?(Int64 | Float64) || 0_i64)
            else
              acc
            end
          end
        else
          value.reduce(start) do |acc, item|
            case item
            when Int64
              acc + item
            when Float64
              acc + item
            else
              acc
            end
          end
        end
      else
        value
      end
    end

    Crinkle.define_filter :map,
      params: {value: Array, attribute: String},
      returns: Array,
      doc: "Apply attribute extraction to array" do |value, attribute|
      attribute = attribute.to_s
      case value
      when Array(Value)
        result = Array(Value).new
        value.each do |item|
          case item
          when Hash(String, Value)
            result << item[attribute]?
          when Hash(Value, Value)
            result << item[attribute]?
          else
            result << nil
          end
        end
        result.as(Value)
      else
        value
      end
    end

    Crinkle.define_filter :select,
      params: {value: Array, test_name: String},
      variadic: [:test_name],
      returns: Array,
      doc: "Filter array by test" do |value, test_name|
      test_name = test_name.to_s
      case value
      when Array(Value)
        test = env.tests[test_name]?
        if test
          result = Array(Value).new
          value.each do |item|
            if test.call(item, Array(Value).new, Hash(String, Value).new, ctx, span)
              result << item
            end
          end
          result.as(Value)
        else
          value
        end
      else
        value
      end
    end

    Crinkle.define_filter :reject,
      params: {value: Array, test_name: String},
      variadic: [:test_name],
      returns: Array,
      doc: "Filter array by rejecting test matches" do |value, test_name|
      test_name = test_name.to_s
      case value
      when Array(Value)
        test = env.tests[test_name]?
        if test
          result = Array(Value).new
          value.each do |item|
            unless test.call(item, Array(Value).new, Hash(String, Value).new, ctx, span)
              result << item
            end
          end
          result.as(Value)
        else
          value
        end
      else
        value
      end
    end

    Crinkle.define_filter :selectattr,
      params: {value: Array, attribute: String, test: String},
      defaults: {test: ""},
      variadic: [:test],
      returns: Array,
      doc: "Filter array by attribute test or truthiness" do |value, attribute, test|
      case value
      when Array(Value)
        varargs = args
        attribute = attribute.to_s
        test_name = test.to_s

        test_kwargs = kwargs.dup
        test_kwargs.delete("attribute")
        test_kwargs.delete("test")

        if test_name.empty?
          result = Array(Value).new
          value.each do |item|
            selected = selectattr_truthy?(resolve_attr_value(item, attribute))
            result << item if selected
          end
          result.as(Value)
        else
          test = env.tests[test_name]?
          return value unless test

          start_index = 0
          start_index += 1 unless kwargs.has_key?("attribute")
          start_index += 1 unless kwargs.has_key?("test")
          test_args = varargs.size > start_index ? varargs[start_index..] : Array(Value).new
          result = Array(Value).new
          value.each do |item|
            attr_resolved = resolve_attr_value(item, attribute)
            if test.call(attr_resolved, test_args, test_kwargs, ctx, span)
              result << item
            end
          end
          result.as(Value)
        end
      else
        value
      end
    end

    Crinkle.define_filter :rejectattr,
      params: {value: Array, attribute: String, test: String},
      defaults: {test: ""},
      variadic: [:test],
      returns: Array,
      doc: "Filter array by rejecting attribute test or truthiness" do |value, attribute, test|
      case value
      when Array(Value)
        varargs = args
        attribute = attribute.to_s
        test_name = test.to_s

        test_kwargs = kwargs.dup
        test_kwargs.delete("attribute")
        test_kwargs.delete("test")

        if test_name.empty?
          result = Array(Value).new
          value.each do |item|
            selected = selectattr_truthy?(resolve_attr_value(item, attribute))
            result << item unless selected
          end
          result.as(Value)
        else
          test = env.tests[test_name]?
          return value unless test

          start_index = 0
          start_index += 1 unless kwargs.has_key?("attribute")
          start_index += 1 unless kwargs.has_key?("test")
          test_args = varargs.size > start_index ? varargs[start_index..] : Array(Value).new
          result = Array(Value).new
          value.each do |item|
            attr_resolved = resolve_attr_value(item, attribute)
            unless test.call(attr_resolved, test_args, test_kwargs, ctx, span)
              result << item
            end
          end
          result.as(Value)
        end
      else
        value
      end
    end

    private def self.resolve_attr_value(item : Value, attribute : String) : Value
      parts = attribute.split(".")
      current = item

      parts.each do |part|
        return Crinkle::Undefined.new(attribute) if current.is_a?(Undefined) || current.is_a?(StrictUndefined)

        if part =~ /^\d+$/
          index = part.to_i
          case current
          when Array(Value)
            current = current[index]? || Crinkle::Undefined.new(attribute)
          when Hash(String, Value)
            current = current[index.to_s]? || Crinkle::Undefined.new(attribute)
          when Hash(Value, Value)
            current = current[Crinkle.value(index.to_i64)]? || Crinkle::Undefined.new(attribute)
          else
            current = Crinkle::Undefined.new(attribute)
          end
        else
          case current
          when Hash(String, Value)
            current = current[part]? || Crinkle::Undefined.new(attribute)
          when Hash(Value, Value)
            current = current[Crinkle.value(part)]? || Crinkle::Undefined.new(attribute)
          else
            if current.responds_to?(:jinja_attribute)
              current = current.jinja_attribute(Crinkle.value(part))
            else
              current = Crinkle::Undefined.new(attribute)
            end
          end
        end
      end

      current
    end

    private def self.selectattr_truthy?(value : Value) : Bool
      case value
      when Nil
        false
      when Undefined, StrictUndefined
        false
      when Bool
        value
      when Int64
        value != 0
      when Int32
        value != 0
      when Float64
        value != 0.0
      when String
        !value.empty?
      when SafeString
        !value.to_s.empty?
      when Array(Value)
        !value.empty?
      when Hash(String, Value)
        !value.empty?
      when Hash(Value, Value)
        !value.empty?
      else
        true
      end
    end

    Crinkle.define_filter :default,
      params: {value: Value, default_value: Value, boolean: Bool},
      defaults: {default_value: "", boolean: false},
      returns: Value,
      doc: "Return default value if undefined or empty" do |value, default_value, boolean|
      fallback = default_value
      boolean = boolean.as?(Bool) || false

      empty = case value
              when Nil
                true
              when Undefined
                true
              when String
                value.empty?
              when Array
                value.empty?
              when Hash
                value.empty?
              when Bool
                !value && boolean
              else
                false
              end
      empty ? fallback : value
    end

    Crinkle.define_filter :random,
      params: {value: Array},
      returns: Value,
      doc: "Return random element from array" do |value|
      case value
      when Array(Value)
        value.empty? ? nil : value.sample
      else
        value
      end
    end

    def self.register(env : Environment) : Nil
      register_filter_first(env)
      register_filter_last(env)
      register_filter_join(env)
      register_filter_length(env)
      register_filter_sort(env)
      register_filter_unique(env)
      register_filter_batch(env)
      register_filter_slice(env)
      register_filter_sum(env)
      register_filter_map(env)
      register_filter_select(env)
      register_filter_reject(env)
      register_filter_selectattr(env)
      register_filter_rejectattr(env)
      register_filter_default(env)
      register_filter_random(env)
    end
  end
end
