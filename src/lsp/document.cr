module Crinkle::LSP
  # Represents an open text document in the LSP server.
  class Document
    getter uri : String
    getter language_id : String
    property text : String
    property version : Int32

    # Cached parse results (lazily computed, invalidated on update)
    @cached_tokens : Array(Token)?
    @cached_ast : AST::Template?
    @cached_diagnostics : Array(::Crinkle::Diagnostic)?

    # Cached analysis results (full LSP diagnostics)
    @cached_lsp_diagnostics : Array(Diagnostic)?
    @cached_analysis_version : Int32?

    def initialize(@uri : String, @language_id : String, @text : String, @version : Int32) : Nil
      @cached_tokens = nil
      @cached_ast = nil
      @cached_diagnostics = nil
      @cached_lsp_diagnostics = nil
      @cached_analysis_version = nil
    end

    # Update the document content (full sync).
    def update(text : String, version : Int32) : Nil
      @text = text
      @version = version
      invalidate_cache
    end

    # Apply an incremental change to the document.
    # Takes a range and replacement text, updates only that portion.
    def apply_change(range : Range, text : String, version : Int32) : Nil
      start_offset = offset_at(range.start)
      end_offset = offset_at(range.end_pos)

      # Replace the range with new text
      before = start_offset > 0 ? @text[0...start_offset] : ""
      after = end_offset < @text.size ? @text[end_offset..] : ""
      @text = before + text + after

      @version = version
      invalidate_cache
    end

    # Invalidate all cached data.
    private def invalidate_cache : Nil
      @cached_tokens = nil
      @cached_ast = nil
      @cached_diagnostics = nil
      @cached_lsp_diagnostics = nil
      @cached_analysis_version = nil
    end

    # Get cached LSP diagnostics if version matches.
    def cached_lsp_diagnostics : Array(Diagnostic)?
      if @cached_analysis_version == @version
        @cached_lsp_diagnostics
      end
    end

    # Cache LSP diagnostics for the current version.
    def cache_diagnostics(diagnostics : Array(Diagnostic)) : Nil
      @cached_lsp_diagnostics = diagnostics
      @cached_analysis_version = @version
    end

    # Clear only the analysis cache (for memory management).
    # Keeps tokens and AST cache intact.
    def clear_analysis_cache : Nil
      @cached_lsp_diagnostics = nil
      @cached_analysis_version = nil
    end

    # Get cached tokens, lexing if needed
    def tokens : Array(Token)
      @cached_tokens ||= begin
        lexer = Lexer.new(@text)
        lexer.lex_all
      end
    end

    # Get cached AST, parsing if needed
    # Returns the AST and any diagnostics from parsing
    def ast : AST::Template
      if cached = @cached_ast
        return cached
      end

      toks = tokens
      parser = Parser.new(toks)
      result = parser.parse
      @cached_ast = result
      @cached_diagnostics = parser.diagnostics
      result
    end

    # Get cached diagnostics from parsing (raw Crinkle::Diagnostic, not LSP format)
    def parse_diagnostics : Array(::Crinkle::Diagnostic)
      # Ensure AST is parsed first (which also caches diagnostics)
      ast
      @cached_diagnostics || Array(::Crinkle::Diagnostic).new
    end

    # Get the number of lines in the document.
    def line_count : Int32
      @text.count('\n') + 1
    end

    # Get a specific line (0-indexed).
    def line(index : Int32) : String?
      lines = @text.split('\n')
      return if index < 0 || index >= lines.size
      lines[index]
    end

    # Convert an LSP position to a byte offset.
    def offset_at(position : Position) : Int32
      offset = 0
      current_line = 0

      @text.each_char_with_index do |char, idx|
        if current_line == position.line
          # Count characters (UTF-16 code units for LSP)
          char_offset = 0
          remaining = @text[offset..]
          remaining.each_char do |rem_char|
            break if rem_char == '\n'
            break if char_offset >= position.character
            char_offset += 1
          end
          return offset + char_offset.clamp(0, remaining.index('\n') || remaining.size)
        end

        if char == '\n'
          current_line += 1
        end
        offset = idx + 1
      end

      # Position beyond end of document
      @text.bytesize
    end

    # Convert a byte offset to an LSP position.
    def position_at(offset : Int32) : Position
      line = 0
      character = 0
      current_offset = 0

      @text.each_char do |char|
        break if current_offset >= offset

        if char == '\n'
          line += 1
          character = 0
        else
          character += 1
        end
        current_offset += 1
      end

      Position.new(line, character)
    end
  end

  # Stores open documents by URI with memory tracking.
  class DocumentStore
    # Maximum number of cached analysis results (LRU eviction)
    MAX_CACHED_ANALYSES = 100

    @documents : Hash(String, Document)
    @access_order : Array(String) # Track access order for LRU eviction

    def initialize : Nil
      @documents = Hash(String, Document).new
      @access_order = Array(String).new
    end

    # Open a new document.
    def open(uri : String, language_id : String, text : String, version : Int32) : Document
      doc = Document.new(uri, language_id, text, version)
      @documents[uri] = doc
      @access_order << uri
      doc
    end

    # Update an existing document (full sync).
    def update(uri : String, text : String, version : Int32) : Document?
      doc = @documents[uri]?
      doc.try(&.update(text, version))
      doc
    end

    # Apply an incremental change to a document.
    def apply_change(uri : String, range : Range, text : String, version : Int32) : Document?
      doc = @documents[uri]?
      doc.try(&.apply_change(range, text, version))
      doc
    end

    # Close a document.
    def close(uri : String) : Document?
      @access_order.delete(uri)
      @documents.delete(uri)
    end

    # Get a document by URI (updates access order for LRU tracking).
    def get(uri : String) : Document?
      if doc = @documents[uri]?
        # Update access order for LRU tracking
        @access_order.delete(uri)
        @access_order << uri
        doc
      end
    end

    # Check if a document is open.
    def open?(uri : String) : Bool
      @documents.has_key?(uri)
    end

    # Get all open document URIs.
    def uris : Array(String)
      @documents.keys
    end

    # Get the number of open documents.
    def size : Int32
      @documents.size
    end

    # Get approximate memory usage in bytes (for monitoring).
    def memory_usage : Int64
      total = 0_i64
      @documents.each_value do |doc|
        # Text content
        total += doc.text.bytesize.to_i64
        # Rough estimate for cached data (if any)
        total += 1024_i64 # Base overhead per document
      end
      total
    end

    # Evict cached analysis from least-recently-used documents.
    # Only evicts cache, not the documents themselves.
    def evict_stale_caches(max_cached : Int32 = MAX_CACHED_ANALYSES) : Int32
      evicted = 0
      docs_with_cache = @access_order.select do |uri|
        @documents[uri]?.try(&.cached_lsp_diagnostics) != nil
      end

      while docs_with_cache.size > max_cached && !docs_with_cache.empty?
        oldest_uri = docs_with_cache.shift
        if doc = @documents[oldest_uri]?
          doc.clear_analysis_cache
          evicted += 1
        end
      end

      evicted
    end
  end
end
