# Phase 7 — Formatter (Detailed Plan)

## Objectives
- Format Jinja2 templates with consistent, configurable style.
- Provide HTML-aware indentation that aligns Crinkle blocks with surrounding markup.
- Preserve semantic content while normalizing whitespace and spacing.
- Establish fixtures with before/after formatting samples.

## Scope (Phase 7)
- Comment preservation (lexer/parser extension):
  - Add `CommentStart` (`{#`) and `CommentEnd` (`#}`) token types to lexer
  - Add `AST::Comment` node type with `text : String` and `span : Span`
  - Parser emits `Comment` nodes in template body
  - Renderer ignores `Comment` nodes (no output)
  - Formatter preserves comments with proper indentation
- Fault-tolerant formatter:
  - Continue formatting even when AST contains errors
  - Use source spans to preserve unformattable regions as-is
  - Emit diagnostics for formatting issues without failing
- Core formatter with:
  - AST-based traversal for structural decisions
  - Token-aware reconstruction for expression spacing
  - Configurable indent, spacing, and line length options
- HTML-aware mode:
  - Track HTML tag nesting in Text nodes via heuristics
  - Align Crinkle block indentation with HTML context
  - Skip formatting inside `<pre>`, `<code>`, `<script>` tags
- Expression formatting:
  - Consistent spacing around operators (`a + b`)
  - Spacing inside braces (`{{ x }}` vs `{{x}}`)
  - Filter chains (`value | upper | trim`)
  - Function calls with args/kwargs
- Statement formatting:
  - Control structures (`if`, `for`, `set`, `block`)
  - Template features (`extends`, `include`, `import`, `macro`)
  - Whitespace control marker preservation (`{%-`, `-%}`)
  - Raw blocks (preserved exactly)
- Fixtures:
  - Unformatted templates in `fixtures/<name>.<ext>.j2`
  - Expected output in `fixtures/<name>.formatter.output.<ext>.j2`

## Design Approach
- **Hybrid AST + Token**: Use AST for structure, tokens for expression reconstruction.
- **HTML Heuristics**: Simple regex-based tag detection (no full HTML parser).
- **Effective Indent**: Combine HTML context level + Crinkle block nesting level.

## File Structure
```
src/
  formatter/
    formatter.cr      # Crinkle::Formatter class with nested Options, HtmlContext, Printer
  crinkle.cr          # Add require for formatter

spec/
  fixtures_spec.cr    # Snapshot-based specs

fixtures/
  <name>.<ext>.j2             # Existing templates (shared input)
  <name>.formatter.output.<ext>.j2 # Expected formatted output
```

## API Sketch

### Lexer/Parser Extensions (for comments)
- `Crinkle::TokenType::CommentStart` — `{#` delimiter
- `Crinkle::TokenType::CommentEnd` — `#}` delimiter
- `Crinkle::AST::Comment` (class)
  - `text : String` — comment content (without delimiters)
  - `span : Span`
- Add `Comment` to `AST::Node` union type

### Formatter Components (nested inside `Crinkle::Formatter`)

- `Crinkle::Formatter::Options` (struct)
  - `indent_string : String` (default: `"  "`)
  - `max_line_length : Int32` (default: `120`)
  - `html_aware? : Bool` (default: `true`)
  - `space_inside_braces? : Bool` (default: `true`)
  - `space_around_operators? : Bool` (default: `true`)
  - `normalize_whitespace_control? : Bool` (default: `false`)

- `Crinkle::Formatter::HtmlContext` (class, private)
  - `process_text(text : String) : Nil`
  - `indent_level : Int32`

- `Crinkle::Formatter::Printer` (class, private)
  - `write(text : String)`, `newline`, `indent`, `dedent`
  - `set_indent(level : Int32)`
  - `to_s : String`

- `Crinkle::Formatter` (main class)
  - `initialize(source : String, options : Options = Options.new)`
  - `format : String`

## Key Algorithms

### HTML Tag Tracking
```crystal
def process_text(text : String) : Nil
  text.scan(/<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/) do |match|
    tag = match[1].downcase
    next if VOID_TAGS.includes?(tag) || match[0].ends_with?("/>")

    if match[0].starts_with?("</")
      close_tag(tag)
    elsif INDENT_TAGS.includes?(tag)
      open_tag(tag)
    end
  end
end
```

### Effective Indent Calculation
```crystal
def compute_effective_indent : Int32
  base = @options.html_aware? ? @html_context.indent_level : 0
  base + @crinkle_indent
end
```

## Fixtures / Snapshots
- Input templates: reuse existing `fixtures/<name>.<ext>.j2`
- Expected output in `fixtures/<name>.formatter.output.<ext>.j2`
- Use `assert_text_snapshot` pattern from existing specs
- Test categories:
  - Basic expressions (literals, operators, filters)
  - Control structures (if/elif/else, for/else)
  - Nested Crinkle blocks
  - HTML + Crinkle mixed content
  - Whitespace control markers
  - Raw blocks and edge cases
  - Templates with parse errors (fault-tolerance)

## Example Transformations

### Basic formatting
**Input:**
```jinja
<div>
{%if show%}<span>{{name|upper}}</span>{%endif%}
</div>
```

**Output:**
```jinja
<div>
  {% if show %}
    <span>{{ name | upper }}</span>
  {% endif %}
</div>
```

### Comment preservation
**Input:**
```jinja
{#TODO: add error handling#}
{% if user %}{# Check user exists #}
Hello, {{ user.name }}
{% endif %}
```

**Output:**
```jinja
{# TODO: add error handling #}
{% if user %}
  {# Check user exists #}
  Hello, {{ user.name }}
{% endif %}
```

## Acceptance Criteria
- Formatter produces consistent output for all test fixtures.
- Fault-tolerant: templates with parse errors still format valid regions.
- HTML-aware mode aligns Crinkle blocks with HTML indentation.
- Options are configurable and respected.
- Snapshot specs pass for formatter input/output pairs.
- Idempotent: formatting already-formatted output yields same result.

## Progress Checklist
- [x] Lexer: CommentStart/CommentEnd token types
- [x] Parser: AST::Comment node type
- [x] Renderer: ignore Comment nodes
- [x] Formatter::Options struct implemented
- [x] Formatter::Printer class implemented
- [x] Formatter::HtmlContext class implemented
- [x] Formatter class with AST traversal
- [x] Expression formatting (all 12 expr types)
- [x] Statement formatting (all 17 node types)
- [x] Comment formatting with indentation
- [x] Fault-tolerance for parse errors
- [x] HTML-aware indentation working
- [x] Whitespace-control delimiter preservation (`-` in `{%-`, `-%}`, `{{-`, `-}}`, `{#-`, `-#}`)
- [x] Formatter fixtures created
- [x] Formatter specs passing
- [x] Idempotency verified

## Out of Scope (Future)
- Automatic line breaking for very long expressions
- Import sorting/organization
- CLI tool integration (potential Phase 7.5)
