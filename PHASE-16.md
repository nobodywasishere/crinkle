# Phase 16 — Required Builtin Tests (Detailed Plan)

## Objectives
- Implement complete set of tests needed for production templates.
- Match Jinja2 test semantics.
- Enable `is` expressions in templates.

## Priority
**HIGH**

## Motivation
Analysis of real-world templates identified these required tests:

| Test | Uses | Status |
|------|------|--------|
| `none` / `not none` | ~9 | **Missing** |
| `defined` | ~3 | **Missing** |
| `undefined` / `not undefined` | ~2 | **Missing** |
| `sequence` | 1 | **Missing** |

## Scope (Phase 16)
Implement 4 missing tests in `src/std/tests/` or `Environment#register_builtin_filters_tests`.

## Reference Implementations

### 1. none — Check if value is nil
```crystal
@tests["none"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Bool do
  value.nil?
end
```

### 2. defined — Check if value is NOT Undefined
```crystal
@tests["defined"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Bool do
  !value.is_a?(Undefined)
end
```

### 3. undefined — Check if value IS Undefined
```crystal
@tests["undefined"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Bool do
  value.is_a?(Undefined)
end
```

### 4. sequence — Check if value is iterable (array-like)
```crystal
@tests["sequence"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Bool do
  case value
  when Array(Value), String
    true
  else
    false
  end
end
```

## Test Fixtures

### `fixtures/std/tests/test_none.html.j2`
```jinja
{% if value is none %}NULL{% else %}{{ value }}{% endif %}
```

### `fixtures/std/tests/test_defined.html.j2`
```jinja
{% if optional is defined %}{{ optional }}{% else %}default{% endif %}
```

### `fixtures/std/tests/test_undefined.html.j2`
```jinja
{% if missing is undefined %}not set{% endif %}
```

### `fixtures/std/tests/test_sequence.html.j2`
```jinja
{% if items is sequence %}list{% else %}scalar{% endif %}
```

## Acceptance Criteria
- All 4 tests implemented with correct Jinja2 semantics.
- Tests work with `is` and `is not` expressions.
- Test fixtures pass.

## Checklist
- [ ] Add `none` test (check if value is nil)
- [ ] Add `defined` test (check if value is NOT Undefined)
- [ ] Add `undefined` test (check if value IS Undefined)
- [ ] Add `sequence` test (check if value is iterable)
- [ ] Create test fixtures
