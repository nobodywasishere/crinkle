# Phase 1 — Minimal Lexer (Detailed Plan)

## Objectives
- Define the token model for Jinja2 templates.
- Implement a homegrown lexer with precise spans.
- Be fault-tolerant: continue lexing after errors whenever possible.
- Be extremely performant: low allocations, linear pass, minimal branching.
- Emit stable diagnostics for malformed input.
- Add lexer-focused fixtures and tests.

## Scope (Phase 1)
- Tokenize raw text and Jinja2 delimiters.
- Handle `{{ ... }}` and `{% ... %}` blocks.
- Recognize identifiers, numbers, strings, operators, and punctuation (minimal set).
- Track line/column and byte offsets for every token.
- Emit diagnostics for unterminated expressions/blocks.
- UTF-8 support: lexer operates on a char stream (not raw bytes).

## Token Model (initial)
- `Text`
- `VarStart` (`{{` / `{{-`)
- `VarEnd` (`}}` / `-}}`)
- `BlockStart` (`{%` / `{%-`)
- `BlockEnd` (`%}` / `-%}`)
- `Identifier`
- `Number`
- `String`
- `Operator` (e.g., `==`, `!=`, `+`, `-`, `*`, `/`, `|`, `.`)
- `Punct` (e.g., `(`, `)`, `[`, `]`, `{`, `}`, `,`, `:`)
- `Whitespace` (inside expressions/blocks only)
- `EOF`

## Lexer Behavior (initial)
- Default state: read raw text until `{` followed by `{` or `%`.
- Enter expression mode on `VarStart`, block mode on `BlockStart`.
- In expression/block mode:
  - Skip/emit whitespace tokens (decide by config; default emit).
  - Lex identifiers, numbers, strings, operators, punctuation.
  - Exit on matching `VarEnd` or `BlockEnd`.
- Support whitespace control markers (`-`) in start/end delimiters.
- Fault tolerance: on error, emit diagnostic and recover to the next safe delimiter.
- If a new `{%` or `{{` appears while inside an expression/block, emit an unterminated diagnostic and recover to text mode.
- Unterminated strings emit diagnostics and recover without aborting the entire lexing pass.

## Span Tracking
- Each token has:
  - `span.start.offset` (0-based)
  - `span.start.line` / `span.start.column` (1-based)
  - `span.end.offset`, `span.end.line`, `span.end.column`
 - Offsets are byte offsets; line/column are character-based.

## Diagnostics (Phase 1)
- `E_UNTERMINATED_EXPRESSION` for `{{` without `}}`.
- `E_UNTERMINATED_BLOCK` for `{%` without `%}`.
- `E_UNEXPECTED_CHAR` for invalid bytes in expression/block mode.

## Performance Guidelines
- Single-pass scanner over bytes; no backtracking.
- Avoid substring allocations; use slices/indices where possible.
- Pre-allocate token buffers when input size is known.
- Keep hot paths branch-light; avoid regex.

## Files to Add
- `src/lexer/lexer.cr` — main lexer class
- `src/lexer/token.cr` — token types + span struct
- `src/diagnostics/diagnostic.cr` — diagnostic types
- `spec/lexer_spec.cr` — lexer specs

## Tests / Fixtures
- Reuse Phase 0 fixtures for basic coverage.
- Add lexer-specific fixtures if needed (e.g., operators, strings, numbers).
- Snapshot lexer output to JSON (optional for Phase 1, but preferred).

## CLI Integration
- Update `scripts/j2parse` to print tokens for a `.j2` file once lexer is live.

## Acceptance Criteria
- Lexer tokenizes `.j2` fixtures with correct spans.
- Diagnostics are emitted for malformed delimiters.
- Tests pass using Crystal `spec`.

## Tooling Notes
- Lint with Ameba 1.7.x using `/Users/margret/.local/bin/ameba`.
- Run specs with `CRYSTAL_CACHE_DIR=/tmp/crystal-cache crystal spec` (cache dir override).
