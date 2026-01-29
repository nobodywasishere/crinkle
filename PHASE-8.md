# Phase 8 — Linter (Detailed Plan)

## Objectives
- Provide higher-level diagnostics beyond syntax errors.
- Align diagnostic formatting with ameba style (structured, concise, consistent).
- Use consistent diagnostic IDs: `Category/RuleName` (e.g., `Parser/UnknownTag`).
- Group diagnostics by phase/category (Lexer/Parser/Formatter/Renderer + lint categories).
- Keep rendering out of lint scope for now.

## Diagnostic Naming + Organization
- Format: `Category/RuleName`
  - Categories: `Lexer`, `Parser`, `Formatter`, `Renderer`
  - Lint categories: `Lint`, `Style`, `Naming`, `Documentation`, `Performance`, `Security`
  - Examples:
    - `Lexer/UnterminatedExpression`
    - `Parser/UnknownTag`
    - `Formatter/UnbalancedIndent`
    - `Lint/UnusedVariable`
    - `Style/TrailingWhitespace`
    - `Naming/MacroParamShadow`
- Each diagnostic includes:
  - `id` (as above)
  - `severity` (error/warning/info)
  - `message`
  - `span`
- Rendering step is excluded from linting rules for now (renderer diagnostics can still be mapped when provided).

## Existing Diagnostic Mapping
- Do not refactor existing diagnostic IDs in `Jinja::Diagnostic`.
- Map `DiagnosticType` values to linter IDs at the linter boundary.

## Output Style (Ameba-like)
- One diagnostic per line (or JSON entry), brief message, location info.
- Consistent ordering: file > line > column > id > message.
- Optional help text for quick fixes (later).

## Initial Rules (Implemented)
- `Lint/MultipleExtends`
- `Lint/ExtendsNotFirst`
- `Lint/DuplicateBlock`
- `Lint/DuplicateMacro`
- `Lint/UnusedMacro`
- `Style/TrailingWhitespace`
- `Style/MixedIndentation`
- `Style/ExcessiveBlankLines`

## Lint Rule Framework (Ameba-like)
- Rules grouped by category, similar to ameba’s cop architecture.
- `Linter::Rule` with:
  - `id : String`
  - `severity : Severity`
  - `check(template : AST::Template, context : LintContext) : Array(Diagnostic)`
- `LintContext`:
  - Source text
  - AST
  - Symbol table (variables, scopes, macros, imports)
  - Config flags (strictness, allow-unused, etc.)

## Potential Lints (Exhaustive List)

### Template/Structure
- `Lint/UnknownVariable` — unresolved name in output/expr (if symbol table available).
- `Lint/UnusedVariable` — assigned but never used.
- `Lint/UnusedMacro` — declared macro never used.
- `Lint/UnusedImport` — imported namespace/identifiers never referenced.
- `Lint/DuplicateMacro` — macro redefined in same scope.
- `Lint/DuplicateBlock` — block defined more than once in same template.
- `Lint/ConflictingSet` — multiple `set` assignments in same scope without usage.
- `Lint/UnexpectedEndTag` — end tag without start (if parser didn’t already flag).
- `Lint/MissingEndTag` — missing close tag (if parser didn’t already flag).
- `Lint/MultipleExtends` — more than one `{% extends %}` in a template.
- `Lint/ExtendsNotFirst` — extends not at the top of template (Jinja rule).
- `Lint/BlockOutsideExtends` — block usage in template without extends.

### Expressions
- `Lint/UnknownFilter` — filter not registered in environment.
- `Lint/UnknownTest` — test not registered in environment.
- `Lint/UnknownFunction` — function not registered.
- `Lint/InvalidCallTarget` — call on non-callable expression.
- `Lint/InvalidIndexTarget` — index access on non-indexable values (if type info available).
- `Style/RedundantGroup` — unnecessary parentheses.
- `Lint/ConstantCondition` — `if true`/`if false` (if constant-foldable).
- `Lint/ConstantBranch` — branch never taken due to constant condition.
- `Lint/InvalidComparison` — comparisons of incompatible types (if type info available).
- `Lint/DoublePipeFilter` — `||` used as filter separator (legacy/typo).
- `Style/RedundantNot` — `not not` patterns.

### Control Flow + Scoping
- `Lint/ForLoopNotIterable` — iterating over known non-iterable (if type info).
- `Naming/ForLoopShadow` — loop variable shadows outer variable.
- `Naming/SetShadow` — `set` shadows existing name in same scope.
- `Naming/BlockShadow` — block overrides itself within same template.
- `Naming/MacroParamShadow` — macro params shadow outer vars.
- `Lint/CallMissingCaller` — call block expects `caller` but not defined.

### Imports / Includes / Extends
- `Lint/IncludeNotFound` — include references missing template (if loader available).
- `Lint/ImportNotFound` — import references missing template.
- `Lint/FromImportMissingName` — `from import` name not exported.
- `Lint/IncludeWithoutContext` — warn on `without context` if variables used (optional).
- `Lint/CycleDetected` — extends/import cycle (if loader available).

### Whitespace / Formatting
- `Style/TrailingWhitespace` — trailing whitespace in text nodes.
- `Style/MixedIndentation` — tabs + spaces.
- `Style/UnbalancedIndent` — uneven indentation (HTML-aware optional).
- `Style/ExcessiveBlankLines` — multiple blank lines in a row.
- `Style/WhitespaceControlMisuse` — trim markers on both ends where it erases intended text.
- `Documentation/CommentWhitespace` — malformed `{#- -#}` spacing (optional).

### Custom Tags / Extensions
- `Lint/UnknownCustomTag` — custom tag not registered.
- `Lint/MissingCustomEndTag` — custom block tag without end tag.
- `Lint/CustomTagArgs` — invalid argument count/shape (if extension metadata provided).

## Data Flow / Symbol Table Plan
- Build scope tree with:
  - Set variables, loop vars, macro params, import aliases.
- Mark references (reads) vs writes.
- Provide a minimal “known values” pass for constant folding.

## Snapshot + Tests
- `spec/linter_spec.cr` with snapshots:
  - `fixtures/linter_diagnostics/*.json`
- Reuse templates from `fixtures/templates`.
- Keep empty diagnostics out of snapshots.

## Acceptance Criteria
- Diagnostic IDs follow `Category/RuleName`.
- Ameba-like formatting for diagnostics.
- Initial rule set implemented + tests passing.
- Rendering remains out of lint scope for now.
