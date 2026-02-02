# Phase 16 — Required Builtin Tests (Detailed Plan)

## Objectives
- Implement complete set of Jinja2 builtin tests.
- Match Jinja2 test semantics exactly.
- Enable `is` expressions in templates.

## Priority
**HIGH**

## Status Summary

### Implemented Tests (29 tests) ✅

| Test | Location | Notes |
|------|----------|-------|
| `defined` | types.cr | ✅ |
| `undefined` | types.cr | ✅ |
| `none` | types.cr | ✅ |
| `boolean` | types.cr | ✅ |
| `true` | types.cr | ✅ |
| `false` | types.cr | ✅ |
| `number` | types.cr | ✅ |
| `integer` | types.cr | ✅ |
| `float` | types.cr | ✅ |
| `string` | types.cr | ✅ |
| `sequence` | types.cr | ✅ (includes String) |
| `iterable` | types.cr | ✅ |
| `mapping` | types.cr | ✅ |
| `callable` | types.cr | ✅ Detects Crinkle::Object |
| `sameas` | types.cr | ✅ Identity comparison |
| `escaped` | types.cr | ✅ SafeString check |
| `odd` | types.cr | ✅ |
| `even` | types.cr | ✅ |
| `divisibleby` | types.cr | ✅ |
| `lower` | strings.cr | ✅ |
| `upper` | strings.cr | ✅ |
| `startswith` | strings.cr | ✅ (extension) |
| `endswith` | strings.cr | ✅ (extension) |
| `eq` / `equalto` | comparison.cr | ✅ |
| `ne` | comparison.cr | ✅ |
| `lt` / `lessthan` | comparison.cr | ✅ |
| `le` | comparison.cr | ✅ |
| `gt` / `greaterthan` | comparison.cr | ✅ |
| `ge` | comparison.cr | ✅ |
| `in` | comparison.cr | ✅ |

### Deferred to Phase 17 (2 tests)

| Test | Description | Reason |
|------|-------------|--------|
| `filter` | Check if filter exists by name | Requires env access |
| `test` | Check if test exists by name | Requires env access |

## Scope (Phase 16)

### Part A — Core Tests ✅ COMPLETE
The 4 originally scoped tests are implemented:
- `none` — Check if value is nil
- `defined` — Check if value is NOT Undefined
- `undefined` — Check if value IS Undefined
- `sequence` — Check if value is Array or String

### Part B — Remaining Jinja2 Tests (TODO)

#### 1. sameas — Identity comparison
```crystal
env.register_test("sameas") do |value, args, _kwargs|
  other = args.first?
  value.same?(other)
end
```

#### 2. escaped — Check if value is SafeString
```crystal
env.register_test("escaped") do |value, _args, _kwargs|
  value.is_a?(SafeString)
end
```

#### 3. filter — Check if filter exists (requires env access)
```crystal
# Requires TestProc signature change to include Environment
env.register_test("filter") do |value, _args, _kwargs, env|
  name = value.to_s
  env.filters.has_key?(name)
end
```

#### 4. test — Check if test exists (requires env access)
```crystal
# Requires TestProc signature change to include Environment
env.register_test("test") do |value, _args, _kwargs, env|
  name = value.to_s
  env.tests.has_key?(name)
end
```

#### 5. callable — Fix to properly detect callable objects
```crystal
env.register_test("callable") do |value, _args, _kwargs|
  case value
  when Crinkle::Object
    # Check if object implements jinja_call
    value.responds_to?(:jinja_call)
  else
    false
  end
end
```

## Implementation Notes

### Environment Access for `filter` and `test`
The `filter` and `test` introspection tests require access to the Environment to check registered filters/tests. Options:
1. Change `TestProc` signature to include `Environment`
2. Create special-case handling in renderer for these tests
3. Defer to Phase 17 (Environment Access in Filters/Functions)

**Recommendation:** Implement `sameas` and `escaped` now (easy), defer `filter`/`test` to Phase 17.

## Test Fixtures

Located in `fixtures/std_tests/`:

| Fixture | Tests |
|---------|-------|
| `test_none.html.j2` | nil detection |
| `test_defined.html.j2` | defined/undefined |
| `test_undefined.html.j2` | undefined detection |
| `test_sequence.html.j2` | array/string sequences |
| `types.html.j2` | comprehensive type tests |
| `comparison.html.j2` | comparison tests |
| `strings.html.j2` | string tests |

## Acceptance Criteria
- [x] Core 4 tests implemented with correct Jinja2 semantics
- [x] Tests work with `is` and `is not` expressions
- [x] Test fixtures pass
- [x] `sameas` test implemented
- [x] `escaped` test implemented
- [x] `callable` test fixed
- [ ] `filter` test implemented (deferred to Phase 17)
- [ ] `test` test implemented (deferred to Phase 17)

## Checklist

### Part A — Core Tests ✅
- [x] `none` test (check if value is nil)
- [x] `defined` test (check if value is NOT Undefined)
- [x] `undefined` test (check if value IS Undefined)
- [x] `sequence` test (check if value is Array or String)
- [x] Create test fixtures

### Part B — Remaining Tests ✅
- [x] `sameas` test (identity comparison)
- [x] `escaped` test (SafeString check)
- [x] Fix `callable` test (detect Crinkle::Object)
- [ ] `filter` test (requires env access — deferred to Phase 17)
- [ ] `test` test (requires env access — deferred to Phase 17)
