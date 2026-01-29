# jinja-cr — Plan

## Goals
Build a cohesive developer experience for Jinja2 templates in Crystal:
- Fault-tolerant lexer + parser
- AST + diagnostics
- Linter
- Language Server (LSP)

## Phased Plan

### Phase 0 — Baseline + Specs
**Outcome:** Clear scope, repo structure, and fixtures.
- Define scope of Jinja2 features (blocks, filters, tests, macros, includes, whitespace control, etc.).
- Capture compatibility targets (which Jinja2 version or subset).
- Decide error-handling model (recoverable diagnostics vs. hard failures).
- Set up basic project layout (src/, spec/, fixtures/).
- Collect/author fixtures: small templates (`.j2`) + expected AST/diagnostics.
- Use JSON for AST snapshots and store expected outputs in parallel fixture folders.
- Add a minimal CLI to run lexer/parser on a fixture.
- Document how evaluation/execution layers on after parsing.
- Adopt `Jinja::` module naming (e.g., `Jinja::Lexer`, `Jinja::Parser`).

#### Phase 0 Checklist
- [x] Scope and compatibility decisions documented
- [x] Repo skeleton created
- [x] Fixtures added (`.j2` templates + JSON snapshots)
- [x] Diagnostics/AST snapshot format documented
- [x] Minimal CLI scaffold added
- [x] Eval/exec layering documented

### Phase 1 — Minimal Lexer
**Outcome:** Token stream with precise spans.
- Design token types: text, variable start/end, block start/end, identifiers, literals, operators, punctuation, whitespace control.
- Implement a streaming lexer over UTF-8 chars with line/column tracking.
- Support Jinja2 delimiters and raw text.
- Emit diagnostics for malformed delimiters or unexpected EOF.
- Add lexer tests against fixtures (`.j2`).
- Prefer fault-tolerant recovery (keep lexing after errors).
- Add lexer token/diagnostic JSON snapshots for fixtures.
- Snapshot specs write updated JSON and fail on diffs to surface changes.

#### Phase 1 Checklist
- [x] Token model + spans implemented
- [x] UTF-8 char-stream lexer implemented
- [x] Fault-tolerant recovery in lexer
- [x] Diagnostics emitted for unterminated constructs
- [x] Lexer specs added
- [x] CLI prints tokens/diagnostics

### Phase 2 — Minimal Parser + AST
**Outcome:** Parse a limited but useful subset.
- Define AST nodes: Template, Text, Output, Name, Literal, Call, Filter, If, For, Block.
- Parse:
  - `{{ ... }}` output expressions
  - `{% if %}...{% endif %}`
  - `{% for %}...{% endfor %}`
- Build error recovery (sync at block end / delimiter).
- Emit diagnostics with spans for syntax errors.
- Parser tests with golden AST + diagnostics (stored under `fixtures/parser_*`).
- Use self-updating snapshot specs for AST/diagnostics.

#### Phase 2 Checklist
- [x] AST types + serializer added
- [x] Parser implemented for `if`/`for` and basic expressions
- [x] Parser diagnostics + recovery
- [x] Snapshot fixtures + specs (self-updating)
- [x] CLI supports AST output

#### Notes: Custom Tags (Planned)
- Add a parser extension registry keyed by tag name.
- Extensions provide a `parse` hook that consumes tokens and returns AST nodes.
- Extensions declare their end tags to aid recovery and nesting.
- Unknown tags emit diagnostics when no extension matches.
- Consider an `Environment` object that registers extensions before parsing.

### Phase 3 — Expression Grammar
**Outcome:** Full expression parsing (no evaluation).
- Implement precedence/associativity (or Pratt parser).
- Support filters (`|`), tests (`is`), calls, indexing, attribute access.
- Support literals: strings, numbers, booleans, null, lists, dicts.
- Add whitespace/line-statement variations (if in scope).
- Expand fixtures + tests.
- Recovery: unexpected tokens now resync to the next expression-start token to avoid
  cascading `}}`/`%}` errors (ex: `{{ 1 + * 2 }}` recovers to `1 + 2` with a single diagnostic).

