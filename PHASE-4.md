# Phase 4 — Control Structures + Macros (Detailed Plan)

## Objectives
- Add core Jinja2 control structures beyond `if`/`for`.
- Parse macro-related tags and call blocks with correct scoping.
- Establish a consistent block/tag parsing framework for nesting + recovery.
- Expand fixtures + snapshots for both valid and invalid constructs.

## Scope (Phase 4)
- Block tags:
  - `{% set %}` single-line assignment
  - `{% set %}...{% endset %}` block assignment
  - `{% block %}...{% endblock %}`
  - `{% extends %}` and `{% include %}` (expression arguments only, no evaluation)
  - `{% import %}` / `{% from %}` (simple forms)
  - `{% macro %}` / `{% endmacro %}`
  - `{% call %}` / `{% endcall %}`
  - `{% raw %}` / `{% endraw %}`
- Use existing expression parser for tag arguments where applicable.
- Continue to prefer error recovery over hard failure.

## AST Additions
- `Set(name, value)` and `SetBlock(name, body)`
- `Block(name, body)`
- `Extends(template_expr)`
- `Include(template_expr, with_context?, ignore_missing?)` (flags captured, no eval)
- `Import(template_expr, alias)`
- `FromImport(template_expr, names, with_context?)`
- `Macro(name, params, body)`
- `Call(name_or_expr, args, kwargs, body)` (call blocks)
- `Raw(text)`
- Update `Serializer` for new nodes.

## Parser Changes
- Introduce a block-tag dispatch table:
  - Map tag name -> handler function + optional end tags.
  - Centralize parsing of `{% ... %}` to reduce duplication.
- Add parsing for each tag:
  - `set`:
    - `set name = expr` (single line)
    - `set name` followed by body and `{% endset %}`
  - `block` / `endblock`:
    - parse optional block name after `endblock` (diagnostic if mismatch)
  - `extends` / `include` / `import` / `from`:
    - parse template expression and required identifiers/aliases
  - `macro` / `call`:
    - parse parameter list with default expressions
    - `call` allows arguments and a body
  - `raw`:
    - parse literal text until `{% endraw %}` without lexing inner content
- Improve block recovery:
  - When parsing tag body, recover to end tags that match the open tag.
  - Track stack of open tags for diagnostics on mismatch.

## Implementation Notes
- End-tag parsing now optionally consumes a trailing identifier to avoid errors
  for tags like `{% endblock name %}` while deferring mismatch checks to linting.
- Raw blocks concatenate the underlying token lexemes until `{% endraw %}` and
  emit a single `Raw` node with the collected text.

## Diagnostics
- Unknown tag name
- Missing required identifiers/aliases
- Expected `end...` tag but found other tag
- Invalid macro parameter list or default value
- Unexpected tokens in tag arguments

## Fixtures / Snapshots
- Add templates + snapshots for:
  - `set` single-line and block
  - `block` with nested content
  - `extends` + `include`
  - `import` + `from` variants
  - `macro` definitions + `call` blocks
  - `raw` regions containing tag-like text
  - Invalid/mismatched tags for diagnostics + recovery
- Ensure both AST and diagnostics snapshots cover edge cases.

## Added Edge-Case Coverage
- Missing end tags for set/macro/call/raw.
- Malformed import/include flags and missing import names.
- Unknown/stray end tags and extra tokens in tag headers.
- Raw blocks containing nested tag-like text and raw blocks inside blocks.

## CLI Integration
- `src/j2parse.cr --ast` should serialize new node types.
- Add CLI flag idea (optional): `--format` to choose AST or diagnostics only.

## Acceptance Criteria
- New tags parse to correct AST shapes with spans.
- Diagnostics emitted for invalid/mismatched tags with good recovery.
- Snapshot specs pass for added fixtures.

## Progress Checklist
- [x] Parser tag-dispatch framework
- [x] AST nodes + serializer updates
- [x] Tag parsing: set/block/extends/include/import/from
- [x] Tag parsing: macro/call/raw
- [x] Diagnostics + recovery for tags
- [x] Fixtures + snapshots added
