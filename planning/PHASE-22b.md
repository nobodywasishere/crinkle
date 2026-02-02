# Phase 22b — LSP Semantic Features

## Objectives
- Integrate schema into LSP for completions, hover, and signature help.
- Add inference engine for zero-config property completions.
- Optional: Dev server IPC for live updates.

## Priority
**LOW** - Enhanced developer experience

## Motivation

With the schema from Phase 22 and linting from Phase 22a, the LSP can provide rich IDE features:

- Filter/test/function completions with signatures
- Hover documentation
- Signature help for function calls
- Property completions from template usage (inference)

## Project Configuration

```yaml
# .crinkle/config.yaml
version: 1

# Where to find templates
template_paths:
  - templates/
  - app/views/

# Schema location (from Phase 22)
schema:
  path: .crinkle/schema.json
  watch: true

# Inference settings
inference:
  enabled: true
  cross_template: true  # Infer from extends/include

# Dev server (optional)
dev_server:
  discover: .crinkle/server.lock
  fallback_socket: /tmp/crinkle-dev.sock
```

## Schema-Based Features

### Filter/Test/Function Completions

```
{{ price | m█ }}
         ↓
  money_format  - Format a number as currency
  map           - Apply expression to each item
  max           - Return maximum value
```

Completions show:
- Name
- Brief description from schema
- Signature preview

### Hover Information

```
{{ price | money_format(currency: "EUR") }}
           ^^^^^^^^^^^^
┌─────────────────────────────────────────┐
│ money_format(value: Number,             │
│              currency: String = "USD",  │
│              locale: String = "en")     │
│              -> String                  │
│                                         │
│ Format a number as currency             │
└─────────────────────────────────────────┘
```

### Signature Help

```
{{ price | money_format(█) }}
                        ↓
  money_format(value: Number, currency: String = "USD", locale: String = "en")
                              ^^^^^^^^
  currency - The currency code (default: "USD")
```

Triggered on `(` and `,` within filter/function calls.

## Inference Engine

Zero-config property completions from template usage patterns.

### How It Works

```jinja
{% for item in items %}
  {{ item.name }}
  {{ item.price }}
{% endfor %}
{{ user.email }}
```

The LSP infers:
- `items` is iterable with elements having `.name` and `.price`
- `user` has property `.email`

### Property Completions

```jinja
{{ user.█ }}
        ↓
  email      (inferred from line 5)
  name       (inferred from line 12)
  created_at (inferred from line 18)
```

### Inference Rules

| Pattern | Inference |
|---------|-----------|
| `{% for x in items %}` | `items` is iterable, `x` is element |
| `{{ obj.prop }}` | `obj` has property `prop` |
| `{% set x = expr %}` | `x` has type/properties of `expr` |
| `{% if cond %}` | `cond` is truthy-testable |
| `{{ x \| filter }}` | `x` is filter input type |

### Cross-Template Inference

```jinja
{# base.html.j2 #}
{{ page_title }}
{% block content %}{% endblock %}

{# child.html.j2 #}
{% extends "base.html.j2" %}
{# LSP knows: page_title is required #}
```

Templates connected via `extends`/`include`/`import` share inferred context.

### Typo Detection

```jinja
{{ user.email }}   {# Used elsewhere #}
{{ user.emial }}   {# Likely typo #}
```

**Warning:** Unknown property 'emial' on 'user'. Did you mean 'email'?

## Dev Server IPC (Optional)

For live updates without regenerating schema.

### Protocol

JSON-RPC over Unix socket:

```json
// Request
{"jsonrpc": "2.0", "method": "getFilters", "id": 1}

// Response
{"jsonrpc": "2.0", "result": {"filters": {...}}, "id": 1}
```

### Methods

- `getFilters` - List registered filters with signatures
- `getTests` - List registered tests
- `getFunctions` - List registered functions
- `getContext(template)` - Get context for a template

