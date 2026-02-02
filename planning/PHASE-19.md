# Phase 19 — Context Inheritance (Detailed Plan)

## Objectives
- Support global/per-request context patterns.
- Enable environment inheritance for shared configuration.
- Avoid duplicating filters/tests/functions across requests.

## Priority
**MEDIUM**

## Motivation
Production apps often have global context (app config, build ID) and per-request context (user, session):

```crystal
# Global context - shared across all requests
GLOBAL_ENV = Crinkle::Environment.new.tap do |env|
  env.globals["app_name"] = Crinkle.value("MyApp")
  env.globals["build_id"] = Crinkle.value("abc123")
end

# Per-request - inherits from global, adds request-specific vars
request_env = GLOBAL_ENV.new_child
request_env.context["ctx"] = Crinkle.value(request_context)
request_env.context["user"] = Crinkle.value(current_user)
```

## Scope (Phase 19)
- Add `parent` property to Environment.
- Add `globals` hash for environment-level variables.
- Implement `new_child` method for environment inheritance.
- Update renderer for parent scope lookup.

## API Design

### Environment Modifications
```crystal
class Environment
  getter parent : Environment?
  getter globals : Hash(String, Value)

  def initialize(
    @parent : Environment? = nil,
    # ... other params
  ) : Nil
    @globals = Hash(String, Value).new
    # ... rest of init
  end

  # Create child environment that inherits from this one
  def new_child : Environment
    child = Environment.new(parent: self)
    # Child inherits filters, tests, functions, loader
    child.filters.merge!(@filters)
    child.tests.merge!(@tests)
    child.functions.merge!(@functions)
    child.template_loader = @template_loader
    child
  end

  # Look up global variable (checks self, then parent chain)
  def global(name : String) : Value
    @globals[name]? || @parent.try(&.global(name)) || Undefined.new(name)
  end
end
```

### Renderer Modifications
```crystal
class Renderer
  private def lookup_variable(name : String) : Value
    # Check local scopes first
    @scopes.reverse_each do |scope|
      if scope.has_key?(name)
        return scope[name]
      end
    end

    # Check environment globals
    @environment.global(name)
  end
end
```

## Alternative: Context Class
Instead of environment inheritance, use a Context class:

```crystal
class Context
  getter parent : Context?
  @variables : Hash(String, Value)

  def initialize(@parent = nil)
    @variables = Hash(String, Value).new
  end

  def []=(key : String, value : Value)
    @variables[key] = value
  end

  def [](key : String) : Value
    @variables[key]? || @parent.try(&.[key]) || Undefined.new(key)
  end

  def merge!(other : Hash(String, Value))
    @variables.merge!(other)
  end

  def new_child : Context
    Context.new(parent: self)
  end
end
```

## Example Usage
```crystal
# Setup global environment
global_env = Crinkle::Environment.new
global_env.globals["app"] = Crinkle.value("MyApp")
global_env.set_loader { |n| File.read("templates/#{n}") }

# Per-request
def handle_request(request)
  env = global_env.new_child
  context = Crinkle.variables({
    "ctx" => request_context,
    "user" => current_user
  })
  env.render("page.html.j2", context)
end
```

## Acceptance Criteria
- Child environments inherit filters, tests, functions from parent.
- Global variables accessible through inheritance chain.
- Per-request context doesn't pollute global environment.
- Template caching works correctly with inheritance.

## Checklist
- [x] Add `parent` property to Environment
- [x] Add `globals` hash to Environment
- [x] Add `new_child` method to Environment
- [x] Update Renderer to check parent globals
- [x] Add specs for context inheritance
