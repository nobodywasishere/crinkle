# Phase 14 — Callable Objects (Detailed Plan)

## Objectives
- Enable objects to expose callable methods for template invocation.
- Support method calls with positional and keyword arguments.
- Maintain compatibility with Crinja's `jinja_call` pattern.

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
- Create `CallableProc` type alias for callable procs.
- Create `Arguments` struct for argument handling.
- Add `jinja_call` method to `Object` module.
- Update renderer to check `jinja_call` before attribute access.

## File Structure
```
src/
  runtime/
    callable.cr      # CallableProc type alias
    arguments.cr     # Arguments struct
  runtime/object.cr  # Modified to add jinja_call
  renderer/renderer.cr # Modified for callable invocation
  crinkle.cr         # Add requires
```

## API Design

### `src/runtime/callable.cr`
```crystal
module Crinkle
  # Simple type alias for callable procs
  alias CallableProc = Arguments -> Value
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
  def jinja_call(name : String) : CallableProc?
    nil # Default: no callable methods
  end
end
```

### Renderer Modifications
```crystal
# Inside eval_call method - check if callee is a method call on an object
if callee.is_a?(AST::GetAttr)
  target = eval_expr(callee.target)
  unless target.is_a?(Undefined) || target.is_a?(StrictUndefined)
    if target.responds_to?(:jinja_call)
      if callable = target.jinja_call(callee.name)
        arguments = Arguments.new(env: @environment, varargs: args, kwargs: kwargs, target: target)
        return callable.call(arguments)
      end
    end
  end
end
```

## Example Usage
```crystal
class MyContext
  include Crinkle::Object

  def jinja_attribute(attr : Crinkle::Value) : Crinkle::Value
    case attr.to_s
    when "name" then Crinkle.value("MyApp")
    else Crinkle::Undefined.new(attr.to_s)
    end
  end

  def jinja_call(name : String) : Crinkle::CallableProc?
    case name
    when "localize"
      ->(args : Crinkle::Arguments) : Crinkle::Value {
        key = args.varargs[0]?.try(&.to_s) || ""
        Crinkle.value(translate(key))
      }
    when "flag"
      ->(args : Crinkle::Arguments) : Crinkle::Value {
        flag_name = args.varargs[0]?.try(&.to_s) || ""
        Crinkle.value(check_flag(flag_name))
      }
    end
  end
end
```

## Test Fixtures
- `fixtures/std_callable/callable_basic.html.j2` — Basic method call with argument
- `fixtures/std_callable/callable_kwargs.html.j2` — Method call with keyword arguments
- `fixtures/std_callable/callable_on_context.html.j2` — Multiple methods on context object

## Acceptance Criteria
- Objects can expose callable methods via `jinja_call`.
- Callable methods receive positional and keyword arguments.
- Renderer checks `jinja_call` before falling back to attribute access.
- Test fixtures pass for callable object scenarios.

## Checklist
- [x] Create `src/runtime/callable.cr` with CallableProc type alias
- [x] Create `src/runtime/arguments.cr` with Arguments struct
- [x] Add `jinja_call` method to `src/runtime/object.cr`
- [x] Update renderer to check `jinja_call` before attribute access
- [x] Create test fixtures for callable objects
- [x] Add specs for callable invocation

## Implementation Notes

### Design Simplification (Post-Implementation)

The initial design included three types:
- `Callable` module (abstract interface with `call` method)
- `CallableInstance` class (wrapper with metadata: proc, defaults, name)
- `CallableProc` type alias (`Arguments -> Value`)

The return type was `(Callable | CallableProc)?`, and the renderer handled both with a case statement:
```crystal
case callable
when Callable
  return callable.call(arguments)
when CallableProc
  return callable.call(arguments)  # Identical!
end
```

**Problem:** Both branches were identical because procs already have a `.call` method. The `CallableInstance` class was never used - it existed for potential future metadata support (defaults, name), but these features weren't needed since:
- Arguments already handles defaults via the `defaults` hash
- Method names are passed as strings to `jinja_call`

**Simplification:** Removed `Callable` module and `CallableInstance` class, keeping only `CallableProc` as a simple type alias. Benefits:
- Simpler API: `jinja_call` returns `CallableProc?` instead of union type
- Less code: No unused wrapper class or abstract interface
- Single code path in renderer: Direct proc call instead of case statement
- Clear intent: Users return procs directly from `jinja_call`

All 203 specs pass with the simplified design.
