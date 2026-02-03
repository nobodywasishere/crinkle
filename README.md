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

## Standard Library

Crinkle includes a comprehensive standard library with 46 filters, 31 tests, and 6 functions. The standard library is loaded by default but can be disabled for custom environments.

### Built-in Filters

**String Filters:**
- `upper`, `lower`, `capitalize`, `title` - Case manipulation
- `trim` - Remove leading/trailing whitespace
- `truncate(length, killwords=false, end="...")` - Shorten strings
- `replace(old, new)` - String replacement
- `wordcount` - Count words
- `reverse` - Reverse string or array
- `center(width)` - Center string with padding
- `indent(width, first=false)` - Indent text

**List Filters:**
- `first`, `last` - Get first/last item
- `join(separator)` - Join array items
- `length` - Get size of string, array, or hash
- `sort(reverse=false)` - Sort array
- `unique` - Remove duplicates
- `batch(size, fill_with=nil)` - Group into batches
- `slice(slices, fill_with=nil)` - Divide into slices
- `sum(attribute=nil, start=0)` - Sum numeric values
- `map(attribute)` - Extract attribute from objects
- `select(test)` - Filter items by test
- `reject(test)` - Reject items by test
- `selectattr(attr, test)` - Filter by attribute test
- `rejectattr(attr, test)` - Reject by attribute test
- `default(value, default_value=false)` - Fallback value

**Number Filters:**
- `int(default=0)`, `float(default=0.0)` - Type conversion
- `abs` - Absolute value
- `round(precision=0, method="common")` - Round numbers
- `min`, `max` - Get minimum/maximum
- `pow(exponent)` - Power operation

**HTML Filters:**
- `escape`, `e` - Escape HTML entities
- `safe` - Mark string as safe (no escaping)
- `striptags` - Remove HTML tags
- `urlize(trim_url_limit=nil, nofollow=false)` - Convert URLs to links
- `urlencode` - URL-encode string

**Serialization Filters:**
- `tojson(indent=nil)` - Convert to JSON
- `pprint` - Pretty-print JSON
- `list` - Convert to array
- `string` - Convert to string
- `attr(name)` - Get attribute by name
- `dictsort(case_sensitive=false, by="key", reverse=false)` - Sort dictionary
- `items` - Get key-value pairs

### Built-in Tests

**Type Tests:**
- `defined`, `undefined` - Check if variable exists
- `none` - Check if nil
- `boolean`, `true`, `false` - Boolean checks
- `number`, `integer`, `float` - Numeric type checks
- `string` - String check
- `sequence`, `iterable`, `mapping` - Collection checks
- `odd`, `even` - Parity checks
- `divisibleby(n)` - Divisibility check

**Comparison Tests:**
- `eq(value)`, `equalto(value)` - Equality
- `ne(value)` - Inequality
- `lt(value)`, `lessthan(value)` - Less than
- `gt(value)`, `greaterthan(value)` - Greater than
- `le(value)`, `ge(value)` - Less/greater or equal
- `in(container)` - Containment check

**String Tests:**
- `lower`, `upper` - Case checks
- `startswith(prefix)`, `endswith(suffix)` - String prefix/suffix

### Built-in Functions

- `range(stop)`, `range(start, stop)`, `range(start, stop, step)` - Generate sequences
- `dict(**kwargs)` - Create dictionary
- `namespace(**kwargs)` - Create namespace object for state
- `lipsum(n=5, html=true, min=20, max=100)` - Generate lorem ipsum
- `cycler(*items)` - Create cycling iterator
- `joiner(sep=", ")` - Create joining helper

### Selective Loading

By default, all standard library features are loaded. You can disable this for minimal or custom environments:

```crystal
# Load all standard library (default)
env = Crinkle::Environment.new

# Empty environment (no standard library)
env = Crinkle::Environment.new(load_std: false)

# Selectively load specific modules
env = Crinkle::Environment.new(load_std: false)
Crinkle::Std::Filters::Strings.register(env)  # Only string filters
Crinkle::Std::Tests::Types.register(env)       # Only type tests
Crinkle::Std::Functions::Range.register(env)   # Only range function
```

