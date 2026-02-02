# Phase 12 — Crinja Object Serialization Compatibility

## Goal
Match the Crinja object serialization surface (value conversion + Object::Auto) so existing Crinja-based code can migrate with minimal changes. This phase explicitly excludes any other Crinja APIs.

## Sources (Crinja codebase)
Reference implementation: `/Users/margret/dev/crinja/crinja`
- `src/object.cr` (Crinja::Object, Object::Auto, annotations)
- `src/runtime/value.cr` (Crinja.value, Value, Raw types)
- `src/runtime/undefined.cr` (Undefined, StrictUndefined)
- `src/runtime/safe_string.cr` (SafeString, escaping)
- `src/runtime/finalizer.cr` (stringify rules)
- `src/json.cr`, `src/yaml.cr` (JSON::Any, YAML::Any integration)

## Non-Goals
- Runtime environment API compatibility (filters/tests/functions/loaders/config).
- Resolver or method dispatch compatibility.
- Loader/caching behavior, template selection, or tags.
- LSP features (Phase 13).
- Re-implementing undocumented internal behaviors.
- New syntax beyond defined Jinja2 scope.

## Outcomes
- Crinja-style object serialization hooks and conversion rules implemented.
- `Crinkle::Object::Auto` and annotations mirror Crinja behavior.
- Compatibility shims documented and covered by fixtures/specs.

## Compatibility Targets

### 1) Object Serialization and Value Conversion
Mirror the Crinja conversion pipeline defined in `Crinja.value` and `Crinja::Value`:
- **Crinja.value(value)** conversions:
  - Hash -> `Crinja.dictionary` (Hash(Value, Value))
  - NamedTuple -> Dictionary with string keys
  - Tuple -> Crinja::Tuple
  - Array -> Array(Value)
  - Range -> Array
  - Iterator -> Value::Iterator wrapper
  - Char -> String
  - Value -> passthrough
  - Raw (Number | String | Bool | Time | Object | Undefined | SafeString | Dictionary | Array(Value) | Iterator(Value) | Nil) -> Value
  - Otherwise: **raise** "type error: can't wrap X in Crinja::Value"
- **dictionary(object)**: casts any hash-like object to Dictionary, wrapping keys/values as Value.
- **variables(object)**: casts any hash-like object to Variables (string keys), wrapping values as Value.
- **JSON::Any / YAML::Any**:
  - `Crinja.value(any : JSON::Any)` and `Crinja.value(any : YAML::Any)` delegate to `.raw`
  - `JSON::Any` and `YAML::Any` include `Crinja::Object` and implement `jinja_attribute`
- **Undefined**:
  - `Undefined#to_s` prints empty string; `to_json` -> null; `size` -> 0
  - `StrictUndefined` raises on `==`, `<=>`, and `to_s`
- **SafeString**:
  - Preserves escaping; `SafeString.escape` returns safe versions for string/number/array/hash
  - `SafeString.plain` for literals (do not quote in inspect)
- **Finalizer.stringify**:
  - `nil` -> `"none"`
  - arrays -> `[a, b]`
  - hashes -> `{k => v}`
  - tuples -> `(a, b)`
  - quotes values when inside a structure

### 2) Object::Auto (Annotations + Attribute Exposure)
Implement the Crinja `Object::Auto` macro behavior:
- `@[Crinkle::Attribute]` and `@[Crinkle::Attributes]` annotations
- Expose methods based on annotations and defaults
- Support `is_*` alias for `?`-suffixed methods
- Return `Undefined` when attribute is missing
- Wrap returned values through `Crinkle.value`

## Work Plan
1. **Value Conversion Layer**
   - `Crinkle.value` entrypoint now wraps Hash, Tuple, Array, Range, Iterator, Char, Nil, SafeString, Undefined, and Objects.
   - `dictionary`/`variables` helpers produce the Hash/Hash(String, Value) wrappers used throughout the renderer.
2. **Undefined/SafeString/Finalizer**
   - Defined `Undefined`/`StrictUndefined` behaviors plus SafeString escaping and the `Finalizer.stringify` helper used by the renderer.
   - `Finalizer` now prints `nil` as `none` and quotes nested structures.
3. **Object::Auto**
   - Added the annotations and macro to auto-expose methods (including `is_*` aliases).
   - Exposed values are routed through `Crinkle.value`, so missing attributes return `Undefined`.
4. **JSON/YAML integration**
   - Added `src/runtime/json.cr` and `src/runtime/yaml.cr` so `JSON::Any`/`YAML::Any` implement `Crinkle::Object` and forward to the same conversion pipeline.
5. **Fixtures + Specs**
   - Added `object_*` fixtures covering attribute access, safe strings, undefined behavior, value casting, JSON/YAML access, missing/invalid lookups, and SafeString arrays.
   - Specs now run with `UPDATE_SNAPSHOTS=1` to refresh snapshots and succeed without failing on missing files.
6. **Diagnostics**
   - Created diagnostics fixtures (`object_json_missing_attribute`, `object_json_out_of_bounds`) so missing keys/indexes are proven to emit `Unknown attribute` / `Invalid operand` diagnostics.
7. **Docs**
   - Phase 12 docs describe StrictUndefined options and how fixtures capture undefined/error propagation.
8. **Loader guidance**
   - Documented how loader contexts (filesystem/choice/baked) can carry serialized hashes so CLI/loader code can feed the same `Crinkle.value` payloads shown elsewhere.

## Fixtures to Add
- `object_auto.*` — attribute exposure via Object::Auto (name/boolean/missing attribute)
- `object_value_casting.*` — Hash/array/tuple/range conversions
- `object_undefined_behavior.*` — `Undefined` vs `StrictUndefined`
- `object_safe_string.*` — SafeString escaping and iteration
- `object_json_yaml_any.*` — JSON::Any/YAML::Any property lookup
- `object_json_missing_attribute.*` — missing JSON/YAML attributes
- `object_json_out_of_bounds.*` — out-of-range indexes in JSON/YAML arrays
- `object_safe_list.*` — loops over mixed SafeString/String values

## Acceptance Criteria
- All new serialization compatibility fixtures pass.
- No regressions to existing fixtures.
- Documented list of supported Crinja serialization APIs and shims.

## Checklist
- [ ] Value conversion rules implemented.
- [ ] Undefined/StrictUndefined implemented.
- [ ] SafeString + Finalizer implemented.
- [ ] Object::Auto implemented.
- [ ] JSON/YAML integration implemented.
- [ ] Fixtures/specs added and passing.
