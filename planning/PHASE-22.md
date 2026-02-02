# Phase 22 — Typed Registration Macros ✅

**Status:** COMPLETE

## Objectives
- Provide macros for defining filters/tests/functions/callables with type metadata.
- Enable schema extraction from compiled binaries.
- Single source of truth: one definition for runtime + schema.

## Priority
**MEDIUM** - Enables signature-aware linting and LSP intelligence

## Motivation

Currently, filters/tests/functions are registered with blocks that have no type information:

```crystal
env.register_filter("money_format") { |value, args, kwargs, ctx|
  # Implementation - but what types does this expect?
}
```

This makes it impossible for tooling to validate argument counts, check keyword argument names, or provide accurate autocomplete.

## Design Principle: Single Source of Truth

The macro defines BOTH the runtime behavior AND the schema metadata in one place:

```crystal
Crinkle.define_filter :money_format,
  params: {value: Number, currency: String},
  defaults: {currency: "USD"},
  returns: String,
  doc: "Format a number as currency" do |value, currency|
  sprintf("$%.2f", value)
end
```

This generates:
1. Runtime filter registration (what actually executes)
2. Schema entry embedded in the binary (extractable for tooling)

## API Design

### Filter Registration

```crystal
# Minimal - just name and implementation
Crinkle.define_filter :upcase do |value|
  value.to_s.upcase
end

# With typed parameters
Crinkle.define_filter :truncate,
  params: {value: String, length: Int32},
  defaults: {length: 80},
  returns: String do |value, length|
  value.size > length ? value[0...length] + "..." : value
end

# With full metadata
Crinkle.define_filter :money_format,
  params: {value: Number, currency: String, locale: String},
  defaults: {currency: "USD", locale: "en"},
  returns: String,
  doc: "Format a number as currency",
  examples: [
    {input: "{{ 1234.5 | money_format }}", output: "$1,234.50"},
  ],
  deprecated: false do |value, currency, locale|
  # Implementation
end
```

### Test Registration

```crystal
Crinkle.define_test :divisible_by,
  params: {value: Number, divisor: Number},
  doc: "Check if value is divisible by divisor" do |value, divisor|
  (value % divisor) == 0
end
```

### Function Registration

```crystal
Crinkle.define_function :asset_url,
  params: {path: String, version: Bool},
  defaults: {version: true},
  returns: String,
  doc: "Get CDN URL for a static asset" do |path, version|
  base = "https://cdn.example.com/#{path}"
  version ? "#{base}?v=#{BUILD_ID}" : base
end
```

### Callable Object Registration

Objects with `jinja_call` methods (see Phase 14) can expose multiple callable methods.

**Architecture:**
- `jinja_call(method, args, kwargs)` is the low-level dispatch method (can be overridden for full control)
- `define_callable` macros generate schema AND implementations that route through `jinja_call`
- Default call (`{{ obj() }}`) is optional - objects can have only named methods

```crystal
class Formatter
  include Crinkle::Callable

  # Named method: {{ formatter.price(100, currency="EUR") }}
  Crinkle.define_method :price,
    params: {value: Number, currency: String},
    defaults: {currency: "USD"},
    returns: String,
    doc: "Format as currency" do |value, currency|
    sprintf("$%.2f %s", value, currency)
  end

  # Named method: {{ formatter.date(now, format="%Y-%m-%d") }}
  Crinkle.define_method :date,
    params: {value: Time, format: String},
    defaults: {format: "%Y-%m-%d"},
    returns: String,
    doc: "Format a date" do |value, format|
    value.to_s(format)
  end

  # Optional: default call {{ formatter(100) }}
  Crinkle.define_default_call,
    params: {value: Number},
    returns: String,
    doc: "Default format" do |value|
    value.to_s
  end
end
```

**Template usage:**
```jinja
{{ formatter.price(100) }}                 {# Named method #}
{{ formatter.price(100, currency="EUR") }} {# With kwargs #}
{{ formatter.date(now) }}                  {# Another method #}
{{ formatter(100) }}                       {# Default call (if defined) #}
```

**Low-level override (no macros):**

For full control, override `jinja_call` directly. No schema is generated - tooling won't validate these calls:

