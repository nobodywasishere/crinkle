# Phase 30 — Crinja Lexer/Parser Parity (Detailed Plan)

## Objectives
- Match Crinja lexer behavior exactly, including delimiter handling, token boundaries, and string/number edge cases.
- Match Crinja expression parser behavior exactly, including operator precedence/associativity and filter/test argument parsing.
- Match Crinja template parser behavior for tag handling and end-tag semantics where compatibility requires strictness.

## Priority
**CRITICAL** - Blocks Drop-in Compatibility

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

## Acceptance Criteria
- All parity fixtures pass with snapshots matching intended Crinja-compatible behavior.
- Previously identified lexer/parser mismatch cases are covered by regression fixtures.
- `crystal spec` passes.
- `/Users/margret/.local/bin/ameba` passes.

## Checklist
- [ ] Add parity matrix with concrete mismatch cases and expected behavior.
- [ ] Add lexer parity fixtures (delimiters, numbers, strings, operators).
- [ ] Add expression parser parity fixtures (precedence, filters/tests, calls/members).
- [ ] Add template parser parity fixtures (end tags, unknown tags, trimming).
- [ ] Implement lexer updates in `src/lexer/lexer.cr`.
- [ ] Implement parser updates in `src/parser/parser.cr`.
- [ ] Ensure diagnostics snapshots are stable and useful.
- [ ] Run `crystal spec`.
- [ ] Run `/Users/margret/.local/bin/ameba`.

## Verification
```bash
crystal spec
/Users/margret/.local/bin/ameba
```
