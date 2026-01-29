# Phase 13 — Language Server (Detailed Plan)

## Objectives
- Provide a minimal, reliable LSP server for Jinja templates with diagnostics on open/change.
- Enable core IDE features: hover, go-to-definition, document symbols, and folding ranges.
- Integrate lexer/parser/linter diagnostics with consistent spans and severity mapping.
- Build a foundation for incremental parsing, caching, and future features (semantic tokens, completion).

## Scope (Phase 13)
- LSP protocol handling over stdio.
- Lifecycle: initialize, initialized, shutdown, exit.
- Text document sync: didOpen, didChange, didClose.
- Diagnostics: lexer + parser + linter mapped into LSP diagnostics.
- Hover and go-to-definition for variables/macros/blocks.
- Document symbols and folding ranges.
- Basic performance strategy (document cache + incremental update strategy).

## Non-Goals (Phase 13)
- Full completion engine (defer to Phase 14+).
- Workspace-wide symbol search.
- Rename, code actions, and formatting (formatter already exists; LSP formatting deferred).
- Cross-file macro import resolution beyond direct includes (basic only).

## Design Overview
- **Server entrypoint**: `src/lsp/server.cr` with a `Jinja::LSP::Server` class.
- **Protocol**: JSON-RPC 2.0 over stdio.
- **Document model**: in-memory `DocumentStore` keyed by URI.
- **Analysis pipeline**: lex -> parse -> lint -> index (symbols + definitions).
- **Diagnostics**: use existing diagnostic IDs and map severities to LSP.
- **Caching**: keep AST + symbol index per document; reanalyze on change.
- **LSP types**: use `lsprotocol-crystal` (`LSProtocol::*`) for LSP structs and JSON serialization.
- **Parsing**: use `LSProtocol.parse_message` to map incoming JSON to typed request/notification classes.

## Protocol Support
- `initialize`: advertise capabilities
  - textDocumentSync: incremental
  - hoverProvider: true
  - definitionProvider: true
  - documentSymbolProvider: true
  - foldingRangeProvider: true
  - semanticTokensProvider: false (optional later)
- `initialized`: no-op or log
- `shutdown` + `exit`
- `textDocument/didOpen`
- `textDocument/didChange`
- `textDocument/didClose`
- `textDocument/hover`
- `textDocument/definition`
- `textDocument/documentSymbol`
- `textDocument/foldingRange`

## Dependencies
- **lsprotocol-crystal**: use the generated `LSProtocol::*` types for request/response payloads and JSON serialization.

## JSON-RPC Message Parsing (lsprotocol-crystal)
- Use `LSProtocol.parse_message(raw_json)` to parse incoming requests/notifications.
- `LSProtocol.parse_message` inspects `method`, `result`, and `error` fields to determine the correct message type via `LSProtocol::METHOD_TO_TYPES`.
- For responses with `result`, it resolves the response type; for errors, it maps to `LSProtocol::ResponseErrorMessage`.
- If a `method` is missing where required, it raises `LSProtocol::ParseError`.

## LSP Type Mapping (lsprotocol-crystal)
- Core lifecycle: `LSProtocol::InitializeParams`, `LSProtocol::InitializeResult`, `LSProtocol::InitializedParams`
- Capabilities: `LSProtocol::ServerCapabilities`, `LSProtocol::TextDocumentSyncOptions`
- Document sync: `LSProtocol::DidOpenTextDocumentParams`, `LSProtocol::DidChangeTextDocumentParams`, `LSProtocol::DidCloseTextDocumentParams`
- Diagnostics: `LSProtocol::PublishDiagnosticsParams`, `LSProtocol::Diagnostic`, `LSProtocol::Range`, `LSProtocol::Position`
- Hover: `LSProtocol::HoverParams`, `LSProtocol::Hover`
- Definition: `LSProtocol::DefinitionParams`, `LSProtocol::Location`, `LSProtocol::LocationLink`
- Symbols: `LSProtocol::DocumentSymbolParams`, `LSProtocol::DocumentSymbol`, `LSProtocol::SymbolInformation`
- Folding: `LSProtocol::FoldingRangeParams`, `LSProtocol::FoldingRange`

## Data Structures
- `Document`
  - `uri : String`
  - `version : Int32`
  - `text : String`
  - `ast : Jinja::AST::Template?`
  - `diagnostics : Array(Jinja::Diagnostic)`
  - `symbols : Jinja::LSP::SymbolIndex`
- `SymbolIndex`
  - `definitions : Hash(String, Array(Location))`
  - `blocks : Hash(String, Location)`
  - `macros : Hash(String, Location)`
  - `variables : Hash(String, Array(Location))`

## Diagnostics Mapping
- Map `Jinja::Diagnostic` to `LSP::Diagnostic`:
  - Severity: error/warning/info
  - Range: convert span (line/col) to LSP range (0-based)
  - Source: `jinja-cr`
  - Code: diagnostic ID (`Parser/UnknownTag` etc.)
- Support `--strict` logic as a server option (optional): warnings as errors for diagnostics.

## Hover Behavior
- Hover content for:
  - Variables: show name, inferred scope (if available), type if inferred
  - Macros: show signature (name + args)
  - Blocks: show block name
