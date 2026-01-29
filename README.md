# jinja-cr

A Jinja2-compatible lexer, parser, linter, and language server written in Crystal.

## Status
- Lexer and parser implemented with fixtures and snapshot specs
- Custom tag extensions wired (see `PHASE-5.md`)
- Renderer, linter, LSP follow the roadmap in `PLAN.md`

## Goals
- Faithful Jinja2 v3.1.6 parsing (parse + diagnostics first)
- Homegrown lexer and parser
- Linter and LSP for template authoring

## Structure
- `src/` — core implementation
- `spec/` — Crystal specs
- `fixtures/` — `.j2` templates and JSON snapshots
  - Naming convention: `Jinja::Lexer`, `Jinja::Parser`, `Jinja::AST`, `Jinja::Diagnostics`

## CLI
- `src/j2parse.cr [--ast] [--ext NAME] <template.j2>`
- Demo extensions: `--ext demo`

## Custom Extensions
Register custom tags, filters, tests, and functions through `Jinja::Environment`.

```crystal
env = Jinja::Environment.new

env.register_tag("note", ["endnote"]) do |parser, start_span|
  parser.skip_whitespace
  args = Array(Jinja::AST::Expr).new
  args << parser.parse_expression([Jinja::TokenType::BlockEnd])
  end_span = parser.expect_block_end("Expected '%}' to close note tag.")
  body, body_end = parser.parse_until_any_end_tag(["endnote"], allow_end_name: true)
  body_end ||= end_span

  Jinja::AST::CustomTag.new(
    "note",
    args,
    Array(Jinja::AST::KeywordArg).new,
    body,
    parser.span_between(start_span, body_end)
  )
end

env.register_filter("upper") do |value, _args, _kwargs|
  value.to_s.upcase
end
```

Pass the environment to the parser:

```crystal
parser = Jinja::Parser.new(tokens, env)
```

Notes:
- Built-in tags are reserved by default. Set `Environment.new(override_builtins: true)`
  and mark extensions with `override: true` to replace built-ins.
- Use `parse_until_any_end_tag` for block-style custom tags with recovery.

## Development
- Run specs: `crystal spec`
