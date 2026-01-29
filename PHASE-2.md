# Phase 2 — Minimal Parser + AST (Detailed Plan)

## Objectives
- Define a minimal AST for template structure and expressions.
- Implement a fault-tolerant parser over the lexer token stream.
- Produce diagnostics with spans and recover from common syntax errors.
- Add parser snapshot fixtures (AST + diagnostics).

## Scope (Phase 2)
- Parse:
  - Raw text nodes
  - `{{ ... }}` output expressions (single expression)
  - `{% if %}...{% endif %}` blocks (no elif/else yet)
  - `{% for %}...{% endfor %}` blocks
- Expression subset:
  - Names and literals (strings, numbers, booleans, null)
  - Simple binary operators (`+`, `-`, `*`, `/`, `==`, `!=`)
  - Parentheses for grouping
- Error recovery:
  - Synchronize on `VarEnd`, `BlockEnd`, and matching `end*` tags
  - Continue parsing after a malformed block header or expression

## AST (initial)
- `Template(body: Array(Node))`
- `Text(value: String)`
- `Output(expr: Expr)`
- `If(test: Expr, body: Array(Node), else_body: Array(Node))`
- `For(target: Name, iter: Expr, body: Array(Node), else_body: Array(Node))`
- Expressions:
  - `Name(value: String)`
  - `Literal(value: String | Number | Bool | Nil)`
  - `Binary(op: String, left: Expr, right: Expr)`
  - `Group(expr: Expr)`

## Parser Behavior
- Consume tokens from `Jinja::Lexer` and build AST nodes.
- Preserve spans for nodes (start/end offsets + line/column).
- Skip `Whitespace` tokens inside expressions/blocks.
- Validate block tags (`if`, `for`, `endif`, `endfor`).
- Emit diagnostics for:
  - Unexpected token in expression
  - Missing closing tags
  - Mismatched block types
  - Unterminated expressions/blocks (propagate from lexer)

## Files to Add
- `src/parser/parser.cr` — main parser
- `src/ast/nodes.cr` — AST node definitions
- `spec/parser_spec.cr` — parser specs

## Fixtures / Snapshots
- Add parser fixtures in `fixtures/<name>.<ext>.j2` as needed.
- Add parser snapshots:
  - `fixtures/<name>.parser.ast.json`
  - `fixtures/<name>.diagnostics.json`
- Parser specs should:
  - Parse each fixture
  - Write AST/diagnostics snapshots when missing or changed
  - Fail on diffs to surface updates

## CLI Integration
- Extend `src/j2parse.cr` to optionally emit AST/diagnostics (JSON).

## Acceptance Criteria
- Parser builds AST for core fixtures (`var_only`, `simple_block_if`, `simple_block_for`).
- Parser handles malformed inputs with diagnostics and continues where possible.
- Snapshot-based parser specs pass.

## Notes for Custom Tags (Future)
- Add a parser extension registry (e.g., `Jinja::Parser::Extension`) keyed by tag name.
- Allow extensions to hook into `parse_block` with a `parse` method that consumes tokens and returns an AST node.
- Provide a fallback `UnknownTag` diagnostic when no extension matches.
- Allow extensions to declare which end tags they consume (for recovery and nesting).
- Separate AST namespace for extension nodes to avoid coupling with core nodes.
- Load extensions via an environment/config object passed to the parser.

## Progress Checklist
- [x] AST types defined with spans
- [x] Parser skeleton reads tokens and builds AST
- [x] Expression parser for minimal operators
- [x] Block parsing for `if` and `for`
- [x] Diagnostics + recovery
- [x] Snapshot fixtures and specs (self-updating)
- [x] CLI emits AST/diagnostics