```crystal
class CustomFormatter
  include Crinkle::Callable

  # Low-level dispatch - handles all calls
  def jinja_call(method : Symbol?, args : Array, kwargs : Hash) : Crinkle::Value
    case method
    when nil      then default_format(args, kwargs)  # {{ obj() }}
    when :price   then format_price(args, kwargs)    # {{ obj.price() }}
    when :date    then format_date(args, kwargs)     # {{ obj.date() }}
    else
      raise "Unknown method: #{method}"
    end
  end

  private def default_format(args, kwargs)
    # ...
  end
end
```

**Annotation-based approach:**

```crystal
class Formatter
  include Crinkle::Callable

  @[Crinkle::Method(
    params: {value: Number, currency: String},
    defaults: {currency: "USD"},
    returns: String,
    doc: "Format as currency"
  )]
  def price(value, currency = "USD")
    sprintf("$%.2f %s", value, currency)
  end

  @[Crinkle::Method(
    params: {value: Time, format: String},
    defaults: {format: "%Y-%m-%d"},
    returns: String,
    doc: "Format a date"
  )]
  def date(value, format = "%Y-%m-%d")
    value.to_s(format)
  end

  # Optional default call
  @[Crinkle::DefaultCall(
    params: {value: Number},
    returns: String,
    doc: "Default format"
  )]
  def call(value)
    value.to_s
  end
end
```

The annotation approach auto-generates `jinja_call` dispatch from annotated methods.

### Context Capture (Render Calls)

```crystal
# Macro captures context shape at compile time
Crinkle.render("user.html.j2", {
  user: current_user,       # Captured as User type
  permissions: user_perms,  # Captured as Array(String)
})
# Schema records: user.html.j2 expects {user: User, permissions: Array(String)}
```

## Schema Format

### Embedded Schema

```crystal
module Crinkle::Schema
  FILTERS = {
    "money_format" => FilterSchema.new(
      name: "money_format",
      params: [
        ParamSchema.new(name: "value", type: "Number", required: true),
        ParamSchema.new(name: "currency", type: "String", required: false, default: "USD"),
      ],
      returns: "String",
      doc: "Format a number as currency",
      deprecated: false,
    ),
  }
  TESTS = { ... }
  FUNCTIONS = { ... }
  CALLABLES = {
    "Formatter" => CallableSchema.new(
      class_name: "Formatter",
      # default_call is optional - nil if not defined
      default_call: MethodSchema.new(
        params: [ParamSchema.new(name: "value", type: "Number", required: true)],
        returns: "String",
        doc: "Default format",
      ),
      methods: {
        "price" => MethodSchema.new(
          params: [
            ParamSchema.new(name: "value", type: "Number", required: true),
            ParamSchema.new(name: "currency", type: "String", required: false, default: "USD"),
          ],
          returns: "String",
          doc: "Format as currency",
        ),
        "date" => MethodSchema.new(
          params: [
            ParamSchema.new(name: "value", type: "Time", required: true),
            ParamSchema.new(name: "format", type: "String", required: false, default: "%Y-%m-%d"),
          ],
          returns: "String",
          doc: "Format a date",
        ),
      },
    ),
    # Example without default_call - methods only
    "DateHelper" => CallableSchema.new(
      class_name: "DateHelper",
      default_call: nil,  # Not directly callable
      methods: {
        "format" => MethodSchema.new(...),
        "parse" => MethodSchema.new(...),
      },
    ),
  }
  TEMPLATES = { ... }
end
```

### JSON Export

```json
{
  "version": 1,
  "filters": {
    "money_format": {
      "params": [
        {"name": "value", "type": "Number", "required": true},
        {"name": "currency", "type": "String", "required": false, "default": "USD"}
      ],
      "returns": "String",
      "doc": "Format a number as currency",
      "deprecated": false
    }
  },
  "tests": { },
  "functions": { },
  "callables": {
    "Formatter": {
      "class_name": "Formatter",
      "default_call": {
        "params": [{"name": "value", "type": "Number", "required": true}],
        "returns": "String",
        "doc": "Default format"
      },
      "methods": {
        "price": {
          "params": [
            {"name": "value", "type": "Number", "required": true},
            {"name": "currency", "type": "String", "required": false, "default": "USD"}
          ],
          "returns": "String",
          "doc": "Format as currency"
        },
        "date": {
          "params": [
            {"name": "value", "type": "Time", "required": true},
            {"name": "format", "type": "String", "required": false, "default": "%Y-%m-%d"}
          ],
          "returns": "String",
          "doc": "Format a date"
        }
      }
    },
    "DateHelper": {
      "class_name": "DateHelper",
      "default_call": null,
      "methods": {
        "format": { "params": [...], "returns": "String" },
        "parse": { "params": [...], "returns": "Time" }
      }
    }
  },
  "templates": {
    "user.html.j2": {
      "context": {
        "user": "User",
        "permissions": "Array(String)"
      }
    }
  }
}
```

