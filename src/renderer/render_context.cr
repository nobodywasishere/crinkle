module Crinkle
  # Forward declarations for types used in RenderContext
  class Environment; end

  class Renderer; end

  # RenderContext encapsulates the rendering state and provides access
  # to filters, tests, and functions that need to interact with the
  # current rendering environment.
  struct RenderContext
    getter env : Environment
    getter renderer : Renderer
    getter scope : Hash(String, Value)

    def initialize(@env : Environment, @renderer : Renderer, @scope : Hash(String, Value)) : Nil
    end

    # Access a context variable by key.
    # Returns the value if found, or Undefined if not.
    def [](key : String) : Value
      @scope[key]? || Undefined.new(key)
    end

    # Check if a key exists in the current scope.
    def has_key?(key : String) : Bool
      @scope.has_key?(key)
    end

    # Access a global variable by name.
    # Checks the environment's globals and parent chain.
    # Returns the value if found, or Undefined if not.
    def global(name : String) : Value
      @env.global(name)
    end

    # Check if a global variable exists in the environment or parent chain.
    def has_global?(name : String) : Bool
      @env.has_global?(name)
    end

    # Add a diagnostic from within a filter/test/function.
    def add_diagnostic(type : DiagnosticType, message : String, span : Span) : Nil
      @renderer.add_diagnostic(type, message, span)
    end
  end
end
