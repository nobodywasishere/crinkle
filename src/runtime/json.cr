require "json"
require "./value"
require "./object"

module Crinkle
  def self.value(any : JSON::Any) : Value
    value(any.raw)
  end
end

struct JSON::Any
  include Crinkle::Object

  def crinja_attribute(attr : Crinkle::Value) : Crinkle::Value
    result = nil
    if @raw.is_a?(Hash) || @raw.is_a?(Array)
      case attr
      when String
        result = self[attr]?
      when Crinkle::SafeString
        result = self[attr.to_s]?
      when Int32
        result = self[attr]?
      when Int64
        result = self[attr.to_i]?
      end
    end
    result ||= Crinkle::Undefined.new(attr.to_s)
    Crinkle.value(result)
  end
end
