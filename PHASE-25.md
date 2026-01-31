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
- [ ] Implement incremental document sync
- [ ] Add AST caching with invalidation on change
- [ ] Profile and optimize hot paths
- [ ] Add background analysis thread/fiber
- [ ] Implement `workspace/configuration` for settings
- [ ] Implement `workspace/didChangeConfiguration`
- [ ] Add graceful degradation for large files
- [ ] Add memory usage monitoring/limits
- [ ] Performance testing with large templates
- [ ] Integration testing with multiple editors (VS Code, Neovim, etc.)
