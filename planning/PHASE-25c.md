# Phase 25c — LSP Visitor Refactor

## Objectives
- Introduce a shared AST visitor for LSP providers
- Reduce duplicated tree-walk logic across providers
- Keep traversal performance acceptable for large templates
- Support cancellation tokens during long-running traversals

## Priority
**LOW** - Internal refactor for maintainability

## Motivation
Multiple LSP providers implement ad-hoc AST walking (symbols, rename, code
actions, inference, etc.). A shared visitor pattern will centralize traversal,
reduce duplication, and make future features easier to implement consistently.

## Scope
- Add a lightweight visitor in `src/ast/visitor.cr` (or `src/lsp/ast_visitor.cr`)
- Provide default traversal for both `AST::Node` and `AST::Expr`
- Migrate LSP providers incrementally (one per PR/commit)
- Thread a cancellation token through visitor traversal for early exits
- Identify other traversal-heavy subsystems (formatter, linter, renderer) for migration candidates

## Candidate Refactors
- `SymbolProvider` (document symbols)
- `CodeActionProvider` (macro call detection, imports)
- `RenameProvider` (macro/block/variable edits)
- `InferenceEngine` (properties/macros/blocks/vars extraction)
- `Formatter` (formatting walkers, HTML-aware indentation)
- `Linter::Rules` (macro/test/filter scans and arg validation)
- `Renderer` (macro/block collection and template traversal helpers)
- `WorkspaceIndex` (symbol extraction)
- `FoldingProvider` / `InlayHintProvider` (AST walking utilities)

## Design Sketch
- `AST::Visitor`
  - `visit(node : AST::Node)`
  - `visit(expr : AST::Expr)`
  - `visit_children(node)` and `visit_children(expr)`
- Optional `CancellationToken` field or argument to short-circuit traversal
- Subclasses override hooks for specific nodes/expressions
- Avoid allocations inside traversal hot paths

## Acceptance Criteria
- [x] Visitor base exists and is documented
- [x] At least one LSP provider migrated with no behavior change
- [x] No measurable regression in spec runtime for `spec/lsp`
- [x] Cancellation token can interrupt traversal safely

## Checklist
- [x] Add visitor base
- [x] Add cancellation-aware traversal hooks
- [x] Migrate `SymbolProvider`
- [x] Migrate `CodeActionProvider`
- [x] Migrate `RenameProvider`
- [x] Migrate `InferenceEngine`
- [x] Migrate formatter/linter/renderer/workspace index helpers
- [x] Update specs if needed

## Notes
- Keep the visitor small and ergonomic; avoid over-engineering
- Ensure `AST::Expr` traversal matches current ad-hoc logic
