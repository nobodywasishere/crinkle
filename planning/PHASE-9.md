# Phase 9 — CLI (Detailed Plan)

## Objectives
- Provide a single, consistent CLI for lexing, parsing, rendering, formatting, and linting.
- Make defaults predictable and ergonomic (stdin -> stdout, minimal flags).
- Align diagnostics output with ameba-like style used elsewhere.
- Keep outputs script-friendly (JSON by default where structured).

## Scope (Phase 9)
- Subcommands:
  - `lex` — tokens + lexer diagnostics
  - `parse` — AST + parser diagnostics
  - `render` — rendered output + renderer diagnostics
  - `format` — formatted template output
  - `lint` — lint diagnostics (plus mapped lexer/parser diagnostics)
- Shared flags + consistent behavior across subcommands.
- Clear exit codes for CI usage.
- Snapshot/debug mode for investigation and fixture work.

## CLI Structure
- Binary name: `crinkle` with subcommands.
- Suggested command shape:
  - `crinkle lex [path] [--stdin] [--format json|text] [--pretty]`
  - `crinkle parse [path] [--stdin] [--format json|text] [--pretty]`
  - `crinkle render [path] [--stdin] [--format html|text]`
  - `crinkle format [path] [--stdin] [--output path]`
  - `crinkle lint [path] [--stdin] [--format json|text] [--pretty]`

## Shared Flags
- Input selection:
  - `path` positional — read template from file
  - `--stdin` — read template from stdin
  - Default: positional path if provided, otherwise stdin
- Output:
  - `--format json|text|html` (per subcommand)
  - `--pretty` — pretty JSON for machine output
  - `--no-color` — disable ANSI color in text diagnostics
- Diagnostics:
  - `--strict` — treat warnings as errors (exit non-zero)
  - `--max-errors N` — cap reported diagnostics
- Debugging / snapshots:
  - `--snapshots-dir PATH` — write tokens/ast/diagnostics for inspection
  - `--dump-tokens` / `--dump-ast` (optional short-hands)

## Output Conventions
- **Text output**:
  - Diagnostics: one per line: `path:line:col: ID message`
  - Order: file > line > column > id > message
- **JSON output**:
  - Stable schema:
    - `tokens`: array of `{type, lexeme, span}`
    - `ast`: object (AST serializer output)
    - `diagnostics`: array of `{id, severity, message, span}`
    - `output`: string (render/format)

## Exit Codes
- `0` — success, no diagnostics at error severity
- `1` — diagnostics at error severity, or `--strict` triggered by warnings
- `2` — invalid CLI usage (bad flags, missing files)
- `3` — internal error

## Implementation Plan
1. **Command framework**
   - Define a CLI entrypoint under `src/crinkle.cr` or `src/cli.cr`.
   - Parse args and route to subcommands.
   - Add shared option parser utilities.

2. **Input handling**
   - Implement `read_source(path?, stdin?)` with explicit precedence.
   - Normalize newlines (optional) for consistent span handling.

3. **Diagnostics formatting**
   - Implement a `DiagnosticPrinter` for text and JSON.
   - Respect `--no-color`, `--pretty`, `--strict`.

4. **Lex command**
   - Read source, lex all tokens, output tokens + diagnostics.

5. **Parse command**
   - Lex + parse, output AST + diagnostics.

6. **Render command**
   - Lex + parse + render, output rendered output + diagnostics.

7. **Format command**
   - Lex + parse + format, output formatted template.

8. **Lint command**
   - Lex + parse + lint, output lint issues.
   - Optionally include lexer/parser diagnostics in output.

9. **Snapshot mode**
   - When `--snapshots-dir` provided, dump artifacts:
     - `tokens.json`, `ast.json`, `diagnostics.json`, `output.html` (if render)

10. **Docs + examples**
   - Update README with basic usage and examples.

## Fixtures / Tests
- Add CLI specs that run subcommands on fixture templates.
- Validate JSON schema correctness and exit codes.
- Snapshot CLI output for a minimal set of templates.

## Acceptance Criteria
- All subcommands work via stdin and file input.
- Consistent diagnostics formatting across commands.
- JSON outputs stable and machine-friendly.
- Exit codes documented and tested.
- README includes examples.

## Decisions
- `render` does not accept context variables in Phase 9 (defer to Phase 9.1).
- `lint` includes mapped lexer/parser diagnostics by default.
- Remove `j2parse.cr` and introduce a dedicated `cli/cli.cr` entrypoint.
- `--dir` is out of scope for Phase 9.
