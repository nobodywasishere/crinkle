# Phase 22 — LSP Semantic Bridge (Detailed Plan)

## Objectives
- Connect runtime semantic information to the LSP.
- Enable enhanced autocomplete, hover info, and validation.
- Bridge registered filters/tests/functions to LSP intelligence.

## Priority
**LOW** - Research/Experimentation

## Motivation
When Crinkle is used as a library, valuable semantic information exists at runtime:
- Registered custom filters, tests, and functions
- Context variable shapes and types
- Available macros and their signatures
- Template inheritance relationships
- Global variables and their values

The LSP currently operates in isolation, only seeing template source files. This phase explores ways to bridge runtime knowledge to the LSP.

## Approaches

### Approach 1: Schema/Manifest Files
Generate a static manifest describing the environment that the LSP reads.

```crystal
# In application code
env = Crinkle::Environment.new
env.register_filter("money_format") { |v, args, kwargs, ctx| ... }

# Generate manifest for LSP
env.export_schema("crinkle-schema.json")
```

```json
{
  "filters": {
    "money_format": {
      "signature": "(value, currency: string = \"USD\") -> string",
      "description": "Format a number as currency"
    }
  },
  "functions": {
    "asset_url": {
      "signature": "(path: string) -> string",
      "description": "Get CDN URL for an asset"
    }
  },
  "context": {
    "ctx": {
      "type": "RequestContext",
      "methods": ["localize", "flag", "redirected"],
      "attributes": ["user", "request", "session"]
    }
  }
}
```

**Pros:** Simple, no runtime coupling, works with any editor
**Cons:** Manual regeneration, can become stale, no live updates

### Approach 2: Development Server IPC
Run a lightweight server alongside the application that the LSP queries.

```crystal
# In application startup (dev mode only)
if Crinkle.dev_mode?
  Crinkle::DevServer.start(port: 9847)  # LSP connects here
end
```

**Pros:** Always current, live updates, rich information
**Cons:** Requires running app, port coordination, security considerations

### Approach 3: Crystal Source Analysis
Parse the Crystal source code to extract filter/test/function registrations.

**Pros:** No runtime needed, works from source
**Cons:** Complex to implement, limited type information, fragile

### Approach 4: Type Stub Files (`.crinkle.d.cr`)
Similar to TypeScript declaration files, define template context types.

```crystal
# templates/crinkle.d.cr - Type declarations for LSP
module Crinkle::Stubs
  context :global do
    var app_name : String
    var build_id : String
    func asset_url(path : String) : String
  end

  context "pages/user.html.j2" do
    var user : User
    var permissions : Array(String)
  end

  filter money_format(value : Number, currency : String = "USD") : String
end
```

**Pros:** Explicit, version controllable, IDE-friendly
**Cons:** Duplicate definitions, can drift from implementation

### Approach 5: Hybrid - Manifest + Hot Reload
Combine static manifests with optional live updates.

**Pros:** Best of both worlds
**Cons:** More complex implementation

### Approach 6: Template Annotations
Allow templates to declare their expected context.

```jinja
{#- @context
  user: User
  items: Array<Product>
  show_prices: bool = true
-#}
{% for item in items %}
  {{ item.name }}
{% endfor %}
```

**Pros:** Co-located with template, self-documenting
**Cons:** Verbose, requires discipline, no custom filter info

## Recommended Experiment Order
1. **Start with Approach 4 (Type Stubs)** - Low complexity, immediate value
2. **Add Approach 6 (Template Annotations)** - Per-template overrides
3. **Try Approach 1 (Manifest)** - Auto-generate from stubs + runtime
4. **Consider Approach 2 (Dev Server)** - If live updates prove valuable

## Acceptance Criteria
- Schema format defined and documented.
- LSP can load and use schema information.
- At least one approach prototyped and evaluated.
- Documentation for recommended patterns.

## Checklist
- [ ] Design schema format for environment description
- [ ] Implement `Environment#export_schema` method
- [ ] Create LSP schema loader
- [ ] Prototype type stub file parser (`.crinkle.d.cr`)
- [ ] Prototype template annotation parser (`{#- @context ... -#}`)
- [ ] Evaluate dev server approach (spike)
- [ ] Document recommended patterns for users
- [ ] Add schema validation (warn on drift from actual registrations)