### Available Modules

**Filters:**
- `Crinkle::Std::Filters::Strings` - String manipulation
- `Crinkle::Std::Filters::Lists` - List/array operations
- `Crinkle::Std::Filters::Numbers` - Numeric operations
- `Crinkle::Std::Filters::Html` - HTML escaping and manipulation
- `Crinkle::Std::Filters::Serialize` - Serialization operations

**Tests:**
- `Crinkle::Std::Tests::Types` - Type checking
- `Crinkle::Std::Tests::Comparison` - Comparisons
- `Crinkle::Std::Tests::Strings` - String checks

**Functions:**
- `Crinkle::Std::Functions::Range` - Range generation
- `Crinkle::Std::Functions::Dict` - Dictionary creation
- `Crinkle::Std::Functions::Debug` - Debug utilities

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
| `lsp` | Start the Language Server Protocol server |

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

## Language Server (LSP)

Crinkle includes a Language Server Protocol server for IDE integration.

### Starting the LSP

```bash
crinkle lsp [options]
```

| Option | Description |
|--------|-------------|
| `--log FILE` | Log to file (for debugging) |
| `--log-level LEVEL` | Log level: debug, info, warning, error |

### LSP Features

- **Diagnostics**: Real-time syntax errors and lint warnings
- **Formatting**: Format templates via editor commands
- **Completions**: Filter, test, function, and property suggestions
- **Hover**: Documentation for filters, tests, and functions
- **Signature Help**: Parameter hints for function calls

### Configuration

The LSP works without any configuration, using the built-in standard library schema. To customize behavior, create `.crinkle/config.yaml`:

```yaml
version: 1

# Inference settings for property completions
inference:
  enabled: true         # Track variable.property usage for suggestions
  cross_template: true  # Share inferred properties across templates

# Custom schema (only needed for custom extensions)
schema:
  path: .crinkle/schema.json
```

### Custom Schema Generation

For projects with custom filters, tests, or functions, generate a schema file so the LSP can provide completions for them:

```crystal
require "crinkle"

# Register your custom extensions first
env = Crinkle::Environment.new
MyApp::Filters.register(env)
MyApp::Tests.register(env)

# Export the schema
Dir.mkdir_p(".crinkle")
File.write(".crinkle/schema.json", Crinkle::Schema.to_pretty_json)
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

You can extend Crinkle with custom filters, tests, and functions. All extensions are registered on an `Environment` instance.

### Custom Filters

Filters transform values in templates using the pipe syntax: `{{ value | filter_name(args) }}`

```crystal
env = Crinkle::Environment.new

# Simple filter with no arguments
env.register_filter("shout") do |value, args, kwargs|
  value.to_s.upcase + "!"
end
# Usage: {{ "hello" | shout }} => "HELLO!"

# Filter with positional arguments
env.register_filter("truncate") do |value, args, kwargs|
  length = args.first?.as?(Int64) || 50_i64
  str = value.to_s
  str.size > length ? str[0...length.to_i] + "..." : str
end
# Usage: {{ text | truncate(20) }}

# Filter with keyword arguments
env.register_filter("pad") do |value, args, kwargs|
  width = args.first?.as?(Int64) || 10_i64
  char = kwargs["char"]?.to_s || " "
  value.to_s.ljust(width.to_i, char[0])
end
# Usage: {{ name | pad(20, char=".") }}

# Filter working with arrays
env.register_filter("multiply") do |value, args, kwargs|
  factor = args.first?.as?(Int64) || 2_i64
  case value
  when Array
    result = Array(Crinkle::Value).new
    value.each { |item| result << item }
    factor.times { result += value }
    result.as(Crinkle::Value)
  else
    value
  end
end
# Usage: {{ [1, 2, 3] | multiply(2) }} => [1, 2, 3, 1, 2, 3]

# Filter working with hashes
env.register_filter("get_keys") do |value, args, kwargs|
  case value
  when Hash(String, Crinkle::Value)
    result = Array(Crinkle::Value).new
    value.each_key { |k| result << k }
    result.as(Crinkle::Value)
  else
    Array(Crinkle::Value).new
  end
