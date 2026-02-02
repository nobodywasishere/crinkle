# crinkle — Plan

## Goals
Build a cohesive developer experience for Jinja2 templates in Crystal:
- Fault-tolerant lexer + parser
- AST + diagnostics
- Renderer / execution
- Linter
- Production-ready API (drop-in Crinja replacement)
- Language Server (LSP)

## Phased Plan

### Phase 0 — Baseline + Specs ✅
**Outcome:** Clear scope, repo structure, and fixtures.
→ [PHASE-0.md](PHASE-0.md)

### Phase 1 — Minimal Lexer ✅
**Outcome:** Token stream with precise spans.
→ [PHASE-1.md](PHASE-1.md)

### Phase 2 — Minimal Parser + AST ✅
**Outcome:** Parse a limited but useful subset.
→ [PHASE-2.md](PHASE-2.md)

### Phase 3 — Expression Grammar ✅
**Outcome:** Full expression parsing (no evaluation).
→ [PHASE-3.md](PHASE-3.md)

### Phase 4 — Jinja2 Control Structures + Macros
**Outcome:** Broader language coverage (`set`, `macro`, `import`, `include`, `extends`, `block`, `raw`).
→ [PHASE-4.md](PHASE-4.md)

### Phase 5 — Custom Tags / Extensions
**Outcome:** Parser extensibility for non-core tags.
→ [PHASE-5.md](PHASE-5.md)

### Phase 6 — Renderer / Execution
**Outcome:** Render templates from AST.
→ [PHASE-6.md](PHASE-6.md)

### Phase 7 — Formatter ✅
**Outcome:** Format templates with HTML-structural awareness.
→ [PHASE-7.md](PHASE-7.md)

### Phase 8 — Linter
**Outcome:** Useful diagnostics beyond syntax (ameba-style rules).
→ [PHASE-8.md](PHASE-8.md)

### Phase 9 — CLI (Unified Tooling)
**Outcome:** Cohesive CLI with subcommands: `lex`, `parse`, `render`, `format`, `lint`.
→ [PHASE-9.md](PHASE-9.md)

### Phase 10 — HTML-Aware Formatter Engine
**Outcome:** Replace regex-based HTML heuristics with fault-tolerant HTML parser.
→ [PHASE-10.md](PHASE-10.md)

### Phase 11 — Unified Fixture & Diagnostics Layout
**Outcome:** Each template owns a single bundle of snapshot files.
→ [PHASE-11.md](PHASE-11.md)

### Phase 12 — Crinja Object Serialization Compatibility ✅
**Outcome:** Match Crinja's object serialization surface.
→ [PHASE-12.md](PHASE-12.md)

### Phase 13 — Standard Library & Fixture Reorganization
**Outcome:** Clean separation of builtins and organized test fixtures.
**Priority:** HIGH
→ [PHASE-13.md](PHASE-13.md)

### Phase 14 — Callable Objects (jinja_call)
**Outcome:** Objects can expose callable methods for template invocation.
**Priority:** CRITICAL - Blocks Migration
→ [PHASE-14.md](PHASE-14.md)

### Phase 15 — Required Builtin Filters
**Outcome:** Complete set of 18 filters needed for production templates.
**Priority:** HIGH
→ [PHASE-15.md](PHASE-15.md)

### Phase 16 — Required Builtin Tests ✅
**Outcome:** 29 Jinja2 builtin tests implemented (`filter`/`test` deferred to Phase 17).
**Priority:** HIGH
→ [PHASE-16.md](PHASE-16.md)

### Phase 17 — Environment Access in Filters/Functions
**Outcome:** Custom filters and functions can access the rendering context.
**Priority:** HIGH
→ [PHASE-17.md](PHASE-17.md)

### Phase 18 — Template Loading API
**Outcome:** High-level API for loading and rendering templates with caching.
**Priority:** HIGH
→ [PHASE-18.md](PHASE-18.md)

### Phase 19 — Context Inheritance
**Outcome:** Support for global/per-request context patterns.
**Priority:** MEDIUM
→ [PHASE-19.md](PHASE-19.md)

### Phase 20 — LSP Foundation
**Outcome:** Basic LSP server with document synchronization.
**Priority:** LOW
→ [PHASE-20.md](PHASE-20.md)

### Phase 20a — VS Code Extension
**Outcome:** Minimal VS Code extension for testing LSP features.
**Priority:** LOW (enables testing of subsequent LSP phases)
→ [PHASE-20a.md](PHASE-20a.md)

### Phase 21 — LSP Diagnostics
**Outcome:** Real-time error reporting in the editor.
**Priority:** LOW
→ [PHASE-21.md](PHASE-21.md)

### Phase 22 — LSP Semantic Bridge
**Outcome:** Connect runtime semantic information to the LSP.
**Priority:** LOW - Research/Experimentation
→ [PHASE-22.md](PHASE-22.md)

### Phase 23 — LSP Hover & Navigation
**Outcome:** Contextual information and code navigation.
**Priority:** LOW
→ [PHASE-23.md](PHASE-23.md)

### Phase 24 — LSP Document Features
**Outcome:** Document outline, code folding, semantic tokens.
**Priority:** LOW
→ [PHASE-24.md](PHASE-24.md)

### Phase 25 — LSP Performance & Polish
**Outcome:** Production-ready LSP server with good performance.
**Priority:** LOW
→ [PHASE-25.md](PHASE-25.md)

### Phase 26 — MCP Foundation
**Outcome:** Basic MCP server with JSON-RPC and stdio transport.
**Priority:** MEDIUM
→ [PHASE-26.md](PHASE-26.md)

### Phase 27 — MCP Tools (Template Operations)
**Outcome:** Expose lex/parse/render/format/lint as MCP tools.
**Priority:** MEDIUM
→ [PHASE-27.md](PHASE-27.md)

### Phase 28 — MCP Resources (Template Information)
**Outcome:** Expose builtins and template metadata as MCP resources.
**Priority:** MEDIUM
→ [PHASE-28.md](PHASE-28.md)

### Phase 29 — MCP Prompts (AI Assistance)
**Outcome:** Pre-built prompts for AI-assisted template development.
**Priority:** LOW
→ [PHASE-29.md](PHASE-29.md)

## Production Readiness Summary

Critical path for drop-in Crinja replacement:

| Phase | Feature | Priority |
|-------|---------|----------|
| 13 | Std Library & Fixture Reorg | HIGH |
| 14 | Callable Objects | CRITICAL |
| 15 | 18 Builtin Filters | HIGH |
| 16 | 4 Builtin Tests | HIGH |
| 17 | Environment Access | HIGH |
| 18 | Template Loading API | HIGH |
| 19 | Context Inheritance | MEDIUM |

## Verification

```bash
crystal spec
```

## Definition of Done (per phase)
- Tests passing for all added fixtures.
- Diagnostics include spans and human-friendly messages.
- Minimal public API for lexer/parser results.
- No regressions on previous phases.

## Open Questions
- Exact Jinja2 feature scope and version compatibility?
  - Jinja2 v3.1.6
- Should we parse only, or also evaluate/execute templates?
  - Separate pass for evaluation/execution
- Should we aim for full Jinja2 whitespace/line statement options?
  - Yes
- Do we need integration with existing Crystal Jinja2 libraries (e.g., crinja)?
  - This is a replacement for crinja, so no
- Preferred test framework and formatting for AST snapshots?
  - Use built-in Crystal spec framework
