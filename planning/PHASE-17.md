# Phase 17 — Environment Access in Filters/Functions (Detailed Plan)

## Objectives
- Enable custom filters and functions to access the rendering context.
- Allow filters to read context variables, environment settings, and renderer state.
- Maintain backward compatibility with existing filter signatures.

## Priority
**HIGH**

## Motivation
Custom functions need to access the current rendering context:
```crystal
# Example: Function that accesses context variable
env.register_function("asset_js_inline") do |args, kwargs, env, renderer|
  if (ctx = renderer.context["ctx"]?) && !ctx.is_a?(Undefined)
    nonce = get_attribute(ctx, "script_nonce")
  end
  # ... generate script tag with nonce
end
```

## Scope (Phase 17)
- Create `RenderContext` struct to encapsulate rendering state.
- Update `FilterProc` and `FunctionProc` aliases to include context.
- Update renderer to pass context when calling filters/functions.
- Update all existing filters and tests to accept new signature.

## API Design

### `RenderContext` Struct
```crystal
module Crinkle
  struct RenderContext
    getter env : Environment
    getter renderer : Renderer
    getter scope : Hash(String, Value)

    def initialize(@env, @renderer, @scope)
    end

    # Access current context variable
    def [](key : String) : Value
      @scope[key]? || Undefined.new(key)
    end
  end
end
```

### Updated Type Aliases
```crystal
module Crinkle
  # BEFORE
  # alias FilterProc = Proc(Value, Array(Value), Hash(String, Value), Value)
  # alias FunctionProc = Proc(Array(Value), Hash(String, Value), Value)

  # AFTER - Include render context
  alias FilterProc = Proc(Value, Array(Value), Hash(String, Value), RenderContext, Value)
  alias FunctionProc = Proc(Array(Value), Hash(String, Value), RenderContext, Value)
end
```

### Renderer Modifications
```crystal
private def call_filter(name : String, value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value
  if filter = @environment.filters[name]?
    ctx = RenderContext.new(@environment, self, current_scope)
    filter.call(value, args, kwargs, ctx)
  else
    emit_diagnostic(DiagnosticType::UnknownFilter, "Unknown filter '#{name}'", span)
    value
  end
end

private def call_function(name : String, args : Array(Value), kwargs : Hash(String, Value)) : Value
  if fn = @environment.functions[name]?
    ctx = RenderContext.new(@environment, self, current_scope)
    fn.call(args, kwargs, ctx)
  else
    emit_diagnostic(DiagnosticType::UnknownFunction, "Unknown function '#{name}'", span)
    Undefined.new(name)
  end
end
```

### Updated Filter Registrations
```crystal
# Filters that need context can use it:
@filters["safe"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value), ctx : RenderContext) : Value do
  # Could check ctx.env settings for autoescape mode
  SafeString.new(value.to_s)
end
```

## Example Usage
```crystal
# Custom function accessing context
env.register_function("current_user_name") do |args, kwargs, ctx|
  if user = ctx["user"]?
    user.is_a?(Crinkle::Object) ? get_attribute(user, "name") : Crinkle.value("Guest")
  else
    Crinkle.value("Guest")
  end
end

# Template usage:
# {{ current_user_name() }}
```

## Migration Strategy
1. Update type aliases in `environment.cr`.
2. Update all builtin filter implementations to accept 4th parameter.
3. Update all builtin test implementations similarly.
4. Update renderer to construct and pass `RenderContext`.
5. Document new API for custom filters/functions.

## Acceptance Criteria
- `RenderContext` provides access to environment, renderer, and current scope.
- All existing filters/tests updated to new signature without breaking.
- Custom filters can read context variables.
- Test specs pass.

## Checklist
- [ ] Create `RenderContext` struct (or equivalent)
- [ ] Update `FilterProc` alias to include context
- [ ] Update `FunctionProc` alias to include context
- [ ] Update `call_filter` to pass context
- [ ] Update `call_function` to pass context
- [ ] Update all existing filters to accept new signature
- [ ] Update all existing tests to accept new signature
- [ ] Add specs for context access in filters/functions
