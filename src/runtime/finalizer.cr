require "html"

module Jinja
  struct Finalizer
    def self.stringify(raw : Jinja::Value, escape : Bool = false, in_struct : Bool = false) : String
      String.build do |io|
        stringify(io, raw, escape, in_struct)
      end
    end

    def self.stringify(io : IO, raw : Jinja::Value, escape : Bool = false, in_struct : Bool = false) : Nil
      new(io, escape, in_struct).stringify(raw)
    end

    protected def initialize(@io : IO, @escape : Bool = false, @inside_struct : Bool = false) : Nil
    end

    protected def stringify(raw : Jinja::Value) : Nil
      raw.to_s(@io)
    end

    protected def stringify(raw : Nil) : Nil
      @io << "none"
    end

    protected def stringify(safe : SafeString) : Nil
      quote { safe.to_s(@io) }
    end

    protected def stringify(string : String) : Nil
      quote do
        if @escape
          ::HTML.escape(string).to_s(@io)
        else
          string.to_s(@io)
        end
      end
    end

    protected def stringify(array : Array) : Nil
      @inside_struct = true
      @io << "["
      array.join(@io, ", ") { |item| stringify(item) }
      @io << "]"
    end

    protected def stringify(hash : Hash) : Nil
      @inside_struct = true
      @io << "{"
      found_one = false
      hash.each do |key, value|
        @io << ", " if found_one
        stringify(key)
        @io << " => "
        stringify(value)
        found_one = true
      end
      @io << "}"
    end

    private def quote(&block : -> Nil) : Nil
      quotes = @inside_struct
      @io << '\'' if quotes
      block.call
      @io << '\'' if quotes
    end
  end
end
