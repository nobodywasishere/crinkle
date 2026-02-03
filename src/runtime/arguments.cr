module Crinkle
  # Represents arguments passed to a callable object from a template.
  # Handles both positional arguments (varargs) and keyword arguments (kwargs),
  # with support for default values and target binding.
  #
  # Example:
  # ```
  # args = Arguments.new(
  #   env: environment,
  #   varargs: [Crinkle.value("key")],
  #   kwargs: {"default" => Crinkle.value("fallback")}
  # )
  # key = args.varargs[0]     # First positional argument
  # default = args["default"] # Keyword argument by name
  # ```
  struct Arguments
    getter varargs : Array(Value)
    getter kwargs : Hash(String, Value)
    getter defaults : Hash(String, Value)
    getter env : Environment
    getter target : Value?

    def initialize(
      @env : Environment,
      @varargs : Array(Value) = Array(Value).new,
      @kwargs : Hash(String, Value) = Hash(String, Value).new,
      @defaults : Hash(String, Value) = Hash(String, Value).new,
      @target : Value? = nil,
    ) : Nil
    end

    # Access an argument by name, checking kwargs first, then defaults.
    # Returns Undefined if the argument is not found.
    def [](name : String) : Value
      if kwargs.has_key?(name)
        kwargs[name]
      elsif index = defaults.keys.index(name)
        varargs.size > index ? varargs[index] : (defaults[name]? || Undefined.new(name))
      else
        Undefined.new(name)
      end
    end

    # Fetch an argument by name with a default fallback value.
    # Unlike `[]`, this returns the provided default instead of Undefined.
    def fetch(name : String, default : Value = Undefined.new(name)) : Value
      value = self[name]
      value.is_a?(Undefined) ? default : value
    end

    # Get the target value, raising an error if it's not set.
    # Used when the callable requires a bound target object.
    def target! : Value
      @target || raise "No target for callable"
    end

    # Check if an argument is set (present in kwargs or varargs).
    def set?(name : String) : Bool
      kwargs.has_key?(name) ||
        (defaults.keys.index(name).try { |i| varargs.size > i } || false)
    end
  end
end
