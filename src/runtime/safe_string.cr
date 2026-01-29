require "html"

module Crinkle
  struct SafeString
    def initialize(@string : String, @plain_value : Bool = false) : Nil
    end

    delegate :size, :to_i, :to_f, :to_s, :to_json, to: @string

    def inspect(io : IO) : Nil
      if @plain_value
        @string.to_s(io)
      else
        @string.inspect(io)
      end
    end

    def ==(other : (String | SafeString | Char | Number | Bool)?) : Bool
      @string == other
    end

    def [](index : Int) : Char
      @string[index]
    end

    def [](range : Range(Int32, Int32)) : SafeString
      result = @string[range]
      result.is_a?(String) ? SafeString.new(result) : result
    end

    def [](start : Int32, count : Int32) : SafeString
      result = @string[start, count]
      result.is_a?(String) ? SafeString.new(result) : result
    end

    def [](pattern : Regex) : SafeString?
      result = @string[pattern]
      result.is_a?(String) ? SafeString.new(result) : result
    end

    def []?(range : Range(Int32, Int32)) : SafeString?
      result = @string[range]?
      result.is_a?(String) ? SafeString.new(result) : result
    end

    def []?(start : Int32, count : Int32) : SafeString?
      result = @string[start, count]?
      result.is_a?(String) ? SafeString.new(result) : result
    end

    def []?(pattern : Regex) : SafeString?
      result = @string[pattern]?
      result.is_a?(String) ? SafeString.new(result) : result
    end

    def +(other : String | SafeString | Char) : SafeString
      result = @string + other.to_s
      other.is_a?(SafeString) ? SafeString.new(result) : result
    end

    # for literals such as numbers or booleans, will not be wrapped in quotes by inspect
    def self.plain(value : (String | Number | Bool)?) : SafeString
      new(value.to_s, true)
    end

    NIL = plain(nil)

    def self.escape(value : Value) : SafeString
      case value
      when Nil
        NIL
      when SafeString
        value
      when Number
        plain value.to_s
      when Array(Value)
        container = value.map { |v| escape(v).as(SafeString) }
        plain container.to_s
      when Hash
        hash = value.each_with_object(Hash(SafeString, SafeString).new) do |(k, v), memo|
          memo[escape(k)] = escape(v)
        end
        plain hash.to_s
      else
        new ::HTML.escape(value.to_s)
      end
    end

    # Yields a builder which automatically escapes.
    def self.escape(& : IO -> Nil) : SafeString
      string = String.build { |io| yield io }
      escape string
    end
  end
end

class String
  def ==(other : Crinkle::SafeString) : Bool
    other == self
  end
end
