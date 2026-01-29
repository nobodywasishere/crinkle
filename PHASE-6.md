# Phase 6 — Renderer / Execution (Detailed Plan)

## Objectives
- Render AST to output with a minimal, predictable runtime.
- Provide renderer diagnostics with spans for runtime errors.
- Establish extension points for filters/tests/functions and custom tags.
- Keep output fixtures and diagnostics consistent and easy to inspect.

## Scope (Phase 6)
- Core renderer with:
  - Text/Raw output
  - `{{ ... }}` expression output
  - `{% if %}`, `{% for %}`, `{% set %}`, `{% set %}...{% endset %}`
- Expression evaluator for literals, names, unary/binary ops, lists/dicts/tuples,
  attribute access, index access, filters, tests, and function calls.
- Runtime context:
  - Scoped variables (stack)
  - Macros registered at render time (minimal support)
- Custom tags without renderers emit diagnostics but still render their body.
- Environment exposes a template loader used by include/import/extends.
- Diagnostics for runtime errors:
  - Unknown variable, unknown filter/test/function, invalid operand, non-iterable loop.
- Fixtures:
  - Templates in `fixtures/render_templates`
  - Output snapshots in `fixtures/render_output` (`.html`)
  - Diagnostics snapshots in `fixtures/render_diagnostics` (`.json`)

## API Sketch
- `Jinja::Renderer`
  - `render(template : AST::Template, context : Hash(String, Value) = Hash(String, Value).new) : String`
  - `diagnostics : Array(Diagnostic)`

## Diagnostics
- `UnknownVariable` when a name is missing from the context.
- `UnknownFilter` / `UnknownTest` / `UnknownFunction`.
- `InvalidOperand` for unsupported ops or type mismatches.
- `NotIterable` when `for` receives a non-iterable value.
- `UnsupportedNode` for tags not yet implemented in rendering.

## Fixtures / Snapshots
- Templates live in `fixtures/templates` (same shared folder).
- Output snapshots in `fixtures/render_output` (`.html`).
- Diagnostics snapshots in `fixtures/render_diagnostics` (`.json`).
- Renderer-focused templates (prefix with `render_` to avoid confusion):
  - `render_text_only.j2` → plain HTML output.
  - `render_var_output.j2` → output using context variables.
  - `render_if_else_true.j2` / `render_if_else_false.j2` → truthiness and branching.
  - `render_for_loop_items.j2` / `render_for_loop_empty.j2` → loop + else.
  - `render_set_and_output.j2` / `render_set_block.j2` → variable assignment.
  - `render_filters_and_tests.j2` → filter + test integration.
  - `render_function_call.j2` → environment function.
  - `render_unknown_variable.j2` → runtime diagnostic.
  - `render_unknown_filter.j2` → runtime diagnostic with fallback.
  - `render_bad_loop_iterable.j2` → runtime diagnostic for non-iterable.

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
