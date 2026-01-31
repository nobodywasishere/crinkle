# Phase 0 — Baseline + Specs (Detailed Plan for crinkle)

## Objectives
- Align on scope, compatibility, and non-goals.
- Establish repository structure and conventions.
- Produce a reliable fixture set for lexer/parser/linter tests.
- Set expectations for diagnostics, error recovery, and public API.

## Deliverables
- `PHASE-0.md` (this document) with agreed scope and decisions.
- Repo skeleton with `src/`, `spec/`, and `fixtures/` directories.
- Initial fixture corpus (templates + expected outputs).
- Testing conventions documented (AST snapshots + diagnostics format).
- A small “hello world” harness to run lexer/parser on a fixture.

## Scope Decisions (from PLAN.md)
- **Jinja2 compatibility target**: Jinja2 v3.1.6.
- **Feature coverage for Phase 1–2**: must-have tags and expressions as listed in `PLAN.md`.
- **Whitespace control**: support for `{%- -%}` / `{{- -}}`, `trim_blocks`, `lstrip_blocks`.
- **Line statements**: `line_statement_prefix`, `line_comment_prefix`.
- **Evaluation**: parsing and execution should be separate passes.
- **Template inheritance**: parse-only now, semantic validation later.
- **Error recovery**: best-effort parsing with diagnostics.

## Repository Layout (proposed)
- `src/`
  - `lexer/` (module: `Crinkle::Lexer`)
  - `parser/` (module: `Crinkle::Parser`)
  - `ast/` (module: `Crinkle::AST`)
  - `diagnostics/` (module: `Crinkle::Diagnostics`)
  - `lsp/` (module: `Crinkle::LSP`, later)
- `spec/`
  - `lexer_spec.cr`
  - `parser_spec.cr`
  - `fixtures_spec.cr`
- `fixtures/`
  - `*.j2` (templates live in `fixtures/<name>.<ext>.j2`)
  - `ast/`
  - `diagnostics/`

## Diagnostics Contract (proposed)
- Diagnostic fields: `id`, `severity`, `message`, `span`.
- `span` includes start/end byte offsets and line/column pairs.
- Diagnostics should be stable for snapshot testing.
 - Keep schema simple first; expand only as needed.
 - Line/column are 1-based; offsets are 0-based.

## AST Snapshot Format (JSON)
- JSON object with a `type` and node-specific fields.
- Root node is `Template` with `body: []`.
- Expression nodes are nested under `expr` fields.
- Keep schema minimal; extend as parser grows.

## Eval/Exec Layering (decision)
- Parsing produces a pure AST + diagnostics (no evaluation).
- Execution happens in a later pass that consumes the AST and a runtime context.
- Linting and LSP consume the AST and diagnostics, not the executor.

## CLI Contract (Phase 0)
- `src/j2parse.cr <template.j2>` reads the file and prints a simple status message.
- Later phases will print tokens, AST, and diagnostics in JSON.

## Fixture Plan
Start with a minimal set and grow iteratively.

### Minimal fixtures (Phase 1)
- `text_only.j2`: plain text.
- `var_only.j2`: `{{ name }}`.
- `simple_block_if.j2`: `{% if user %}Hi{% endif %}`.
- `simple_block_for.j2`: `{% for item in items %}{{ item }}{% endfor %}`.
- `bad_delimiter.j2`: `{{ name }` (unterminated).

### Expected outputs
- `fixtures/<name>.parser.ast.json` for parser output.
- `fixtures/<name>.diagnostics.json` for errors.
- Outputs live in parallel folders and are committed when changed.

## Testing Approach
- Unit tests for lexer and parser using fixtures.
- Snapshot tests for AST + diagnostics to prevent regressions.
- CI-friendly: no external dependencies.

## Phase 0 Tasks
1. Confirm scope decisions and document in `PLAN.md` and `PHASE-0.md`.
2. Create repo skeleton and stub modules.
3. Add initial fixtures (templates + expected outputs).
4. Define diagnostic schema and AST snapshot format.
5. Add a tiny CLI to run lexer/parser on a fixture.
6. Document how evaluation/execution will be layered after parsing.

## Acceptance Criteria
- We can run tests that load fixtures and compare outputs.
- There is a documented scope baseline to guide Phase 1–2.
- Repo layout is stable enough to start implementing lexer.

## Open Questions
- Use Crystal’s `spec` or another test runner?
- Should fixtures include whitespace-control examples from day one?
