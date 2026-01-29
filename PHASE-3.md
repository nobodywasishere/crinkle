# Phase 3 — Expression Grammar (Detailed Plan)

## Objectives
- Expand expression parsing to cover Jinja2 operators and precedence.
- Add calls, filters, tests, attribute access, and indexing.
- Improve literal support (lists, dicts, tuples).
- Strengthen diagnostics and recovery for expression errors.

## Scope (Phase 3)
- Operators:
  - Unary: `not`, `-`, `+`
  - Boolean: `and`, `or`
  - Comparisons: `==`, `!=`, `<`, `<=`, `>`, `>=`, `in`, `not in`, `is`, `is not`
  - Arithmetic: `+`, `-`, `*`, `/`, `//`, `%`, `**`
  - Concatenation: `~`
- Primary forms:
  - Names, literals (string/number/bool/null)
  - Grouping with `(...)`
  - List literal: `[a, b, c]`
  - Dict literal: `{key: value, ...}`
  - Tuple literal: `(a, b)`
- Postfix:
  - Attribute access: `foo.bar`
  - Indexing: `foo[0]` / `foo["key"]`
  - Calls: `foo(arg, kw=val)`
  - Filters: `value|filter(arg)`
  - Tests: `value is test` / `value is not test`

## Parser Changes
- Implement full Pratt parser with precedence table aligned to Jinja2.
- Add AST nodes:
  - `Unary(op, expr)`
  - `Compare(left, ops)` or `Binary` expanded to comparisons
  - `Call(callee, args, kwargs)`
  - `Filter(expr, name, args, kwargs)`
  - `Test(expr, name, args)`
  - `GetAttr(target, name)`
  - `GetItem(target, index)`
  - `ListLiteral(items)`
  - `DictLiteral(pairs)`
  - `TupleLiteral(items)`
- Add keyword handling for `and`, `or`, `not`, `in`, `is`.
- Track spans for new nodes.

## Diagnostics
- Unexpected token in expression (with expected forms).
- Unterminated list/dict/tuple.
- Missing closing `)` / `]` / `}`.
- Invalid filter/test syntax.
- Recovery: sync to `,`, `)`/`]`/`}` or block end.
- Recovery: when an unexpected token appears, advance to the next viable expression start
  (or stop token) to avoid cascading `}}`/`%}` errors.

## Fixtures / Snapshots
- Add focused fixtures for:
  - Precedence/associativity
  - Filters + tests
  - Calls with kwargs
  - Indexing + attribute access
  - List/dict literals
  - Error cases (missing separators, missing closers)
- Use self-updating snapshot specs for parser AST + diagnostics.

## Implementation Notes
- Unexpected-token recovery now re-syncs to the next expression-start token so we can
  continue parsing (ex: `{{ 1 + * 2 }}` becomes `1 + 2` with a single diagnostic).

## CLI Integration
- `src/j2parse.cr --ast` should include new expression nodes.

## Acceptance Criteria
- Expression fixtures parse into correct AST shapes.
- Diagnostics are emitted for malformed expressions.
- Snapshot-based specs pass.

## Progress Checklist
- [x] Precedence table aligned with Jinja2 (approximate; refine if needed)
- [x] New AST nodes implemented
- [x] Pratt-style parsing with postfix and infix operators
- [x] Filters/tests/calls parsing
- [x] List/dict/tuple literals
- [x] Diagnostics + recovery for expression errors
- [x] Fixtures + snapshot specs updated
