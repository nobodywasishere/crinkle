# Phase 25 — LSP Performance & Polish (Detailed Plan)

## Objectives
- Optimize LSP server for production use.
- Handle large templates efficiently.
- Support workspace-wide features.
- Add configuration support.

## Priority
**LOW**

## Scope (Phase 25)
- Implement incremental parsing.
- Add AST and analysis caching.
- Switch to incremental document sync.
- Add background processing.
- Support workspace configuration.

## Features

### Incremental Parsing
Only re-parse changed regions:
```crystal
class IncrementalParser
  def update(old_ast : AST::Template, changes : Array(TextChange)) : AST::Template
    # Identify affected nodes
    # Re-lex only changed regions
    # Re-parse affected subtrees
    # Merge with unchanged portions
  end
end
```

### Caching
Cache AST and analysis results per document:
```crystal
class DocumentCache
  @ast_cache : Hash(String, CachedAST)
  @analysis_cache : Hash(String, CachedAnalysis)

  def get_ast(uri : String, version : Int32) : AST::Template?
    entry = @ast_cache[uri]?
    entry if entry && entry.version == version
  end

  def invalidate(uri : String)
    @ast_cache.delete(uri)
    @analysis_cache.delete(uri)
  end
end
```

### Incremental Document Sync
Use `TextDocumentSyncKind.Incremental`:
```crystal
def handle_did_change(params : DidChangeParams)
  document = @documents.get(params.uri)

  params.changes.each do |change|
    if change.range?
      # Apply incremental change
      document.apply_change(change.range, change.text)
    else
      # Full replacement
      document.set_text(change.text)
    end
  end

  schedule_analysis(params.uri)
end
```

### Background Processing
Non-blocking analysis:
```crystal
class Server
  @analysis_channel : Channel(String)
  @analysis_fiber : Fiber

  def initialize
    @analysis_channel = Channel(String).new(100)
    @analysis_fiber = spawn { analysis_loop }
  end

  private def analysis_loop
    loop do
      uri = @analysis_channel.receive
      run_analysis(uri)
    end
  end

  def schedule_analysis(uri : String)
    @analysis_channel.send(uri)
  end
end
```

### Workspace Configuration
Read settings from client:
```crystal
def handle_configuration(params : ConfigurationParams)
  @config = params.items.first.as(CrinkleConfig)
end

struct CrinkleConfig
  property lint_enabled : Bool = true
  property lint_rules : Array(String) = [] of String
  property format_on_save : Bool = false
  property max_file_size : Int32 = 1_000_000
end
```

### Memory Management
Graceful degradation for large files:
```crystal
def analyze_document(document : Document)
  if document.text.size > @config.max_file_size
    # Skip detailed analysis, only basic lexing
    return basic_analysis(document)
  end

  full_analysis(document)
end
```

## Performance Targets
- Document open: < 100ms for typical templates
- Incremental change: < 50ms
- Hover/definition: < 20ms
- Memory: < 100MB for workspace with 1000 templates

## Acceptance Criteria
- Large templates handled without freezing.
- Rapid typing doesn't cause lag.
- Configuration settings respected.
- Memory usage stays bounded.
- Works across VS Code, Neovim, and other editors.

## Checklist
- [x] Implement incremental document sync
- [x] Add AST caching with invalidation on change
- [x] Add background analysis thread/fiber
- [x] Implement `workspace/configuration` for settings
- [x] Implement `workspace/didChangeConfiguration`
- [x] Add graceful degradation for large files
- [x] Add memory usage monitoring/limits
- [x] Add cancellation token support for long-running operations
- [x] Add specs for all new functionality
- [ ] Profile and optimize hot paths
- [ ] Performance testing with large templates
- [ ] Integration testing with multiple editors (VS Code, Neovim, etc.)

## Implementation Summary

### Completed Features

#### Incremental Document Sync
- Changed from `TextDocumentSyncKind::Full` (1) to `TextDocumentSyncKind::Incremental` (2)
- Added `Document#apply_change(range, text, version)` method for range-based updates
- Updated `handle_did_change` to process incremental changes with fallback to full sync

#### Document Caching
- Added `@cached_lsp_diagnostics` and `@cached_analysis_version` to Document
- Server checks cache before running analysis
- Cache invalidated automatically on document update

#### Background Analysis
- Debounced analysis runs in spawned fibers after configurable delay
- Simple pattern: spawn → sleep → check guards → run analysis
- No Channel overhead - direct fiber spawn per request

#### Workspace Configuration Support
- Added `CrinkleLspSettings` struct with configurable options:
  - `lintEnabled` - enable/disable linting (default: true)
  - `maxFileSize` - threshold for large file handling (default: 1MB)
  - `debounceMs` - configurable debounce delay (default: 150ms)
  - `typoDetection` - enable/disable typo detection (default: true)
- Implemented `workspace/didChangeConfiguration` handler

#### Graceful Degradation for Large Files
- Files exceeding `maxFileSize` get basic analysis (lexer + parser only)
- Skips linting and typo detection for performance
- Added `Linter::Issue.from_diagnostic` helper

#### Cancellation Token Support
- `CancellationToken` class with atomic flag for thread-safe cancellation
- Tokens tracked per URI, cancelled when new edit arrives
- Checked before and after analysis to avoid stale diagnostics

#### Memory Usage Monitoring/Limits
- Added LRU tracking in `DocumentStore` with `@access_order`
- Added `memory_usage` method for monitoring
- Added `evict_stale_caches` to limit cached analyses (default: 100)
- Automatic cache eviction after each analysis

### Files Modified
- `src/lsp/server.cr` - Debounced analysis with cancellation, configuration, large file handling
- `src/lsp/document.cr` - Incremental sync, caching, LRU tracking, memory management
- `src/lsp/protocol.cr` - Workspace configuration types, LSP settings struct
- `src/linter/linter.cr` - Added `Issue.from_diagnostic`
- `src/lsp/lsp.cr` - Updated requires
- `spec/lsp_spec.cr` - Added 22 new specs for all new functionality