- Use simple Markdown text (no external links).
- Fallback: if no symbol found, return empty hover.

## Go-to-Definition Behavior
- For variables/macros/blocks:
  - Prefer closest in-scope definition in the current file.
  - If imported/included file is loaded in DocumentStore, allow jump to that location.
- If no definition, return empty result.

## Document Symbols
- Produce a flat list of symbols for:
  - Blocks
  - Macros
  - Set assignments (variables)
- Use `SymbolKind::Method` for macros, `SymbolKind::Class` for blocks, `SymbolKind::Variable` for vars.

## Folding Ranges
- Use AST nodes to find foldable regions:
  - `{% if %}...{% endif %}`
  - `{% for %}...{% endfor %}`
  - `{% block %}...{% endblock %}`
  - `{% macro %}...{% endmacro %}`
- Return folding ranges for the body spans only (exclude delimiters where possible).

## Incremental Parsing Strategy
- Start with full reparse on every change (simpler).
- Store previous text and detect if change is small; in that case, re-lex only affected range (optional).
- Use a `DocumentAnalyzer` class to encapsulate re-analysis and caching.

## Implementation Plan
1. **LSP Core**
   - Add `src/lsp/` directory with JSON-RPC framing and message parsing.
   - Add `lsprotocol-crystal` to `shard.yml` and `require "lsprotocol"` in LSP entrypoint.
   - Implement `Server` class for request/notification dispatch, using `LSProtocol::*` types for payloads.

2. **Document Store**
   - Implement `DocumentStore` with add/update/remove and version tracking.
   - Normalize line endings and keep original text for spans.

3. **Diagnostics Pipeline**
   - Implement `Analyzer` to run lex/parse/lint and store diagnostics.
   - Map diagnostics into LSP format and publish via `textDocument/publishDiagnostics`.

4. **Symbol Indexing**
   - Traverse AST to collect:
     - Block declarations
     - Macro definitions + args
     - `set` assignments
   - Provide lookups for hover/definition.

5. **Request Handlers**
   - didOpen (`LSProtocol::DidOpenTextDocumentParams`): store doc, analyze, publish diagnostics
   - didChange (`LSProtocol::DidChangeTextDocumentParams`): update text, reanalyze, publish diagnostics
   - didClose (`LSProtocol::DidCloseTextDocumentParams`): drop doc, clear diagnostics
   - hover (`LSProtocol::HoverParams`): resolve symbol at position
   - definition (`LSProtocol::DefinitionParams`): resolve definition location
   - documentSymbol (`LSProtocol::DocumentSymbolParams`): return symbol list
   - foldingRange (`LSProtocol::FoldingRangeParams`): return folding ranges

6. **Testing**
   - Unit tests for symbol indexing and position resolution.
   - Integration tests for LSP messages (initialize -> open -> hover).
   - Fixtures for documents with macros/blocks/variables.

7. **Docs**
   - README: usage example for `jinja-lsp` via stdio.
   - Document supported capabilities and limitations.

## Progress Update (January 29, 2026)
- Implemented `jinja lsp` CLI entrypoint and LSP server skeleton.
- JSON-RPC parsing via `LSProtocol.parse_message` with typed request/notification handling.
- Document store + analyzer pipeline (lexer + parser + symbol index).
- Diagnostics publishing on open/change/close.
- Implemented hover, definition, document symbols, and folding ranges.
- Split LSP implementation into focused files:
  - `src/lsp/server.cr` (server orchestration)
  - `src/lsp/transport.cr` (JSON-RPC framing IO)
  - `src/lsp/analyzer.cr` (analysis + symbol indexing)
  - `src/lsp/document_store.cr` (document lifecycle)
  - `src/lsp/resolver.cr` (hover/definition/symbol/folding resolution)
  - `src/lsp/text_scanner.cr` (non-regex text fallback)
  - `src/lsp/mapper.cr` (diagnostic + span mapping)
  - `src/lsp/types.cr` (shared LSP data types)
- Added LSP specs covering initialize, diagnostics, and core request handlers.

## Fixtures / Tests
- `fixtures/lsp_*` templates:
  - `lsp_symbols` — blocks, macros, set vars
  - `lsp_hover` — variable + macro usage
  - `lsp_folding` — nested blocks
  - `lsp_diagnostics` — intentional parse + lint errors
- Add LSP JSON request/response fixtures for integration tests.

## Acceptance Criteria
- LSP server starts and handles initialize/shutdown.
- Diagnostics publish on open/change with correct spans.
- Hover/definition works for symbols in same document.
- Document symbols and folding ranges return expected results.
- Tests cover indexing and at least one full LSP flow.

## Checklist
- [ ] LSP server entrypoint + JSON-RPC framing.
- [ ] DocumentStore with versioned updates.
- [ ] Analyzer pipeline (lex/parse/lint).
- [ ] Diagnostic mapping to LSP.
- [ ] Hover + definition handlers.
- [ ] Document symbols handler.
- [ ] Folding ranges handler.
- [ ] Tests + fixtures.
- [ ] README update for LSP usage.
