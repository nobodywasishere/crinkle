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

## CLI

```
crinkle lex [path]     # Output tokens
crinkle parse [path]   # Output AST
crinkle render [path]  # Render template
crinkle format [path]  # Format template
crinkle lint [path]    # Lint template
```

Options: `--stdin`, `--format json|text`, `--pretty`, `--strict`

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

### Special Values

- **`SafeString`** - Pre-escaped HTML that won't be double-escaped
- **`Undefined`** - Missing values (renders empty, tracks name for diagnostics)
- **`StrictUndefined`** - Raises on any access (strict mode)

## Custom Extensions

Register custom tags, filters, and tests:

```crystal
env = Crinkle::Environment.new

# Custom filter
env.register_filter("shout") do |value, _args, _kwargs|
  value.to_s.upcase + "!"
end

# Custom tag
env.register_tag("note", ["endnote"]) do |parser, start_span|
  # Parse tag content...
end

parser = Crinkle::Parser.new(tokens, env)
```

## Development

```
crystal spec
```

## Roadmap

See [planning/PLAN.md](planning/PLAN.md) for the development roadmap.

## License

MIT