#### Phase 3 Checklist
- [x] Expression parser extended with precedence + postfix operators
- [x] New AST nodes for calls/filters/tests/attr/index/literals
- [x] Parser/lexer snapshots updated for new fixtures

### Phase 4 — Jinja2 Control Structures + Macros
**Outcome:** Broader language coverage.
- Add parsing for:
  - `{% set %}` / `{% set ... %}{% endset %}`
  - `{% macro %}` / `{% call %}`
  - `{% import %}`, `{% include %}`, `{% extends %}`, `{% block %}`, `{% super %}`
  - `{% raw %}` / `{% endraw %}`
- Track nesting and scoping in AST.
- Improve recovery for mismatched tags.
- Note: end tags may include a trailing name (e.g., `endblock name`); parser accepts
  it now and leaves mismatch checks for the linter. Raw blocks collect token lexemes
  until `endraw` and emit a single `Raw` node.
- Added edge-case fixtures for missing end tags, malformed import/include flags, unknown
  tags, and raw blocks that contain tag-like text.

### Phase 5 — Custom Tags / Extensions
**Outcome:** Parser extensibility for non-core tags.
- Introduce a tag-extension registry (name -> handler).
- Extension handlers can consume tokens and return AST nodes.
- Extensions declare end tags to support recovery/nesting.
- If a handler returns `nil` and declares end tags, parser recovers to the next end tag
  and emits a fallback `AST::CustomTag` node.
- Unknown tags emit diagnostics when no extension matches.
- Add fixtures for extension tag parsing and error recovery.
- Add registries for custom filters, tests, and global functions with a consistent API
  (wiring for renderer; evaluation happens in Phase 6).

### Phase 6 — Renderer / Execution
**Outcome:** Render templates from AST (no linting yet).
- Define runtime context (variables, filters, tests, globals).
- Implement evaluation for expressions and control flow.
- Render output with whitespace control and raw blocks.
- Integrate include/extends/import/macro/call behavior.
- Add rendering fixtures with expected output.

### Phase 7 — Formatter (Optional, HTML-aware)
**Outcome:** Format templates with HTML-structural awareness.
- Build formatter over AST + token spans (preserve trivia where possible).
- HTML-aware mode: align Jinja blocks with HTML indentation.
- Configurable options (indent width, line length, whitespace control).
- Add fixtures with before/after formatting samples.

### Phase 8 — Linter
**Outcome:** Useful diagnostics beyond syntax.
- Build rule framework with rule IDs, severity, quick fixes.
- Starter rules:
  - Unknown variables (if symbol table available)
  - Unused variables / imports
  - Unclosed or mismatched blocks
  - Deprecated syntax
  - Suspicious whitespace control
- Add tests for lints and fixes.

### Phase 9 — Language Server (LSP)
**Outcome:** IDE features for templates.
- Minimal LSP server (initialize, textDocument/didOpen, didChange, didClose).
- Diagnostics pipeline using lexer/parser/linter.
- Hover + go-to-definition for variables/macros/blocks.
- Document symbols, folding ranges, semantic tokens (optional).
- Performance: incremental parsing and caching.

### Phase 10 — Compatibility + UX Polish
**Outcome:** Confidence + developer adoption.
- Add compatibility test suite using real-world Jinja2 templates.
- Benchmark parsing on large templates.
- Documentation, examples, and release process.

## Definition of Done (per phase)
- Tests passing for all added fixtures.
- Diagnostics include spans and human-friendly messages.
- Minimal public API for lexer/parser results.
- No regressions on previous phases.

## Open Questions
- Exact Jinja2 feature scope and version compatibility?
  - Jinja2 v3.1.6
- Should we parse only, or also evaluate/execute templates?
  - There should be functionality for evaluating / executing templates, but this should be a separate pass from parsing them
- Should we aim for full Jinja2 whitespace/line statement options?
  - Yes
- Do we need integration with existing Crystal Jinja2 libraries (e.g., crinja)?
  - This is meant as a replacement for crinja, so no
- Preferred test framework and formatting for AST snapshots?
  - Use the built-in spec testing framework to Crystal lang
