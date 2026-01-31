module Crinkle::Std::Filters
  module Lists
    def self.register(env : Environment) : Nil
      env.register_filter("first") do |value, _args, _kwargs|
        case value
        when Array
          value.first?
        when String
          value.empty? ? "" : value[0].to_s
        end
      end

      env.register_filter("last") do |value, _args, _kwargs|
        case value
        when Array
          value.last?
        when String
          value.empty? ? "" : value[-1].to_s
        end
      end

      env.register_filter("join") do |value, args, _kwargs|
        sep = args.first?.to_s
        case value
        when Array
          value.map(&.to_s).join(sep)
        else
          value.to_s
        end
      end

      env.register_filter("length") do |value, _args, _kwargs|
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

      env.register_filter("sort") do |value, _args, kwargs|
        reverse = kwargs["reverse"]?.as?(Bool) || false
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

      env.register_filter("unique") do |value, _args, _kwargs|
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

      env.register_filter("batch") do |value, args, kwargs|
        case value
        when Array(Value)
          size = args.first?.as?(Int64) || 2_i64
          fill_with = kwargs["fill_with"]?

          result = Array(Value).new
          batch = Array(Value).new

          value.each_with_index do |item, i|
            batch << item
            if batch.size == size || i == value.size - 1
              # Pad if needed and at last batch
              if fill_with && batch.size < size
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

      env.register_filter("slice") do |value, args, kwargs|
        case value
        when Array(Value)
          slices = args.first?.as?(Int64) || 2_i64
          fill_with = kwargs["fill_with"]?

          next value if slices <= 0

          result = Array(Value).new
          slice_size = (value.size.to_f / slices).ceil.to_i

          slices.times do |i|
            start_idx = i * slice_size
            end_idx = [(i + 1) * slice_size, value.size].min

            if start_idx < value.size
              slice = value[start_idx...end_idx]

              # Pad if needed and fill_with is provided
              if fill_with && slice.size < slice_size
                slice = slice.dup
                while slice.size < slice_size
                  slice << fill_with
                end
              end

              result << slice.as(Value)
            end
          end

          result.as(Value)
        else
          value
        end
      end

      env.register_filter("sum") do |value, args, kwargs|
        case value
        when Array
          start = args.first?.as?(Int64 | Float64) || 0_i64
          attribute = kwargs["attribute"]?.to_s if kwargs["attribute"]?

          if attribute
            value.reduce(start) do |acc, item|
              case item
              when Hash
                acc + (item[attribute]?.as?(Int64 | Float64) || 0_i64)
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

      env.register_filter("map") do |value, args, _kwargs|
        attribute = args.first?.to_s
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

      env.register_filter("select") do |value, args, _kwargs|
        test_name = args.first?.to_s
        case value
        when Array(Value)
          test = env.tests[test_name]?
          next value unless test

          result = Array(Value).new
          value.each do |item|
            if test.call(item, Array(Value).new, Hash(String, Value).new)
              result << item
            end
          end
          result.as(Value)
        else
          value
        end
      end

      env.register_filter("reject") do |value, args, _kwargs|
        test_name = args.first?.to_s
        case value
        when Array(Value)
          test = env.tests[test_name]?
          next value unless test

          result = Array(Value).new
          value.each do |item|
            unless test.call(item, Array(Value).new, Hash(String, Value).new)
              result << item
            end
          end
          result.as(Value)
        else
          value
        end
      end

      env.register_filter("selectattr") do |value, args, _kwargs|
        attr = args[0]?.to_s
        test_name = args[1]?.to_s
        case value
        when Array(Value)
          test = env.tests[test_name]?
          next value unless test

          result = Array(Value).new
          value.each do |item|
            case item
            when Hash(String, Value)
              attr_value = item[attr]?
              if test.call(attr_value, Array(Value).new, Hash(String, Value).new)
                result << item
              end
            when Hash(Value, Value)
              attr_value = item[attr]?
              if test.call(attr_value, Array(Value).new, Hash(String, Value).new)
                result << item
              end
            end
          end
          result.as(Value)
        else
          value
        end
      end

      env.register_filter("rejectattr") do |value, args, _kwargs|
        attr = args[0]?.to_s
        test_name = args[1]?.to_s
        case value
        when Array(Value)
          test = env.tests[test_name]?
          next value unless test

          result = Array(Value).new
          value.each do |item|
            case item
            when Hash(String, Value)
              attr_value = item[attr]?
              unless test.call(attr_value, Array(Value).new, Hash(String, Value).new)
                result << item
              end
            when Hash(Value, Value)
              attr_value = item[attr]?
              unless test.call(attr_value, Array(Value).new, Hash(String, Value).new)
                result << item
              end
            end
          end
          result.as(Value)
        else
          value
        end
      end

      env.register_filter("default") do |value, args, kwargs|
        fallback = args.first? || ""
        default_value = kwargs["default_value"]?.as?(Bool) || false

        empty = case value
                when Nil
                  true
                when String
                  value.empty?
                when Array
                  value.empty?
                when Hash
                  value.empty?
                when Bool
                  !value && default_value
                else
                  false
                end
        empty ? fallback : value
      end
    end
  end
end
