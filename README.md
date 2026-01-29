# crinkle

A Jinja2-compatible lexer, parser, linter, and language server written in Crystal.

## Status
- Lexer and parser implemented with fixtures and snapshot specs
- Custom tag extensions wired (see `PHASE-5.md`)
- Renderer, linter, LSP follow the roadmap in `PLAN.md`

## Goals
- Faithful Jinja2 v3.1.6 parsing (parse + diagnostics first)
- Homegrown lexer and parser
- Linter and LSP for template authoring

## Structure
- `src/` — core implementation
- `spec/` — Crystal specs
- `fixtures/` — `.j2` templates and JSON snapshots
  - Naming convention: `Crinkle::Lexer`, `Crinkle::Parser`, `Crinkle::AST`, `Crinkle::Diagnostics`

## CLI
- `crinkle lex [path] [--stdin] [--format json|text] [--pretty]`
- `crinkle parse [path] [--stdin] [--format json|text] [--pretty]`
- `crinkle render [path] [--stdin] [--format html|text]`
- `crinkle format [path] [--stdin] [--output path]`
- `crinkle lint [path] [--stdin] [--format json|text] [--pretty]`

## Custom Extensions
Register custom tags, filters, tests, and functions through `Crinkle::Environment`.

```crystal
env = Crinkle::Environment.new

env.register_tag("note", ["endnote"]) do |parser, start_span|
  parser.skip_whitespace
  args = Array(Crinkle::AST::Expr).new
  args << parser.parse_expression([Crinkle::TokenType::BlockEnd])
  end_span = parser.expect_block_end("Expected '%}' to close note tag.")
  body, body_end = parser.parse_until_any_end_tag(["endnote"], allow_end_name: true)
  body_end ||= end_span

  Crinkle::AST::CustomTag.new(
    "note",
    args,
    Array(Crinkle::AST::KeywordArg).new,
    body,
    parser.span_between(start_span, body_end)
  )
end

env.register_filter("upper") do |value, _args, _kwargs|
  value.to_s.upcase
end
```

Pass the environment to the parser:

```crystal
parser = Crinkle::Parser.new(tokens, env)
```

Notes:
- Built-in tags are reserved by default. Set `Environment.new(override_builtins: true)`
  and mark extensions with `override: true` to replace built-ins.
- Use `parse_until_any_end_tag` for block-style custom tags with recovery.

## Development
- Run specs: `crystal spec`

## Object serialization

The renderer exposes a Crinja-inspired serialization pipeline so templates work with wrapped values consistently while still allowing you to surface missing data or escaped content explicitly.

### `Crinkle.value(value)`

- Converts any supported Crystal value into the `Crinkle::Value` union that the renderer understands. Supported inputs:
  - `Hash`, `NamedTuple` → rich dictionaries (`Hash(Value, Value)` or `Hash(String, Value)`)
  - `Array`, `Tuple`, `Range`, `Iterator` → flatten to `Array(Value)`
  - `Char`, `String`, numbers, booleans, `Time`, `Nil`, `SafeString`, `Undefined`, `StrictUndefined`, and implementors of `Crinkle::Object`.
- `Crinkle.dictionary` / `Crinkle.variables` turn hash-like objects into dictionaries while re-wrapping every key/value via `Crinkle.value`.
- Passing an unsupported type raises `type error: can't wrap ... in Crinkle::Value`, so serializers stay strict about what data enters the renderer.

### Undefined / StrictUndefined / SafeString

- **`Undefined`** represents missing attributes/variables. It renders as an empty string (`Finalizer.stringify` prints `none` for naked nils) but keeps the missing name for diagnostics so you can report `Unknown variable "foo"`.
- **`StrictUndefined`** raises whenever you try to stringify, compare, or inspect it—useful if you want Crinja-style strictness without silently falling back to empties.
- To toggle `StrictUndefined` globally, future environment flags like `Environment.new(strict_undefined: true)` will treat any missing value as an immediate exception. You can also inject `Crinkle::StrictUndefined.new("name")` yourself to mimic that behavior today.
- **`SafeString`** wraps pre-escaped HTML content. The `Finalizer` treats `SafeString` specially (quote escaping is skipped unless nested inside arrays/hashes), so loops and filters that re-emit safe strings keep their literal markup.

