# jinja-cr

A Jinja2-compatible lexer, parser, linter, and language server written in Crystal.

## Status
- Phase 0 scaffolding in progress
- Lexer/parser/linter/LSP to follow the roadmap in `PLAN.md`

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
- `src/j2parse.cr <template.j2>`

## Development
- Run specs: `crystal spec`