## Schema Extraction

### Command-Line Flag

```crystal
# In application entry point
if ARGV.includes?("--crinkle-schema")
  puts Crinkle::Schema.to_json
  exit 0
end
```

Usage:
```bash
$ ./myapp --crinkle-schema > .crinkle/schema.json
```

### Build Integration

```makefile
schema: build
	./bin/myapp --crinkle-schema > .crinkle/schema.json

check-schema: build
	./bin/myapp --crinkle-schema > /tmp/schema.json
	diff -q .crinkle/schema.json /tmp/schema.json || (echo "Schema out of date" && exit 1)
```

## Migration Guide

### From Block-Based Registration

Before:
```crystal
env.register_filter("money_format") { |value, args, kwargs, ctx|
  currency = kwargs["currency"]?.try(&.as_s) || "USD"
  # ...
}
```

After:
```crystal
Crinkle.define_filter :money_format,
  params: {value: Number, currency: String},
  defaults: {currency: "USD"},
  returns: String do |value, currency|
  # Direct access to typed parameters
end
```

### Gradual Migration

Both registration styles can coexist:
- Block-based filters work at runtime but have no schema
- Macro-based filters appear in schema with full metadata

## Acceptance Criteria

- [x] `Crinkle.define_filter` macro implemented
- [x] `Crinkle.define_test` macro implemented
- [x] `Crinkle.define_function` macro implemented
- [x] `Crinkle.define_callable` macro implemented (via `@[Crinkle::Method]` annotations)
- [ ] `Crinkle.render` captures context types (deferred)
- [x] Schema embedded as compile-time constant
- [x] `--crinkle-schema` flag outputs JSON (via `crinkle schema` command)
- [x] Migration guide documented (in PHASE-22.md)

## Checklist

### Macro Implementation
- [x] Design macro API (params, defaults, returns, doc, etc.)
- [x] Implement `define_filter` macro
- [x] Implement `define_test` macro
- [x] Implement `define_function` macro
- [x] Implement `define_method` macro (via `@[Crinkle::Method]` annotations)
- [x] Implement `define_default_call` macro (via `@[Crinkle::DefaultCall]` annotations)
- [x] Auto-generate `jinja_call` dispatch from macros
- [x] Consider `@[Crinkle::Method]` / `@[Crinkle::DefaultCall]` annotations
- [ ] Handle variadic parameters (deferred)
- [x] Support deprecation marking

### Schema System
- [x] Define `FilterSchema`, `TestSchema`, `FunctionSchema`, `CallableSchema` types
- [x] Define `MethodSchema` type (for callable methods)
- [x] Define `ParamSchema` type
- [x] Implement schema aggregation at compile time
- [x] Implement JSON serialization
- [x] Add `--crinkle-schema` CLI flag (via `crinkle schema` command)
- [x] Document schema format

### Context Capture
- [ ] Implement `Crinkle.render` macro variant (deferred)
- [ ] Capture template path → context type mapping (deferred)
- [ ] Handle dynamic template paths (warn/skip) (deferred)

## Open Questions

1. **Type syntax:** Crystal types vs. simplified type language?
   - Proposal: Use Crystal types, they're familiar to users

2. **Variadic handling:** How to express `*args` in schema?
   - Proposal: `variadic: true` flag, type applies to each arg

3. **Union types:** How to handle `String | Int32`?
   - Proposal: Support Crystal union syntax in type field

4. **Backward compatibility:** Keep block-based registration?
   - Proposal: Yes, macros are opt-in enhancement
