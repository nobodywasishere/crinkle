# Phase 25d — Type Inference & Type-Aware UX

## Objectives
- Introduce a shared type inference engine usable across LSP and linter
- Add type-aware signals to hover/inlay hints/linting
- Improve completion ranking using inferred types (no filtering)
- Capture type inference snapshots in fixtures for regression coverage
- Respect custom schema in inference
- Add lightweight string pooling for performance hot paths

## Status
**COMPLETED**

## Shipped Work
- Shared type inference engine in `src/type_inference/inference.cr`
- Type-aware hover + inlay hints + linter TypeMismatch rule
- Completion ranking using inferred receiver types and callable methods
- Per-document type inference cached in `InferenceEngine`
- Fixture snapshots: `*.type_inference.json` for relevant templates
- Custom schema respected in type inference
- Shared string pool for lexer + HTML tokenizer + LSP inference caches
- Workspace index pooling for macro/block/variable names

## Notes
- `Any` is the top type for unknowns; hover shows it inline, inlay hints hide it.
- Completion ranking uses compatibility checks but does not filter candidates.
- String pooling is intentionally conservative (identifiers/operators/tag names).

## Follow-Ups (Optional)
- Callable method return type inference for `GetAttr`/`GetItem`
- Flow-sensitive type narrowing via tests (`is string`, etc.)
- Macro return type inference
- Improve hover with doc + definition location (compact form)
