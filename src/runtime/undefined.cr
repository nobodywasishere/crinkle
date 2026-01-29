module Crinkle
  class Undefined
    getter name : String

    def initialize(@name : String = "") : Nil
    end

    def to_s(io : IO) : Nil
      # Undefined renders as an empty string.
    end

    def to_s : String
      ""
    end

    def to_json(io : IO) : Nil
      io << "null"
    end

    def size : Int32
      0
    end
  end

  class StrictUndefined < Undefined
    private def raise_error(method : String) : NoReturn
      display = @name.empty? ? "undefined" : @name
      raise "Undefined value '#{display}' accessed via #{method}"
    end

    def to_s(io : IO) : Nil
      raise_error("to_s")
    end

    def to_s : String
      raise_error("to_s")
    end

    def ==(other : Crinkle::Value) : Bool
      raise_error("==")
    end

    def <=>(other : Crinkle::Value) : Int32
      raise_error("<=>")
    end
  end
end
