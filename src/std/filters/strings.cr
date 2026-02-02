module Crinkle::Std::Filters
  module Strings
    Crinkle.define_filter :upper,
      params: {value: String},
      returns: String,
      doc: "Convert string to uppercase" do |value|
      value.to_s.upcase
    end

    Crinkle.define_filter :lower,
      params: {value: String},
      returns: String,
      doc: "Convert string to lowercase" do |value|
      value.to_s.downcase
    end

    Crinkle.define_filter :capitalize,
      params: {value: String},
      returns: String,
      doc: "Capitalize first character of string" do |value|
      str = value.to_s
      if str.empty?
        str
      else
        rest = str[1..]?
        str[0].upcase + (rest ? rest.downcase : "")
      end
    end

    Crinkle.define_filter :trim,
      params: {value: String},
      returns: String,
      doc: "Strip leading and trailing whitespace" do |value|
      value.to_s.strip
    end

    Crinkle.define_filter :truncate,
      params: {value: String, length: Int64, killwords: Bool, end_str: String, leeway: Int64},
      defaults: {length: 255_i64, killwords: false, end_str: "...", leeway: 0_i64},
      returns: String,
      doc: "Truncate string to specified length" do |value, length, killwords, end_str, leeway|
      str = value.to_s
      length = length.as?(Int64) || 255_i64
      killwords = killwords.as?(Bool) || false
      end_str = end_str.to_s.empty? ? "..." : end_str.to_s
      leeway = leeway.as?(Int64) || 0_i64

      if str.size <= length + leeway
        str
      elsif killwords
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

    Crinkle.define_filter :replace,
      params: {value: String, old: String, new_str: String, count: Int64},
      defaults: {count: nil},
      returns: String,
      doc: "Replace occurrences of a substring" do |value, old, new_str, count|
      str = value.to_s

      if old.is_a?(Undefined) || new_str.is_a?(Undefined)
        str
      else
        old = old.to_s
        new_str = new_str.to_s
        count_val = count

        if count_val.is_a?(Int64)
          result = str
          count_val.times { result = result.sub(old, new_str) }
          result
        else
          str.gsub(old, new_str)
        end
      end
    end

    Crinkle.define_filter :title,
      params: {value: String},
      returns: String,
      doc: "Convert string to title case" do |value|
      value.to_s.split(' ').map(&.capitalize).join(' ')
    end

    Crinkle.define_filter :wordcount,
      params: {value: String},
      returns: Int64,
      doc: "Count words in string" do |value|
      value.to_s.split.size.to_i64
    end

    Crinkle.define_filter :reverse,
      params: {value: Any},
      returns: Any,
      doc: "Reverse a string or list" do |value|
      case value
      when String
        value.reverse
      when Array
        value.reverse
      else
        value
      end
    end

    Crinkle.define_filter :center,
      params: {value: String, width: Int64},
      defaults: {width: 80_i64},
      returns: String,
      doc: "Center string in field of given width" do |value, width|
      str = value.to_s
      width = width.as?(Int64) || 80_i64
      str.center(width.to_i)
    end

    Crinkle.define_filter :indent,
      params: {value: String, width: Int64, first: Bool},
      defaults: {width: 4_i64, first: false},
      returns: String,
      doc: "Indent lines with spaces" do |value, width, first|
      str = value.to_s
      width = width.as?(Int64) || 4_i64
      first = first.as?(Bool) || false

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

    Crinkle.define_filter :format,
      params: {value: String},
      returns: String,
      doc: "Apply printf-style formatting" do |value|
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

    def self.register(env : Environment) : Nil
      register_filter_upper(env)
      register_filter_lower(env)
      register_filter_capitalize(env)
      register_filter_trim(env)
      register_filter_truncate(env)
      register_filter_replace(env)
      register_filter_title(env)
      register_filter_wordcount(env)
      register_filter_reverse(env)
      register_filter_center(env)
      register_filter_indent(env)
      register_filter_format(env)
    end
  end
end
