# Phase 6 — Renderer / Execution (Detailed Plan)

## Objectives
- Render AST to output with a minimal, predictable runtime.
- Provide renderer diagnostics with spans for runtime errors.
- Establish extension points for filters/tests/functions and custom tags.
- Keep output fixtures and diagnostics consistent and easy to inspect.
- Respect whitespace-control trim markers from AST nodes when rendering.

## Scope (Phase 6)
- Core renderer with:
  - Text/Raw output
  - `{{ ... }}` expression output
  - `{% if %}`, `{% for %}`, `{% set %}`, `{% set %}...{% endset %}`
- Template features:
  - `{% include %}` (with `ignore missing` and `with/without context`)
  - `{% import %}`, `{% from %}` for macro loading
  - `{% extends %}` + block overrides with `super()`
  - `{% macro %}` and `{% call %}` blocks
- Expression evaluator for literals, names, unary/binary ops, lists/dicts/tuples,
  attribute access, index access, filters, tests, and function calls.
- Runtime context:
  - Scoped variables (stack)
  - Macros registered at render time (minimal support)
  - `loop` variables for `for` blocks
- Custom tags without renderers emit diagnostics but still render their body.
- Environment exposes a template loader used by include/import/extends.
- Diagnostics for runtime errors:
  - Unknown variable, unknown filter/test/function, invalid operand, non-iterable loop.
- Template cache + cycle detection for recursive includes/extends.
- Fixtures:
  - Templates in `fixtures/<name>.<ext>.j2`
  - Output snapshots in `fixtures/<name>.renderer.output.txt`
  - Diagnostics snapshots in `fixtures/<name>.diagnostics.json`

## API Sketch
- `Crinkle::Renderer`
  - `render(template : AST::Template, context : Hash(String, Value) = Hash(String, Value).new) : String`
  - `diagnostics : Array(Diagnostic)`
  - `register_tag_renderer(tag : String, &block : TagRenderer)`

## Diagnostics
- `UnknownVariable` when a name is missing from the context.
- `UnknownFilter` / `UnknownTest` / `UnknownFunction`.
- `InvalidOperand` for unsupported ops or type mismatches.
- `NotIterable` when `for` receives a non-iterable value.
- `UnsupportedNode` for tags not yet implemented in rendering.
- `TemplateCycle` when an include/extend/import creates recursion.

## Fixtures / Snapshots
- Templates live in `fixtures/<name>.<ext>.j2` (same shared folder).
- Output snapshots in `fixtures/<name>.renderer.output.txt`.
- Diagnostics snapshots in `fixtures/<name>.diagnostics.json`.
- Renderer snapshots are produced for all templates in `fixtures/<name>.<ext>.j2`.
- When adding new renderer-focused templates, consider a `render_` prefix to
  highlight intent, but it is optional.

## Acceptance Criteria
- Renderer returns expected HTML output for fixtures.
- Diagnostics emitted with spans for runtime errors.
- Snapshot specs pass for render output + diagnostics.

## Progress Checklist
- [x] Renderer class implemented
- [x] Runtime expression evaluator implemented
- [x] Runtime diagnostics wired
- [x] Render fixtures + snapshots
- [x] Renderer specs passing
