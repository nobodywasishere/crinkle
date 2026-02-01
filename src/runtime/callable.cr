require "./value"
require "./arguments"

module Crinkle
  # Base module for callable objects that can be invoked from templates.
  # Implementations must define the `call` method to handle invocation.
  module Callable
    abstract def call(arguments : Arguments) : Value
  end

  # Type alias for callable procs that take Arguments and return a Value.
  alias CallableProc = Arguments -> Value

  # A concrete implementation of Callable that wraps a proc.
  # This is the standard way to create callable objects in templates.
  #
  # Example:
  # ```
  # callable = CallableInstance.new(
  #   proc: ->(args : Arguments) {
  #     key = args.varargs[0]?.try(&.to_s) || ""
  #     Crinkle.value("translated: #{key}")
  #   },
  #   name: "localize"
  # )
  # ```
  class CallableInstance
    include Callable

    getter proc : CallableProc
    getter defaults : Hash(String, Value)
    getter name : String?

    def initialize(@proc : CallableProc, @defaults : Hash(String, Value) = Hash(String, Value).new, @name : String? = nil) : Nil
    end

    def call(arguments : Arguments) : Value
      @proc.call(arguments)
    end
  end
end
