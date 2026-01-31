# crinkle

A Jinja2-compatible template engine for Crystal with lexer, parser, renderer, formatter, and linter.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  crinkle:
    github: nobodywasishere/crinkle
```

## Quick Start

```crystal
require "crinkle"

# Parse and render a template
source = "Hello, {{ name }}!"
lexer = Crinkle::Lexer.new(source)
parser = Crinkle::Parser.new(lexer.lex_all)
template = parser.parse

renderer = Crinkle::Renderer.new
output = renderer.render(template, {"name" => Crinkle.value("World")})
# => "Hello, World!"
```

## Supported Jinja2 Features

### Expressions
- Variables: `{{ name }}`
- Attribute access: `{{ user.name }}`, `{{ item["key"] }}`
- Filters: `{{ name | upper }}`, `{{ items | join(", ") }}`
- Tests: `{% if value is defined %}`, `{% if items is sequence %}`
- Operators: `+`, `-`, `*`, `/`, `//`, `%`, `**`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `and`, `or`, `not`, `in`, `is`
- Literals: strings, numbers, booleans, lists `[1, 2, 3]`, dicts `{"a": 1}`
- Ternary: `{{ "yes" if active else "no" }}`

### Control Structures
- `{% if %}` / `{% elif %}` / `{% else %}` / `{% endif %}`
- `{% for item in items %}` / `{% else %}` / `{% endfor %}`
- `{% set name = value %}`
- `{% macro name(args) %}` / `{% endmacro %}`
- `{% call %}` / `{% endcall %}`
- `{% block name %}` / `{% endblock %}`
- `{% extends "base.html" %}`
- `{% include "partial.html" %}`
- `{% import "macros.html" as m %}`
- `{% from "macros.html" import macro_name %}`
- `{% raw %}` / `{% endraw %}`

### Whitespace Control
- Trim whitespace: `{%- ... -%}`, `{{- ... -}}`, `{#- ... -#}`

### Comments
- `{# This is a comment #}`

## CLI

```
crinkle <command> [path ...] [options]
```

### Commands

| Command | Description |
|---------|-------------|
| `lex` | Tokenize template, output tokens + diagnostics |
| `parse` | Parse template, output AST + diagnostics |
| `render` | Render template, output HTML + diagnostics |
| `format` | Format template source |
| `lint` | Lint template, output diagnostics |

### Options

| Option | Description |
|--------|-------------|
| `--stdin` | Read template from stdin |
| `--format json\|text\|html\|dot` | Output format (default varies by command) |
| `--pretty` | Pretty-print JSON output |
| `--no-color` | Disable ANSI colors |
| `--strict` | Treat warnings as errors |
| `--max-errors N` | Limit number of diagnostics |
| `--snapshots-dir PATH` | Write snapshot files |

### Examples

```bash
# Lex a template
crinkle lex template.html.j2 --format json --pretty

# Format all templates in current directory
crinkle format

# Lint with strict mode
crinkle lint templates/*.j2 --strict

# Render from stdin
echo "Hello {{ name }}" | crinkle render --stdin
```

## Value Serialization

Wrap Crystal values for use in templates:

```crystal
# Basic values
Crinkle.value("string")
Crinkle.value(42)
Crinkle.value(true)

# Collections
Crinkle.value({"key" => "value"})
Crinkle.value([1, 2, 3])

# Build a context
context = Crinkle.variables({
  "user" => {"name" => "Ada", "active" => true},
  "items" => [1, 2, 3]
})
```

### Custom Objects

Expose Crystal objects to templates with `Crinkle::Object::Auto`:

```crystal
class User
  include Crinkle::Object::Auto

  @[Crinkle::Attribute]
  def name
    "Ada"
  end

  @[Crinkle::Attribute]
  def admin?
    true
  end
end

context = {"user" => Crinkle.value(User.new)}
# Template: {{ user.name }}, admin: {{ user.is_admin }}
```

Methods ending with `?` are automatically exposed as `is_*` (e.g., `admin?` becomes `is_admin`).

### JSON and YAML

`JSON::Any` and `YAML::Any` work directly in templates:

```crystal
data = JSON.parse(%q({"name": "Ada", "scores": [95, 87, 92]}))
context = {"data" => Crinkle.value(data)}
# Template: {{ data.name }}, first score: {{ data.scores[0] }}
```

### Special Values

| Type | Description |
|------|-------------|
| `SafeString` | Pre-escaped HTML that won't be double-escaped |
| `Undefined` | Missing values (renders empty, tracks name for diagnostics) |
| `StrictUndefined` | Raises on any access (for strict mode) |

```crystal
# Mark HTML as safe
Crinkle::SafeString.new("<strong>bold</strong>")

# Explicit undefined with name tracking
Crinkle::Undefined.new("missing_var")
```

## Custom Extensions

### Filters

```crystal
env = Crinkle::Environment.new

env.register_filter("shout") do |value, args, kwargs|
  value.to_s.upcase + "!"
end

env.register_filter("truncate") do |value, args, kwargs|
  length = args[0]?.try(&.as_i?) || 50
  str = value.to_s
  str.size > length ? str[0, length] + "..." : str
end
```

### Tests

```crystal
env.register_test("even") do |value, args, kwargs|
  value.as_i?.try(&.even?) || false
end

# Usage: {% if num is even %}
```

### Custom Tags

```crystal
env.register_tag("note", ["endnote"]) do |parser, start_span|
  parser.skip_whitespace
  args = [parser.parse_expression([Crinkle::TokenType::BlockEnd])]
  end_span = parser.expect_block_end("Expected '%}' to close note tag.")
  body, body_end = parser.parse_until_any_end_tag(["endnote"], allow_end_name: true)

  Crinkle::AST::CustomTag.new(
    "note",
    args,
    [] of Crinkle::AST::KeywordArg,
    body,
    parser.span_between(start_span, body_end || end_span)
  )
end
```

Pass the environment to the parser:

```crystal
parser = Crinkle::Parser.new(tokens, env)
```

## Formatter

Format templates with HTML-aware indentation:

```crystal
source = "{%if x%}<div>{{y}}</div>{%endif%}"
formatter = Crinkle::Formatter.new(source)
formatted = formatter.format
# => "{% if x %}\n  <div>{{ y }}</div>\n{% endif %}"
```

### Options

```crystal
options = Crinkle::Formatter::Options.new(
  indent_string: "  ",        # Indentation (default: 2 spaces)
  max_line_length: 120,       # Target line length
  html_aware: true,           # Align with HTML structure
  space_inside_braces: true,  # {{ x }} vs {{x}}
)
formatter = Crinkle::Formatter.new(source, options)
```

## Diagnostics

All passes (lexer, parser, renderer, linter) emit diagnostics with precise source locations:

```crystal
lexer = Crinkle::Lexer.new(source)
tokens = lexer.lex_all

lexer.diagnostics.each do |diag|
  puts "#{diag.severity}: #{diag.message} at #{diag.span.start_pos.line}:#{diag.span.start_pos.column}"
end
```

Diagnostic severities: `Error`, `Warning`, `Info`, `Hint`

## Development

```bash
crystal spec          # Run tests
crystal build src/cli/cli.cr -o crinkle  # Build CLI
```

### Note on Development

This project was vibe coded using **GPT-5.2-Codex** and **Claude Opus 4.5**.

## Roadmap

See [planning/PLAN.md](planning/PLAN.md) for the development roadmap.

## License

MIT
