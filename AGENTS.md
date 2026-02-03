# Agent Development Guide

This document provides essential information for AI agents working on the crinkle project.

## Project Overview

**crinkle** is a Jinja2-compatible template engine for Crystal featuring:
- Fault-tolerant lexer and parser with precise error recovery
- AST-based renderer with diagnostics
- HTML-aware formatter
- Linter with customizable rules
- CLI tool for all operations

## Architecture

```
┌─────────┐
│ Source  │
└────┬────┘
     │
     v
┌─────────┐     ┌──────────────┐
│  Lexer  │────>│ Token Stream │
└─────────┘     └──────┬───────┘
                       │
                       v
┌─────────┐     ┌──────────────┐     ┌────────────┐
│ Parser  │────>│     AST      │────>│  Renderer  │
└─────────┘     └──────┬───────┘     └─────┬──────┘
                       │                    │
                       v                    v
                ┌──────────────┐     ┌────────────┐
                │  Formatter   │     │   Output   │
                └──────────────┘     └────────────┘
                       │
                       v
                ┌──────────────┐
                │    Linter    │
                └──────────────┘
```

Each pass is independent and fault-tolerant - parsing continues after errors, formatting works on incomplete ASTs, etc.

## Directory Structure

```
crinkle/
├── src/
│   ├── crinkle.cr              # Main module, exports public API
│   ├── lexer/
│   │   └── lexer.cr            # Tokenization with error recovery
│   ├── parser/
│   │   └── parser.cr           # AST construction with diagnostics
│   ├── ast/
│   │   ├── ast.cr              # AST node definitions
│   │   └── serializer.cr       # JSON serialization for snapshots
│   ├── renderer/
│   │   └── renderer.cr         # Template evaluation and output
│   ├── formatter/
│   │   └── formatter.cr        # HTML-aware formatting
│   ├── linter/
│   │   └── runner.cr           # Linting rules and execution
│   ├── runtime/
│   │   ├── value.cr            # Value type union
│   │   ├── object.cr           # Object protocol
│   │   └── ...                 # SafeString, Undefined, etc.
│   ├── environment.cr          # Extension registry
│   ├── diagnostic.cr           # Error/warning reporting
│   └── cli/
│       └── cli.cr              # Command-line interface
├── spec/
│   ├── *_spec.cr               # Unit tests
│   └── fixtures_spec.cr        # Snapshot tests
├── fixtures/                   # Test templates and snapshots
│   ├── lexer/                  # Token-level tests (9 fixtures)
│   ├── parser/                 # AST construction tests (77 fixtures)
│   ├── formatter/              # Formatting tests (51 fixtures)
│   ├── linter/                 # Linting rule tests (11 fixtures)
│   ├── renderer/               # Execution tests (22 fixtures)
│   ├── std_filters/            # Filter tests (1 fixture)
│   ├── std_tests/              # Test tests (1 fixture)
│   ├── std_functions/          # Function tests (empty)
│   ├── integration/            # End-to-end tests (6 fixtures)
│   └── extensions/             # Extension tag tests (6 fixtures)
└── planning/                   # Phase plans and roadmap
    ├── PLAN.md                 # Master plan
    └── PHASE-*.md              # Detailed phase docs
```

## Key Concepts

### Fault Tolerance

Every pass must continue after errors:
- **Lexer**: Emits error tokens, continues lexing
- **Parser**: Synchronizes at statement boundaries, emits error nodes
- **Formatter**: Formats valid regions, preserves invalid regions as-is
- **Renderer**: Returns partial output with diagnostics

### Diagnostics

All errors use the `Diagnostic` type with:
- Severity: `Error`, `Warning`, `Info`, `Hint`
- Message: Human-readable description
- Span: Precise source location (line, column, offset)
- ID: Categorized identifier (e.g., `Parser/UnexpectedToken`)

### Snapshots

Tests use JSON snapshots that auto-update:
```crystal
assert_snapshot("fixtures/example.parser.ast.json", actual_ast)
```

When snapshots differ, specs fail showing the diff. Update by regenerating.

## Common Workflows

### Adding a New AST Node

1. Define node in `src/ast/ast.cr`:
   ```crystal
   class MyNode < Node
     getter value : String
     def initialize(@value, @span)
     end
   end
   ```

2. Add to union type:
   ```crystal
   alias Node = MyNode | OtherNode | ...
   ```

3. Handle in serializer (`src/ast/serializer.cr`)

4. Parse in `src/parser/parser.cr`

5. Render in `src/renderer/renderer.cr`

6. Format in `src/formatter/formatter.cr`

### Adding a Builtin Filter

1. Register in `src/environment.cr`:
   ```crystal
   @filters["myfilter"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
     # Implementation
   end
   ```

2. Add test fixture: `fixtures/std_filters/filter_myfilter.html.j2`

3. Run specs to generate snapshots

### Adding a CLI Command

