module Crinkle::Std::Filters
  module Strings
    def self.register(env : Environment) : Nil
      env.register_filter("upper") do |value, _args, _kwargs, _ctx|
        value.to_s.upcase
      end

      env.register_filter("lower") do |value, _args, _kwargs, _ctx|
        value.to_s.downcase
      end

      env.register_filter("capitalize") do |value, _args, _kwargs, _ctx|
        str = value.to_s
        next str if str.empty?
        rest = str[1..]?
        str[0].upcase + (rest ? rest.downcase : "")
      end

      env.register_filter("trim") do |value, _args, _kwargs, _ctx|
        value.to_s.strip
      end

      env.register_filter("truncate") do |value, args, kwargs, _ctx|
        str = value.to_s
        length = kwargs["length"]? || args.first? || 255_i64
        length = length.as?(Int64) || 255_i64
        killwords = kwargs["killwords"]?.as?(Bool) || false
        end_str = kwargs["end"]?.to_s || "..."
        leeway = kwargs["leeway"]? || args[3]? || 0_i64
        leeway = leeway.as?(Int64) || 0_i64

        next str if str.size <= length + leeway

        if killwords
          str[0...(length - end_str.size)] + end_str
        else
          # Find last space before length
          truncated = str[0...(length - end_str.size)]
          last_space = truncated.rindex(' ')
          if last_space
            truncated[0...last_space] + end_str
          else
            truncated + end_str
          end
        end
      end

      env.register_filter("replace") do |value, args, kwargs, _ctx|
        str = value.to_s
        old = kwargs["old"]? || args[0]?
        new_str = kwargs["new"]? || args[1]?
        count = kwargs["count"]? || args[2]?

        next value unless old && new_str

        old = old.to_s
        new_str = new_str.to_s

        if count
          count_val = count.as?(Int64) || count.to_s.to_i? || 0
          count_val.times { str = str.sub(old, new_str) }
          str
        else
          str.gsub(old, new_str)
        end
      end

      env.register_filter("title") do |value, _args, _kwargs, _ctx|
        value.to_s.split(' ').map(&.capitalize).join(' ')
      end

      env.register_filter("wordcount") do |value, _args, _kwargs, _ctx|
        value.to_s.split.size.to_i64
      end

      env.register_filter("reverse") do |value, _args, _kwargs, _ctx|
        case value
        when String
          value.reverse
        when Array
          value.reverse
        else
          value
        end
      end

      env.register_filter("center") do |value, args, _kwargs, _ctx|
        str = value.to_s
        width = args.first?.as?(Int64) || 80_i64
        str.center(width.to_i)
      end

      env.register_filter("indent") do |value, args, kwargs, _ctx|
        str = value.to_s
        width = args.first?.as?(Int64) || 4_i64
        first = kwargs["first"]?.as?(Bool) || false

        lines = str.lines
        indented = lines.map_with_index do |line, i|
          if i == 0 && !first
            line
          else
            " " * width.to_i + line
          end
        end

        indented.join('\n')
      end

      env.register_filter("format") do |value, args, _kwargs, _ctx|
        format_str = value.to_s
        begin
          # Simple format implementation - replace %s, %d, %i, %f sequentially
          result = format_str
          args.each do |arg|
            result = result.sub(/%[sdif]/) do |match|
              case match
              when "%s"
                arg.to_s
              when "%d", "%i"
                if int_val = arg.as?(Int64)
                  int_val.to_s
                elsif str_val = arg.to_s.to_i64?
                  str_val.to_s
                else
                  "0"
                end
              when "%f"
                if float_val = arg.as?(Float64)
                  float_val.to_s
                elsif str_val = arg.to_s.to_f64?
                  str_val.to_s
                else
                  "0.0"
                end
              else
                arg.to_s
              end
            end
          end
          result
        rescue
          value
        end
      end
    end
  end
end
