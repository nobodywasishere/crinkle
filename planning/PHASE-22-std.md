# Phase 22-std — Standard Library Typed Registration

## Goal
Migrate all standard library filters, tests, and functions to use the typed registration macros from Phase 22, populating the global schema registry.

## Why Now
- Phase 22 created the macro infrastructure
- Phase 22a (Schema-Aware Linting) needs the schema populated to validate template usage
- Phase 22b (LSP Semantic Features) needs the schema for completions/hover
- This is the bridge between the infrastructure and its consumers

## Scope

### Filters to Migrate
All filters in `src/std/filters/`:
- **strings.cr**: `upper`, `lower`, `title`, `capitalize`, `trim`, `striptags`, `escape`, `safe`, `default`, `replace`, `truncate`, `wordwrap`, `center`, `ljust`, `rjust`, `format`, `indent`, `wordcount`
- **lists.cr**: `join`, `first`, `last`, `length`, `reverse`, `sort`, `unique`, `map`, `select`, `reject`, `batch`, `slice`, `groupby`, `dictsort`, `rejectattr`, `selectattr`, `list`, `items`, `attr`, `tojson`
- **numbers.cr**: `abs`, `int`, `float`, `round`, `filesizeformat`, `sum`, `max`, `min`
- **html.cr**: `e`, `forceescape`, `urlencode`, `xmlattr`
- **serialize.cr**: `pprint`, `tojson`

### Tests to Migrate
All tests in `src/std/tests/`:
- **types.cr**: `defined`, `undefined`, `none`, `boolean`, `true`, `false`, `integer`, `float`, `number`, `string`, `mapping`, `iterable`, `sequence`, `callable`
- **comparison.cr**: `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `sameas`, `in`, `even`, `odd`, `divisibleby`
- **strings.cr**: `lower`, `upper`, `filter`, `test`

### Functions to Migrate
All functions in `src/std/functions/`:
- **range.cr**: `range`
- **dict.cr**: `dict`
- **namespace.cr**: `namespace`
- **cycler.cr**: `cycler`
- **joiner.cr**: `joiner`
- **lipsum.cr**: `lipsum`
- **debug.cr**: `debug`

## Implementation Steps

### Step 1: Create Std Registration Module
Create `src/std/registry.cr` that uses the macros:

```crystal
module Crinkle::Std
  # Filters
  Crinkle.define_filter :upper,
    params: {value: String},
    returns: String,
    doc: "Convert string to uppercase" do
    __param_value.to_s.upcase
  end

  # ... more filters

  def self.register(env : Environment) : Nil
    __register_filter_upper(env)
    # ... more registrations
  end
end
```

### Step 2: Migrate Filters (by file)
1. strings.cr - String manipulation filters
2. lists.cr - Collection filters
3. numbers.cr - Numeric filters
4. html.cr - HTML/URL encoding filters
5. serialize.cr - Serialization filters

### Step 3: Migrate Tests (by file)
1. types.cr - Type checking tests
2. comparison.cr - Comparison tests
3. strings.cr - String tests

### Step 4: Migrate Functions
1. range.cr, dict.cr, namespace.cr, cycler.cr, joiner.cr, lipsum.cr, debug.cr

### Step 5: Update Environment
Modify `Environment.new(load_std: true)` to call the new registration methods.

### Step 6: Verify Schema Output
Run `crinkle schema --pretty` and verify all builtins appear with correct metadata.

## Migration Pattern

**Before (current approach):**
```crystal
module StringFilters
  def self.register(env : Environment) : Nil
    env.register_filter("upper") do |value, args, kwargs, ctx|
      Crinkle.value(value.to_s.upcase)
    end
  end
end
```

**After (typed macro):**
```crystal
module StringFilters
  Crinkle.define_filter :upper,
    params: {value: String},
    returns: String,
    doc: "Convert string to uppercase" do
    __param_value.to_s.upcase
  end

  def self.register(env : Environment) : Nil
    __register_filter_upper(env)
  end
end
```

## Benefits
- Schema automatically populated at compile time
- Documentation embedded in code
- Type metadata enables future validation
- LSP can provide completions and hover info

## Acceptance Criteria
- [ ] All std filters use `define_filter` macro
- [ ] All std tests use `define_test` macro
- [ ] All std functions use `define_function` macro
- [ ] `crinkle schema` outputs complete builtin catalog
- [ ] All existing tests pass (no behavioral changes)
- [ ] Schema JSON includes params, returns, doc for each builtin

## Estimated Scope
- ~50 filters
- ~30 tests
- ~10 functions
- Medium effort (mostly mechanical conversion)

## Dependencies
- Phase 22 (Typed Registration Macros) - COMPLETE

## Risks
- Some filters have complex signatures (variadic args, special cases)
- Need to ensure no behavioral regressions during migration
