# Phase 5 — Custom Tags / Extensions (Detailed Plan)

## Objectives
- Enable parser extensibility for non-core tags.
- Keep default behavior predictable (built-ins reserved unless explicitly overridden).
- Provide recovery guidance to avoid cascading errors in custom tags.
- Define a minimal public API for extensions and an `Environment`.
- Add a clean, consistent API for custom filters, tests, and functions.

## Scope (Phase 5)
- Parser extension registry keyed by tag name.
- Extension hooks for:
  - `parse` — consumes tokens and returns AST::Node?
  - `end_tags` — declares expected end tags for recovery/nesting
- Runtime registries (for later renderer usage):
  - Filters
  - Tests
  - Global functions
- Optional override capability for built-in tags (off by default).
- Fixtures + snapshots for sample custom tags and error cases.

## API Design
- `Jinja::Environment`
  - `register_tag(name : String, handler : TagHandler, end_tags : Array(String) = [] of String, override : Bool = false)`
  - `register_filter(name : String, filter : FilterProc)`
  - `register_test(name : String, test : TestProc)`
  - `register_function(name : String, fn : FunctionProc)`
  - Holds tag registry, configuration flags (allow overrides).
- `TagHandler` signature proposal:
  - `->(parser : Parser, start_span : Span) : AST::Node?`
  - Parser passed so handler can use shared helpers (expression parsing, recovery).
- Filter/test/function procs (consistent shape):
  - `FilterProc = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value`
  - `TestProc = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Bool`
  - `FunctionProc = ->(args : Array(Value), kwargs : Hash(String, Value)) : Value`
- `TagExtension` optional struct/class:
  - `name : String`
  - `end_tags : Array(String)`
  - `parse(parser : Parser, start_span : Span) : AST::Node?`

## Parser Changes
- Expose a safe subset of helpers to extensions:
  - `parse_expression`
  - `expect_block_end`
  - `recover_to`
  - `parse_until_end_tag`
  - `parse_until_any_end_tag` (multi-end-tag recovery)
- Integrate environment registry:
  - Built-in dispatch table remains first.
  - If tag not found in built-ins, consult registry.
  - If override enabled, registry takes precedence for listed tags.
- Emit diagnostics when:
  - Tag is unknown and no extension matches.
  - Extension fails to consume a required end tag (if `end_tags` declared).

## Diagnostics
- Unknown tag (no extension match).
- Extension parse error (if handler raises/returns nil without recovery).
- Missing end tag for custom block tags (use `end_tags` info).

## Fixtures / Snapshots
- Add a simple custom tag example (e.g., `{% note %}...{% endnote %}`):
  - Parse via extension into `AST::Raw` or a new `AST::CustomTag` node.
- Add a single-line custom tag (e.g., `{% uppercase "hi" %}`).
- Add error cases:
  - Missing end tag for custom block.
  - Unknown custom tag without registration.
  - Custom tag with bad args.
- Add snapshots for AST + diagnostics.

## AST Considerations
- Option A: `AST::CustomTag(name, args, body)` generic node.
- Option B: Extensions return existing nodes (e.g., `Raw`, `SetBlock`) for reuse.
- Decide approach after first fixture set.

## CLI Integration
- Add a flag to load a sample extension registry for demo usage:
  - `j2parse --ext demo`
- Optional demo registrations for filters/tests/functions (no evaluation yet, just wiring).

## Acceptance Criteria
- Parser can register and parse custom tags without modifying core code.
- Built-ins remain reserved unless override is explicitly enabled.
- Diagnostics and recovery work for custom tag errors.
- Snapshot specs pass for custom tag fixtures.

## Progress Checklist
- [x] Environment + registry API added
- [x] Parser integrates registry with override rules
- [x] Extension handlers can use parser helpers safely
- [x] Fixtures + snapshots for custom tags
- [x] CLI demo extension
