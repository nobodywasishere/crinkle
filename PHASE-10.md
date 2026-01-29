# Phase 10 — HTML-Aware Formatter Engine (Detailed Plan)

## Objectives
- Replace regex heuristics in the formatter with a fault-tolerant HTML parser that can coexist with Crinkle nodes.
- Simplify `Crinkle::Formatter` by extracting HTML parsing + indentation into dedicated, testable components.
- Preserve HTML validity and user intent while keeping Crinkle formatting rules intact.

## Why This Phase
- The current formatter mixes HTML heuristics with Crinkle formatting logic, causing edge-case regressions.
- A tolerant HTML parser enables consistent indentation even when templates are partially invalid or contain Crinkle holes.
- Simpler formatter code reduces accidental formatting drift in unrelated fixtures.

## High-Level Approach
- Introduce an HTML tokenizer + parser that tolerates malformed markup.
- Treat Crinkle tags/expressions as opaque “holes” embedded in HTML text.
- Use the HTML stack to compute indentation and formatting boundaries.
- Keep Crinkle formatting logic separate and deterministic.

## Architecture

### New Components
1. **HTML::Tokenizer**
   - Emits tokens: StartTag, EndTag, SelfClosingTag, Text, Comment, Doctype, JinjaHole.
   - Fault-tolerant: accepts malformed tags, unmatched quotes, and missing closers.
   - Produces offsets/line/column for diagnostics/debugging.

2. **HTML::Parser**
   - Consumes tokens and builds a lightweight tree or stack-only structure.
   - Recovery:
     - Close unclosed tags on EOF.
     - Ignore mismatched end tags by popping until match (or stop if not found).
     - Void elements don’t push to stack.

3. **HTML::IndentEngine**
   - Computes indentation for each logical line segment based on stack depth.
   - Treats “holes” as inline nodes that do not affect HTML stack.

4. **Crinkle::Formatter (simplified)**
   - Responsible only for:
     - Crinkle AST formatting (expressions + statements).
     - Delegating HTML indentation to HTML::IndentEngine when enabled.
     - Rendering text nodes without HTML-specific logic.

### Changes to Formatter
- Remove regex scanning in `Formatter::HtmlContext`.
- Remove ad-hoc HTML open/close tag handling inside `format_text`.
- Use the HTML parser result to align lines for HTML-aware formatting.
- Keep preformatted tags (`script`, `style`, `pre`, `code`, `textarea`) as raw segments.

## Data Model
- **HTML::Node** (optional):
  - `tag`, `children`, `span` (if tree needed)
- **HTML::StackFrame** (if stack-only):
  - `tag`, `indent_affects?`, `preformatted?`
- **JinjaHole**:
  - `span`, `raw_text`
  - Treated as inline text by HTML engine.

## Implementation Steps
1. **Create tokenizer** under `src/formatter/html/` (or `src/html/`).
2. **Implement tolerant parser** that produces stack events and indentation info.
3. **Integrate indent engine** in formatter:
   - Formatter emits lines (text + Crinkle fragments).
   - HTML indent engine post-processes lines to apply indentation.
4. **Remove heuristic code** from formatter (HtmlContext, regex scans).
5. **Update fixtures** focusing on:
   - Mixed HTML + Crinkle with broken HTML.
   - Multiline attributes.
   - Preformatted tags with embedded Crinkle.
   - Inline tags and nested structures.

## Checklist (Current)
- [x] HTML tokenizer/parser/indent engine implemented (fault-tolerant, stack-based).
- [x] Crinkle holes handled as opaque HTML tokens.
- [x] Formatter delegates HTML indentation to the engine (no regex HtmlContext).
- [x] Multiline attribute indentation and preformatted shifting handled by HTML engine.
- [x] HTML diagnostics emitted for unexpected/mismatched/unclosed tags.
- [x] HTML diagnostics surfaced in CLI output (format/lint).
- [x] Fixtures added for HTML recovery: mismatched tags, missing close, invalid nesting.

## Remaining Scope (If we want to go further)
- [ ] Consider a true HTML tree model (currently stack-only).
- [ ] Decide whether HTML diagnostics should remain formatter-only or be promoted to a dedicated HTML diagnostics pipeline.

## Tests / Fixtures
- New fixtures in `fixtures/<name>.<ext>.j2` for:
  - Broken HTML with Crinkle blocks.
  - Nested tags with Crinkle `if/for` boundaries.
  - Multiline attributes on void and non-void tags.
  - Preformatted content containing Crinkle tags.
- Snapshot tests ensure stable output.

## Acceptance Criteria
- Formatter no longer uses regex-based HTML parsing.
- Indentation is consistent for all HTML structures (including malformed cases).
- Preformatted tag contents are preserved verbatim.
- Crinkle formatting unaffected by HTML engine changes.
- Formatter code is significantly smaller and clearer.

## Open Questions
- Should the HTML engine be reused by the linter (e.g., HTML structure lints)?
- Should we expose HTML parse diagnostics or keep them internal?
- How to handle HTML attributes with embedded Crinkle (treat as text or parse holes)?
