# Phase 21 — LSP Diagnostics (Detailed Plan)

## Objectives
- Provide real-time error reporting in the editor.
- Wire up existing lexer, parser, and linter diagnostics.
- Publish diagnostics on document changes.

## Priority
**LOW**

## Scope (Phase 21)
- Create diagnostic conversion utilities.
- Implement `textDocument/publishDiagnostics`.
- Wire up lexer/parser/linter pipelines.
- Add debouncing for rapid typing.

## File Structure
```
src/
  lsp/
    diagnostics.cr  # Convert Crinkle diagnostics to LSP format
    server.cr       # Modified to trigger diagnostics
```

## Features
- `textDocument/publishDiagnostics` — Push diagnostics to client
- Convert `Crinkle::Diagnostic` spans to LSP `Range`
- Map diagnostic severity levels (error, warning, info, hint)
- Include diagnostic codes for quick-fix identification
- Debounce diagnostics on rapid typing

## API Design

### Diagnostic Conversion
```crystal
module Crinkle::LSP
  module Diagnostics
    def self.convert(diag : Crinkle::Diagnostic) : LSP::Diagnostic
      LSP::Diagnostic.new(
        range: span_to_range(diag.span),
        severity: map_severity(diag.severity),
        code: diag.id,
        source: "crinkle",
        message: diag.message
      )
    end

    private def self.span_to_range(span : Crinkle::Span) : LSP::Range
      LSP::Range.new(
        start: LSP::Position.new(span.start_line - 1, span.start_column - 1),
        end_pos: LSP::Position.new(span.end_line - 1, span.end_column - 1)
      )
    end

    private def self.map_severity(severity : Crinkle::Severity) : Int32
      case severity
      when .error?   then 1  # Error
      when .warning? then 2  # Warning
      when .info?    then 3  # Information
      else                4  # Hint
      end
    end
  end
end
```

### Analysis Pipeline
```crystal
module Crinkle::LSP
  class Analyzer
    def analyze(document : Document) : Array(Crinkle::Diagnostic)
      diagnostics = [] of Crinkle::Diagnostic

      # Lex
      lexer = Crinkle::Lexer.new(document.text)
      tokens = lexer.tokenize
      diagnostics.concat(lexer.diagnostics)

      # Parse
      parser = Crinkle::Parser.new(tokens)
      ast = parser.parse
      diagnostics.concat(parser.diagnostics)

      # Lint (if AST valid)
      if ast
        linter = Crinkle::Linter.new(ast)
        diagnostics.concat(linter.lint)
      end

      diagnostics
    end
  end
end
```

### Debouncing
```crystal
class Server
  @pending_analysis : Hash(String, Time)
  DEBOUNCE_MS = 150

  def schedule_analysis(uri : String)
    @pending_analysis[uri] = Time.monotonic

    spawn do
      sleep(DEBOUNCE_MS.milliseconds)
      if @pending_analysis[uri]? == Time.monotonic - DEBOUNCE_MS.milliseconds
        run_analysis(uri)
      end
    end
  end
end
```

## Acceptance Criteria
- Diagnostics publish on document open/change.
- Diagnostic ranges align with source positions.
- Severity levels mapped correctly.
- Debouncing prevents excessive recomputation.
- Error highlighting works in editor.

## Checklist
- [x] Create diagnostic conversion utilities (Crinkle → LSP format)
- [x] Implement `publishDiagnostics` notification
- [x] Wire up linter diagnostics on document change (superset of lexer/parser)
- [x] Add debouncing to avoid excessive recomputation
- [x] Test error highlighting in editor
- [x] Verify diagnostic ranges align with source positions
- [x] Add `textDocument/formatting` support (bonus)