1. Add case in `src/cli/cli.cr`:
   ```crystal
   when "mycommand"
     # Implementation
   ```

2. Update usage text in `print_usage`

3. Test manually: `crystal run src/cli/cli.cr -- mycommand`

## Testing

### Run All Tests
```bash
crystal spec
```

### Always Run After Changes
After any code change, run:
```bash
crystal spec
/Users/margret/.local/bin/ameba
```

### Run Specific Test
```bash
crystal spec spec/lexer_spec.cr
```

### Regenerate Snapshots
Delete outdated snapshots and re-run specs. New snapshots are written automatically.

### Fixture Organization

Fixtures are organized by pipeline stage:
- **lexer/** - Token-level tests (delimiters, whitespace, comments)
- **parser/** - AST construction tests (expressions, statements, control flow)
- **formatter/** - Formatting output tests (indentation, HTML-aware)
- **linter/** - Linting rule tests (duplicate blocks, formatting issues)
- **renderer/** - Execution tests (evaluation, output generation)
- **std_filters/** - Standard library filter tests
- **std_tests/** - Standard library test tests
- **std_functions/** - Standard library function tests
- **integration/** - End-to-end tests combining multiple passes
- **extensions/** - Extension tag tests (custom tags like `{% note %}`)

### Fixture Naming Convention
Within each directory, fixtures follow this naming pattern:
- `name.ext.j2` - Template source (ext is html, md, etc.)
- `name.lexer.tokens.json` - Lexer output
- `name.parser.ast.json` - Parser output
- `name.formatter.output.ext.j2` - Formatter output
- `name.renderer.output.txt` - Renderer output
- `name.diagnostics.json` - Combined diagnostics from all passes

Example: `fixtures/parser/if_else_if.html.j2` with corresponding snapshot files.

## Code Style

### Naming
- Classes: `PascalCase`
- Methods: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`
- Modules: `Crinkle::*`

### Error Handling
- Use diagnostics, not exceptions for template errors
- Parser/lexer should never crash on invalid input
- Prefer error recovery over failing fast

### Value Types
Always wrap values in `Crinkle::Value`:
```crystal
Crinkle.value(42)           # Numbers
Crinkle.value("string")     # Strings
Crinkle.value([1, 2, 3])    # Arrays
Crinkle.variables({...})    # Contexts
```

### Spans
Every AST node has a `span : Span` for error reporting:
```crystal
Crinkle::AST::Literal.new(42, span)
```

Track spans carefully through the parser.

## Important Files

### Core API
- `src/crinkle.cr` - Public exports
- `src/environment.cr` - Extension registry
- `src/diagnostic.cr` - Error reporting

### Parser
- `src/parser/parser.cr` - Recursive descent parser
- Error recovery at statement boundaries
- Pratt parser for expressions

### Renderer
- `src/renderer/renderer.cr` - Template evaluation
- Scope stack for variables
- Filter/test/function calls

### Formatter
- `src/formatter/formatter.cr` - AST-based formatting
- HTML context tracking for indentation
- Whitespace control preservation

## Git Workflow

### Commits
- Use descriptive commit messages
- Commit related changes together

### Git User Configuration

**IMPORTANT:** Use the `--author` flag when committing to identify which AI agent made the change:

**For Claude Opus 4.5:**
```bash
git commit --author="Claude Opus 4.5 <claude@anthropic.com>" -m "message"
```

**For GPT-5.2-Codex:**
```bash
git commit --author="GPT-5.2-Codex <codex@openai.com>" -m "message"
```

This ensures proper attribution in the commit history without overriding the default git configuration.

### Branches
- Work directly on `main` branch
- Atomic commits for features

## Debugging

### CLI Debug Flags
```bash
# Output AST as JSON
crinkle parse template.j2 --format json --pretty

# Output tokens
crinkle lex template.j2 --format json

# See diagnostics in detail
crinkle parse template.j2 --format json --pretty
```

### Print Debugging
```crystal
pp some_value              # Pretty print
puts some_value.inspect    # Detailed inspect
```

## Performance

### Optimization Guidelines
- Parser is hot path - avoid allocations
- Cache frequently accessed values
- Use `String#unsafe_byte_slice` for lexer
- Profile before optimizing

### Benchmarking
```bash
crystal run --release src/cli/cli.cr -- parse large_template.j2
```

## Common Pitfalls

### Parser
- Don't forget error recovery - synchronize at statement boundaries
- Track spans through all nodes
- Handle EOF gracefully

### Renderer
- Wrap all Crystal values in `Crinkle::Value`
- Check for `Undefined` when accessing context
- Escape output (except `SafeString`)

### Formatter
- Preserve whitespace control markers (`-`)
- Don't format inside `{% raw %}` blocks
- Handle parse errors gracefully

## Next Steps

See [planning/PLAN.md](planning/PLAN.md) for roadmap and phase details.

## Questions?

- Check existing code for patterns
- Look at test fixtures for examples
- Read phase plans in `planning/` for context
