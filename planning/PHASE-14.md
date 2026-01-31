# Phase 14 — Callable Objects (Detailed Plan)

## Objectives
- Enable objects to expose callable methods for template invocation.
- Support method calls with positional and keyword arguments.
- Maintain compatibility with Crinja's `crinja_call` pattern.

## Priority
**CRITICAL** - Blocks Migration

## Motivation
Production applications need objects that expose callable methods, not just attributes:
```jinja
{{ ctx.localize("settings.title") }}           {# Call localize() with argument #}
{{ ctx.flag("feature_name") }}                  {# Call flag() with argument #}
{{ ctx.redirected("path", {"key": "val"}) }}   {# Call with multiple args #}
```

This is different from attribute access (`ctx.user`) - these are method invocations with arguments.

## Scope (Phase 14)
- Create `Callable` module and `CallableInstance` class.
- Create `Arguments` struct for argument handling.
- Add `crinja_call` method to `Object` module.
- Update renderer to check `crinja_call` before attribute access.

## File Structure
```
src/
  runtime/
    callable.cr      # Callable module and CallableInstance
    arguments.cr     # Arguments struct
  runtime/object.cr  # Modified to add crinja_call
  renderer/renderer.cr # Modified for callable invocation
  crinkle.cr         # Add requires
```

## API Design

### `src/runtime/callable.cr`
```crystal
module Crinkle
  module Callable
    abstract def call(arguments : Arguments) : Value
  end

  alias CallableProc = Arguments -> Value

  class CallableInstance
    include Callable

    getter proc : CallableProc
    getter defaults : Hash(String, Value)
    getter name : String?

    def initialize(@proc, @defaults = Hash(String, Value).new, @name = nil)
    end

    def call(arguments : Arguments) : Value
      @proc.call(arguments)
    end
  end
end
```

### `src/runtime/arguments.cr`
```crystal
module Crinkle
  struct Arguments
    getter varargs : Array(Value)
    getter kwargs : Hash(String, Value)
    getter defaults : Hash(String, Value)
    getter env : Environment
    getter target : Value?

    def initialize(
      @env : Environment,
      @varargs = Array(Value).new,
      @kwargs = Hash(String, Value).new,
      @defaults = Hash(String, Value).new,
      @target = nil
    )
    end

    def [](name : String) : Value
      if kwargs.has_key?(name)
        kwargs[name]
      elsif index = defaults.keys.index(name)
        varargs.size > index ? varargs[index] : (defaults[name]? || Undefined.new(name))
      else
        Undefined.new(name)
      end
    end

    def fetch(name : String, default : Value = Undefined.new(name)) : Value
      value = self[name]
      value.is_a?(Undefined) ? default : value
    end

    def target! : Value
      @target || raise "No target for callable"
    end

    def is_set?(name : String) : Bool
      kwargs.has_key?(name) ||
        (defaults.keys.index(name).try { |i| varargs.size > i } || false)
    end
  end
end
```

### Object Module Extension
```crystal
module Crinkle::Object
  def crinja_call(name : String) : Callable | CallableProc | Nil
    nil # Default: no callable methods
  end
end
```

### Renderer Modifications
```crystal
private def eval_method_call(obj : Value, method_name : String, args : Array(Value), kwargs : Hash(String, Value)) : Value
  if obj.is_a?(Crinkle::Object)
    if callable = obj.crinja_call(method_name)
      arguments = Arguments.new(env: @environment, varargs: args, kwargs: kwargs)
      return callable.call(arguments)
    end
  end
  eval_attribute(obj, method_name)
end
```

## Example Usage
```crystal
class MyContext
  include Crinkle::Object

  def crinja_attribute(attr : Crinkle::Value) : Crinkle::Value
    case attr.to_s
    when "name" then Crinkle.value("MyApp")
    else Crinkle::Undefined.new(attr.to_s)
    end
  end

  def crinja_call(name : String) : Crinkle::CallableProc?
    case name
    when "localize"
      ->(args : Crinkle::Arguments) {
        key = args.varargs[0]?.try(&.to_s) || ""
        Crinkle.value(translate(key))
      }
    when "flag"
      ->(args : Crinkle::Arguments) {
        flag_name = args.varargs[0]?.try(&.to_s) || ""
        Crinkle.value(check_flag(flag_name))
      }
    end
  end
end
```

## Test Fixtures
- `fixtures/std/callable_basic.html.j2` — Basic method call with argument
- `fixtures/std/callable_kwargs.html.j2` — Method call with keyword arguments
- `fixtures/std/callable_on_context.html.j2` — Multiple methods on context object

## Acceptance Criteria
- Objects can expose callable methods via `crinja_call`.
- Callable methods receive positional and keyword arguments.
- Renderer checks `crinja_call` before falling back to attribute access.
- Test fixtures pass for callable object scenarios.

## Checklist
- [ ] Create `src/runtime/callable.cr` with Callable module and CallableInstance
- [ ] Create `src/runtime/arguments.cr` with Arguments struct
- [ ] Add `crinja_call` method to `src/runtime/object.cr`
- [ ] Update renderer to check `crinja_call` before attribute access
- [ ] Add `require` statements to `src/crinkle.cr`
- [ ] Create test fixtures for callable objects
- [ ] Add specs for callable invocation
