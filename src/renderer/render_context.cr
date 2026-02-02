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
  end
end
