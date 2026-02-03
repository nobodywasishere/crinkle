# Phase 25b — Workspace Indexing & Global Refactors

## Objectives
- Implement a workspace indexer to analyze *all* templates, not just open files
- Enable workspace-wide rename (variables, macros, blocks) across unopened files
- Provide document symbols for all files (pre-indexed, not only in analyzer cache)
- Scale workspace symbols with a persistent index
- Enable workspace-wide auto-import suggestions for macros (and optional filters/tests)

## Priority
**LOW** - Follow-up to Phase 25a advanced LSP features

## Motivation

Phase 25a added advanced LSP features, but they currently only operate on
open/analyzed documents. This phase introduces a workspace indexer so features
work across the entire project, including unopened files:

- Rename should update every affected file
- Workspace symbols should be complete
- Document symbols should be available for any file
- Auto-import should suggest items from any template in the workspace

## Features

### 1. Workspace Indexer

Introduce a background indexer that:
- Discovers templates in configured template roots
- Parses and stores symbol data for each file
- Tracks relationships (extends/include/import)
- Refreshes incrementally on file changes

**Index data (per file):**
- Macros (name, span)
- Blocks (name, span)
- Variables (set/setblock)
- Imports / from-imports
- Template relationships

### 2. Workspace Rename (All Files)

Enhance rename provider to:
- Use workspace index instead of only open docs
- Apply edits to unopened files via WorkspaceEdit
- Resolve imports/exports and macro definitions across templates

**Scope:**
- Macros (definition + call sites + import usages)
- Blocks (definition + overrides in inheritance tree)
- Variables (same-file only unless future scope expansion)

### 3. Document Symbols for Any File

Implement a document symbol provider that:
- Uses the index for unopened files
- Falls back to on-demand parse if file not indexed

### 4. Workspace Symbols Backed by Index

Workspace symbols should:
- Query the index store (not in-memory analyzer cache only)
- Support fuzzy matching and relevance scoring
- Return stable results independent of editor state

### 5. Workspace Auto-Import (Fancy Suggestions)

Enhance code actions to suggest imports based on workspace index:
- Unknown macro/function diagnostics trigger import suggestions from any file
- Suggestions include file path, export name, and alias if needed
- Prefer closest match by path proximity and name similarity

Example:
```
{{ button("Submit") }}
  ⚡ Quick fix: Import 'button' from "macros/buttons.html.j2"
```

### 6. Workspace Auto-Import for Filters/Tests (Optional)

If custom schema defines filters/tests in other files, suggest adding schema
references or imports (if applicable) via code actions.

## Implementation

### Indexer Architecture

- **File discovery**:
  - Use template_paths from config
  - Track .j2/.html.j2 and other configured extensions
  - Store URI + relative path

- **Index store**:
  - In-memory map keyed by URI
  - Persist to disk optionally (future)
  - Each entry includes parsed AST metadata + symbol spans

- **Incremental updates**:
  - Watch for file changes (already handled in server)
  - Re-index on change
  - Evict stale entries for deleted files

### Rename Provider Integration

- Replace document-store scanning with index queries
- For each affected URI:
  - Load text from disk if not open
  - Compute edits
  - Apply WorkspaceEdit with full file paths

### Document Symbol Provider

- Implement `textDocument/documentSymbol` for unopened files
- For opened files, prefer AST from parser
- For unopened, query index store or parse on demand

## Acceptance Criteria

### Workspace Indexer
- [x] Indexer scans template roots on init
- [x] Index updates on file change
- [x] Index data includes macros, blocks, set vars

### Workspace Rename
- [x] Macro rename updates all files in project
- [x] Block rename updates inheritance chain
- [x] Rename works for unopened files

### Document Symbols
- [x] Symbols returned for unopened files
- [x] Open file symbols still correct

### Workspace Symbols
- [x] Results independent of open docs
- [x] Large project performance acceptable

### Auto-Import
- [x] Auto-import suggestions across unopened files

## Checklist

### Indexer
- [x] Create index store type
- [x] Add file discovery from template_paths
- [x] Index on init and update on file changes

### Rename
- [x] Integrate index data
- [x] Load unopened files from disk
- [x] Emit edits for unopened files

### Document Symbols
- [x] Implement provider (index-backed)
- [x] Wire up server handler

### Workspace Symbols
- [x] Use index store
- [x] Keep fuzzy matching

### Auto-Import
- [x] Use index store to resolve candidates
- [x] Rank suggestions by proximity and name match
- [x] Apply edits to unopened files

### Testing
- [x] Workspace rename on unopened file
- [ ] Document symbols on unopened file
- [ ] Indexer performance in large workspace
- [x] Auto-import suggestions across unopened files

## Dependencies

- **Phase 25a**: Advanced LSP features + provider scaffolding
