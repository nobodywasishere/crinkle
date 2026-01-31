module Crinkle::Std::Filters
  module Strings
    def self.register(env : Environment) : Nil
      env.register_filter("upper") do |value, _args, _kwargs|
        value.to_s.upcase
      end

      env.register_filter("lower") do |value, _args, _kwargs|
        value.to_s.downcase
      end

      env.register_filter("capitalize") do |value, _args, _kwargs|
        str = value.to_s
        next str if str.empty?
        rest = str[1..]?
        str[0].upcase + (rest ? rest.downcase : "")
      end

      env.register_filter("trim") do |value, _args, _kwargs|
        value.to_s.strip
      end

      env.register_filter("truncate") do |value, args, kwargs|
        str = value.to_s
        length = args.first?.as?(Int64) || 255_i64
        killwords = kwargs["killwords"]?.as?(Bool) || false
        end_str = kwargs["end"]?.to_s || "..."

        next str if str.size <= length

        if killwords
          str[0...length] + end_str
        else
          # Find last space before length
          truncated = str[0...length]
          last_space = truncated.rindex(' ')
          if last_space
            truncated[0...last_space] + end_str
          else
            truncated + end_str
          end
        end
      end

      env.register_filter("replace") do |value, args, _kwargs|
        str = value.to_s
        old = args[0]?.to_s
        new = args[1]?.to_s
        str.gsub(old, new)
      end

      env.register_filter("title") do |value, _args, _kwargs|
        value.to_s.split(' ').map(&.capitalize).join(' ')
      end

      env.register_filter("wordcount") do |value, _args, _kwargs|
        value.to_s.split.size.to_i64
      end

      env.register_filter("reverse") do |value, _args, _kwargs|
        case value
        when String
          value.reverse
        when Array
          value.reverse
        else
          value
        end
      end

      env.register_filter("center") do |value, args, _kwargs|
        str = value.to_s
        width = args.first?.as?(Int64) || 80_i64
        str.center(width.to_i)
      end

      env.register_filter("indent") do |value, args, kwargs|
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
    end
  end
end
