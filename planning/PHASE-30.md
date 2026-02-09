# Phase 30 — Crinja Lexer/Parser Parity (Detailed Plan)

## Objectives
- Match Crinja lexer behavior exactly, including delimiter handling, token boundaries, and string/number edge cases.
- Match Crinja expression parser behavior exactly, including operator precedence/associativity and filter/test argument parsing.
- Match Crinja template parser behavior for tag handling and end-tag semantics where compatibility requires strictness.

## Priority
**CRITICAL** - Blocks Drop-in Compatibility

## Status
**IN PROGRESS**

## Motivation
crinkle aims to be a drop-in Crinja replacement. That requires behavioral parity in the parser pipeline, including minute differences that affect real templates:
- Delimiter disambiguation with nested braces (`}}}` and similar cases)
- Numeric and string lexing edge cases
- Expression precedence and associativity
- Filter/test syntax and no-parenthesis argument forms
- Tag parsing strictness and end-tag mismatch behavior

Without parity in lexer/parser semantics, downstream rendering and diagnostics diverge.

## Scope (Phase 30)
- Build a parity matrix for lexer + expression parser + template parser behavior.
- Add targeted fixtures for known divergence points and regressions.
- Implement compatibility changes in `src/lexer/lexer.cr` and `src/parser/parser.cr`.
- Keep fault-tolerant diagnostics where possible, but ensure parsing outcomes match Crinja for valid input and key invalid-input edge cases.

## Non-Goals
- Standard library filter/test/function implementation (covered by other phases).
- Renderer/runtime behavior outside parser-driven AST shape differences.
- LSP/editor features.

## File Structure
```
src/
  lexer/
    lexer.cr               # Parity updates for tokenization
  parser/
    parser.cr              # Parity updates for expression/template parsing

fixtures/
  parser/
  lexer/
  integration/
    parity_*.html.j2       # New parity-focused fixtures
    *.diagnostics.json
    *.lexer.tokens.json
    *.parser.ast.json
```

## Work Plan

### 1. Establish Parity Baseline
- Document behavior differences between crinkle and Crinja in a checklist/table.
- Encode each difference as a fixture with expected token stream, AST, and diagnostics.

### 2. Lexer Parity
- Align delimiter closing behavior with nested grouping awareness.
- Align numeric scanning rules (for example: trailing dot handling).
- Align string escape handling and produced token values.
- Align operator tokenization details (`!`, assignment/equality, pipe/test markers as applicable).

### 3. Expression Parser Parity
- Align precedence and associativity (`**`, unary operators, boolean/logical operators).
- Align test/filter parsing (`is`, `is not`, bare args, parenthesized args).
- Align member/index/call parsing edge cases (including numeric member access behavior if required).

### 4. Template Parser Parity
- Align start/end tag matching and mismatched-tag behavior.
- Align unknown-tag behavior for strict compatibility mode.
- Align trim marker effects and block boundary behavior.

### 5. Compatibility Guardrails
- Add regression fixtures for every resolved parity mismatch.
- Add a parity-specific spec target for quick verification during future changes.

## Progress Snapshot (February 9, 2026)
- Implemented major expression parser parity updates in `src/parser/parser.cr`:
  - precedence/associativity alignment for `not`, `~`, `%`, comparisons, and tests
  - `in`/`not in` no longer parsed as binary operators in expressions
  - `null` now parses as an identifier (matching Crinja behavior)
- Added parity fixtures and snapshots for these cases:
  - `expr_not_precedence`, `expr_mod_precedence`, `expr_concat_precedence`
  - `expr_binary_not`, `expr_null_identifier`
  - updated behavior snapshots for `expr_in` and `expr_not_in`
- Verification for this slice passed:
  - `crystal spec`
  - `/Users/margret/.local/bin/ameba`

## Parity Matrix (Current)
| Area | Current Status | Fixture Coverage |
|---|---|---|
| Nested expression delimiter disambiguation (`}}}`) | done | `fixtures/parser/expr_nested_end_delimiter.*` |
| Numeric lexing/member edge cases (`1.`, `foo.1`) | done | `fixtures/parser/expr_trailing_dot_member.*`, `fixtures/parser/expr_dot_numeric_member.*` |
| String escapes and unclosed string handling | done | `fixtures/parser/expr_string_escapes.*`, `fixtures/parser/expr_unclosed_string.*` |
| Filter/test bare-argument parsing (no parens) | done | `fixtures/parser/expr_filter_args_no_parens.*`, `fixtures/parser/expr_filter_kwargs_no_parens.*`, `fixtures/parser/expr_test_arg_without_parens.*` |
| Expression precedence (`not`, `~`, `%`, compare layers) | done | `fixtures/parser/expr_not_precedence.*`, `fixtures/parser/expr_mod_precedence.*`, `fixtures/parser/expr_concat_precedence.*` |
| Binary `in`/`not in` expression handling | done (now rejected/recovery, matching Crinja) | `fixtures/parser/expr_in.*`, `fixtures/parser/expr_not_in.*` |
| `null` literal handling | done (`null` treated as identifier) | `fixtures/parser/expr_null_identifier.*` |
| Lexer operator strictness for bare `!` | done (invalid bare `!` emits lexer error and recovers) | `fixtures/lexer/invalid_bang_operator.*` |
| Template parser strictness (unknown tags, mismatched end-tags) | pending | fixture updates needed |
| Parity-specific fast spec target | pending | spec target needed |

## Acceptance Criteria
- All parity fixtures pass with snapshots matching intended Crinja-compatible behavior.
- Previously identified lexer/parser mismatch cases are covered by regression fixtures.
- `crystal spec` passes.
- `/Users/margret/.local/bin/ameba` passes.

## Checklist
- [x] Add parity matrix with concrete mismatch cases and expected behavior.
- [x] Add lexer parity fixtures for delimiter/numeric/string edge cases.
- [x] Add lexer parity fixtures for remaining operator edge cases (`!`).
- [x] Add expression parser parity fixtures (precedence, filters/tests, calls/members).
- [ ] Add template parser parity fixtures (end tags, unknown tags, trimming).
- [ ] Implement remaining lexer updates in `src/lexer/lexer.cr`.
- [x] Implement expression parser updates in `src/parser/parser.cr`.
- [ ] Implement template parser parity updates in `src/parser/parser.cr`.
- [x] Ensure diagnostics snapshots are stable and useful.
- [x] Run `crystal spec`.
- [x] Run `/Users/margret/.local/bin/ameba`.

## Verification
```bash
crystal spec
/Users/margret/.local/bin/ameba
```