### `Crinkle::Object::Auto`

- Annotate a Crystal class with `@[Crinkle::Attribute]` or `@[Crinkle::Attributes(expose: ...)]`, include `Crinkle::Object::Auto`, and the macro auto-generates `crinja_attribute` logic so templates can call methods directly.
- Methods ending with `?` automatically expose `is_*` lookups (e.g., `admin?` → `is_admin`). Missing attributes fall back to `Undefined`, so you can call them without extra guard clauses.
- Every exposed method result is re-wrapped via `Crinkle.value`, meaning nested hashes, arrays, or even other `Object::Auto` instances remain serializable.

### JSON / YAML helpers

- `JSON::Any` and `YAML::Any` now include `Crinkle::Object` and implement `crinja_attribute`, so you can treat parsed JSON/YAML as dictionaries inside templates. Indexed access respects ints and SafeStrings.
- Invalid attribute/item lookups on JSON/YAML objects still return `Undefined`, preserving diagnostics without crashing the renderer.

### Diagnostics & loaders

- Missing attributes now emit diagnostics even though the rendered output stays empty (`fixtures/object_json_missing_attribute.*` shows `Unknown attribute 'missing'`).
- Reading beyond an array’s bounds produces an `Invalid operand` diagnostic (`fixtures/object_json_out_of_bounds.*`), so you can surface those errors in tooling without failing rendering.
- Since contexts are plain hashes of `Crinkle::Value`, you can hydrate templates with serialized objects regardless of loader: use `Loader::FileSystemLoader` or `Loader::ChoiceLoader` to read templates from disk, set `context = {"payload" => Crinkle.value(my_hash)}`, and pass that context into the renderer. Baked assets via `Loader::BakedFileLoader` follow the same rules—just build your payload once and store it alongside the baked templates.

### JSON/YAML error propagation

```
{# fixtures/object_json_missing_attribute.html.j2 #}
JSON missing attribute:
{{ json_any.missing }}
```

The diagnostics snapshot records `Unknown attribute 'missing'` even though the template prints nothing, proving the renderer reports the missing key while still rendering safely.

```
{# fixtures/object_json_out_of_bounds.html.j2 #}
JSON item[5]:
{{ json_any.items[5] }}
```

Reading past the end of the array logs `Invalid operand: Index 5 out of bounds.` so you can flag the failure separately from the rendered HTML.
### Edge cases & diagnostics

- Missing keys: templates see `Undefined`, render empty output, and diagnostics can highlight the missing name.
- Out-of-bounds array indices return `Undefined`, not `nil`, so you can still detect the absence of data.
- Unsupported types (e.g., custom structs you forget to wrap) raise immediately from `Crinkle.value`, preventing hard-to-trace `nil` propagation.
- `StrictUndefined` prevents your template from silently rendering when a value is missing; every access raises so the caller sees the error.
- SafeStrings inside arrays/hashes still quote correctly when the container is stringified, avoiding accidental double-escaping.

### Example fixtures

- Inspect `fixtures/object_*` to see attribute access, JSON/YAML lookups, safe-string iteration, undefined/missing attribute cases, and value-casting scenarios.

### Examples

```crystal
template = env.parse("User: {{ user.name }}, Status: {{ user.active }}")
context = {"user" => Crinkle.value({"name" => "Ada", "active" => true})}
renderer.render(template, context)
```

```crystal
class Badge
  include Crinkle::Object::Auto

  @[Crinkle::Attribute]
  def label
    "beta"
  end

  @[Crinkle::Attribute]
  def highlighted?
    false
  end
end

context = {"badge" => Crinkle.value(Badge.new)}
```

```crystal
safe_list = [
  Crinkle::SafeString.new("<b>safe</b>"),
  "<i>plain</i>"
] of Crinkle::Value
context["safe_list"] = safe_list
```
