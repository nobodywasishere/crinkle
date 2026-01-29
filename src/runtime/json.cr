require "json"
require "./value"
require "./object"

module Jinja
  def self.value(any : JSON::Any) : Value
    value(any.raw)
  end
end

struct JSON::Any
  include Jinja::Object

  def crinja_attribute(attr : Jinja::Value) : Jinja::Value
    result = nil
    if @raw.is_a?(Hash) || @raw.is_a?(Array)
      case attr
      when String
        result = self[attr]?
      when Jinja::SafeString
        result = self[attr.to_s]?
      when Int32
        result = self[attr]?
      when Int64
        result = self[attr.to_i]?
      end
    end
    result ||= Jinja::Undefined.new(attr.to_s)
    Jinja.value(result)
  end
end
