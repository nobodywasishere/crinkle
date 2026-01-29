require "./types"

module Jinja
  alias Number = Float64 | Int64 | Int32

  alias Value = (String | Number | Bool | Time | SafeString | Undefined | StrictUndefined | Jinja::Object | Array(Value) | Hash(String, Value) | Hash(Value, Value))?

  alias Dictionary = Hash(Value, Value)
  alias Variables = Hash(String, Value)

  def self.dictionary(object : Hash) : Dictionary
    Dictionary.new.tap do |dict|
      object.each do |key, value|
        dict[Jinja.value(key)] = Jinja.value(value)
      end
    end
  end

  def self.variables(object : Hash) : Variables
    Variables.new.tap do |variables|
      object.each do |k, v|
        variables[k.to_s] = Jinja.value(v)
      end
    end
  end

  def self.value(value : ::Object) : Value
    case value
    when Hash
      Jinja.dictionary(value)
    when NamedTuple
      dict = Dictionary.new
      value.each do |k, v|
        dict[Jinja.value(k.to_s)] = Jinja.value(v)
      end
      dict
    when ::Tuple
      items = Array(Value).new
      value.each { |item| items << Jinja.value(item) }
      items
    when Array
      items = Array(Value).new
      value.each { |item| items << Jinja.value(item) }
      items
    when Range
      items = Array(Value).new
      value.each { |item| items << Jinja.value(item) }
      items
    when Iterator
      items = Array(Value).new
      value.each { |item| items << Jinja.value(item) }
      items
    when Char
      value.to_s
    when Value
      value
    when Number, String, Bool, Time, SafeString, Undefined, StrictUndefined, Jinja::Object, Nil
      value
    else
      raise "type error: can't wrap #{value.class} in Jinja::Value"
    end
  end
end