### Discovery

```yaml
# .crinkle/config.yaml
dev_server:
  discover: .crinkle/server.lock  # App writes socket path here
```

The app writes its socket path to the lock file on startup.

### Graceful Degradation

```
LSP starts
├─ Try to connect to dev server
│   ├─ Connected → Use live data
│   └─ Not connected → Fall back
├─ Load .crinkle/schema.json
│   ├─ Found → Use for filters/tests/functions
│   └─ Not found → Built-in Jinja2 only
└─ Run inference engine
    └─ Property suggestions from usage
```

## Implementation

### Schema Loader (shared with linter)

```crystal
class Crinkle::LSP::SchemaProvider
  def initialize(@config : Config)
    @schema = load_schema
    @inference = InferenceEngine.new
    @dev_server = connect_dev_server if @config.dev_server?
  end

  def filters : Hash(String, FilterSchema)
    @dev_server.try(&.filters) || @schema.filters
  end

  def context_for(template : String) : Hash(String, String)
    # Merge: schema context + inferred context
    schema_ctx = @schema.templates[template]?.try(&.context) || {}
    inferred_ctx = @inference.context_for(template)
    schema_ctx.merge(inferred_ctx)
  end
end
```

### Inference Engine

```crystal
class Crinkle::InferenceEngine
  # template -> variable -> [properties]
  @usage : Hash(String, Hash(String, Set(String)))

  def analyze(template : String, ast : AST::Template)
    visitor = UsageVisitor.new
    ast.accept(visitor)
    @usage[template] = visitor.properties
  end

  def properties_for(template : String, variable : String) : Array(String)
    @usage[template]?.try(&.[variable]?.try(&.to_a)) || [] of String
  end
end
```

## Acceptance Criteria

### Schema Integration
- [ ] LSP loads schema from `.crinkle/schema.json`
- [ ] Filter/test/function completions with signatures
- [ ] Hover shows documentation and signature
- [ ] Signature help on `(` and `,`

### Inference
- [ ] Property tracking from template usage
- [ ] Property completions after `.`
- [ ] Cross-template inference via extends/include
- [ ] Typo detection with suggestions

### Configuration
- [ ] `.crinkle/config.yaml` loader
- [ ] File watcher for config/schema changes
- [ ] Graceful defaults without config

### Dev Server (Optional)
- [ ] JSON-RPC protocol defined
- [ ] Socket discovery mechanism
- [ ] Connection with auto-reconnect
- [ ] Graceful fallback

## Checklist

### Configuration
- [ ] Define `.crinkle/config.yaml` format
- [ ] Implement config loader
- [ ] File watcher for config changes

### Schema Integration
- [ ] Load schema (reuse from Phase 22a)
- [ ] Filter completions with signatures
- [ ] Test completions
- [ ] Function completions
- [ ] Hover for filters/tests/functions
- [ ] Signature help provider

### Inference Engine
- [ ] Template AST visitor for usage extraction
- [ ] Property map per variable
- [ ] Track variable origins (for loop, set, macro)
- [ ] Cross-template analysis
- [ ] Property completions provider
- [ ] Typo detection (Levenshtein)

### Dev Server (Optional)
- [ ] Define JSON-RPC protocol
- [ ] Implement `Crinkle::DevServer` module
- [ ] Socket discovery
- [ ] LSP client connection
- [ ] Rate limiting

## Dependencies

- **Phase 22**: Schema generation
- **Phase 22a**: Schema loading (shared code)
- **Phase 21**: LSP diagnostics infrastructure

## Open Questions

1. **Inference confidence:** Show inferred vs. declared differently?
   - Proposal: Subtle UI distinction (italic for inferred)

2. **Cross-template scope:** How far to follow includes?
   - Proposal: One level deep, configurable

3. **Dev server security:** Prevent malicious templates from exploiting?
   - Proposal: Read-only queries, localhost only, rate limiting