end
# Usage: {{ {"a": 1, "b": 2} | get_keys }} => ["a", "b"]
```

**Filter Signature:**
- `value`: The value being filtered
- `args`: Array of positional arguments
- `kwargs`: Hash of keyword arguments
- **Return**: Must return a `Crinkle::Value`

### Custom Tests

Tests return boolean values for conditional checks: `{% if value is test_name %}`

```crystal
env = Crinkle::Environment.new

# Simple test
env.register_test("even") do |value, args, kwargs|
  case value
  when Int64
    value.even?
  else
    false
  end
end
# Usage: {% if count is even %}

# Test with arguments
env.register_test("multiple_of") do |value, args, kwargs|
  divisor = args.first?.as?(Int64)
  return false unless divisor

  case value
  when Int64
    value % divisor == 0
  else
    false
  end
end
# Usage: {% if count is multiple_of(5) %}

# Test working with strings
env.register_test("palindrome") do |value, args, kwargs|
  str = value.to_s
  str == str.reverse
end
# Usage: {% if word is palindrome %}

# Test working with arrays
env.register_test("contains") do |value, args, kwargs|
  search = args.first?
  case value
  when Array
    value.includes?(search)
  when String
    value.includes?(search.to_s)
  else
    false
  end
end
# Usage: {% if items is contains("target") %}
```

**Test Signature:**
- `value`: The value being tested
- `args`: Array of positional arguments
- `kwargs`: Hash of keyword arguments
- **Return**: Must return a `Bool`

### Custom Functions

Functions are called directly and can create new values: `{{ function_name(args) }}`

```crystal
env = Crinkle::Environment.new

# Simple function
env.register_function("greet") do |args, kwargs|
  name = args.first?.to_s || "World"
  "Hello, #{name}!"
end
# Usage: {{ greet("Ada") }}

# Function with keyword arguments
env.register_function("make_user") do |args, kwargs|
  name = kwargs["name"]?.to_s || "Anonymous"
  age = kwargs["age"]?.as?(Int64) || 0_i64

  {
    "name" => name,
    "age" => age,
  } of String => Crinkle::Value
end
# Usage: {% set user = make_user(name="Ada", age=25) %}

# Function returning arrays
env.register_function("repeat") do |args, kwargs|
  value = args.first?
  times = args[1]?.as?(Int64) || 1_i64

  result = Array(Crinkle::Value).new
  times.times { result << value }
  result.as(Crinkle::Value)
end
# Usage: {{ repeat("item", 3) }}

# Generator function
env.register_function("fibonacci") do |args, kwargs|
  n = args.first?.as?(Int64) || 10_i64
  result = Array(Crinkle::Value).new

  a, b = 0_i64, 1_i64
  n.times do
    result << a
    a, b = b, a + b
  end

  result.as(Crinkle::Value)
end
# Usage: {% for num in fibonacci(8) %}{{ num }}{% endfor %}
```

**Function Signature:**
- `args`: Array of positional arguments
- `kwargs`: Hash of keyword arguments
- **Return**: Must return a `Crinkle::Value`

### Organizing Custom Extensions

For larger projects, organize extensions into modules:

```crystal
module MyApp::Templates
  module Filters
    def self.register(env : Crinkle::Environment)
      env.register_filter("currency") do |value, args, kwargs|
        amount = value.as?(Int64 | Float64) || 0
        "$%.2f" % amount
      end

      env.register_filter("slugify") do |value, args, kwargs|
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").strip("-")
      end
    end
  end

  module Tests
    def self.register(env : Crinkle::Environment)
      env.register_test("admin") do |value, args, kwargs|
        case value
        when Hash(String, Crinkle::Value)
          value["role"]?.to_s == "admin"
        else
          false
        end
      end
    end
  end
end

# Register all custom extensions
env = Crinkle::Environment.new
MyApp::Templates::Filters.register(env)
MyApp::Templates::Tests.register(env)
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
