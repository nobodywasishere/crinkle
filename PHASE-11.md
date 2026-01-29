# Phase 11 — Unified fixture & diagnostics layout
**Goal:** Give every fixture template a single cohesive folder of snapshot files so each pass (lexer, parser, formatter, renderer, etc.) reads/writes predictable outputs from `fixtures/<name>.<pass>.<type>.<ext>`, and mirror the same layout under `fixtures/extensions`.

## Outcomes
- A documented naming scheme (`name.lexer.tokens.json`, `name.parser.ast.json`, `name.formatter.output.<ext>.j2`, `name.renderer.output.txt`, `name.diagnostics.json`, etc.) that includes template type suffixes (`.html.j2`, `.md.j2`, etc.).
- One helper per spec run that drives all passes and writes/reads the shared fixtures; diagnostics for every pass are merged into `name.diagnostics.json`.
- All existing fixtures migrated/mapped to the new filenames and regenerated at least once to verify consistency.

## Tasks
1. Build a fixture manager in `spec/spec_helper.cr` supporting:
   * Writing/reading lexer tokens, parser AST, formatter output, renderer output, and diagnostics via the new naming convention.
   * Producing diagnostics output that includes every pass (lexer+parser+renderer+formatter+linter) in a single JSON.
2. Update `spec/lexer_spec.cr`, `spec/parser_spec.cr`, `spec/formatter_spec.cr`, `spec/renderer_spec.cr`, and the existing `extensions` specs to use the manager instead of bespoke snapshot paths.
3. Migrate existing fixtures:
   * Rename/move snapshots into `fixtures/<name>.<pass>.<type>.<ext>` structure.
   * Regenerate JSON/output files to ensure they match the new helper, keeping only one diagnostics JSON per template.
   * Ensure `fixtures/extensions` follows the same naming rules.
4. Document how to add future fixtures under this layout so developers know the conventions and helper usage.

## Checklist
- [ ] Naming convention documented and shared with the team.
- [ ] Unified fixture helper implemented and integrated with all specs.
- [ ] Existing fixtures migrated to new structure + snapshots regenerated.
- [ ] Diagnostics combined into the single `name.diagnostics.json`.
- [ ] Extensions fixtures use the same naming layout.
