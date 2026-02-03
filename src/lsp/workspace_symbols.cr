module Crinkle::LSP
  # Provides workspace-wide symbol search.
  # Uses workspace index if available, otherwise falls back to inference cache.
  class WorkspaceSymbolProvider
    @inference : InferenceEngine
    @index : WorkspaceIndex?

    def initialize(@inference : InferenceEngine, @index : WorkspaceIndex? = nil) : Nil
    end

    # Search for symbols across all known templates.
    def symbols(query : String) : Array(SymbolInformation)
      results = Array(SymbolInformation).new

      # Search macros
      macro_source.each do |uri, macros|
        macros.each do |macro_info|
          if fuzzy_match?(macro_info.name, query)
            if span = macro_info.definition_span
              results << SymbolInformation.new(
                name: macro_info.name,
                kind: SymbolKind::Method,
                location: Location.new(uri: uri, range: span_to_range(span)),
                container_name: extract_filename(uri)
              )
            end
          end
        end
      end

      # Search blocks
      block_source.each do |uri, blocks|
        blocks.each do |block_info|
          if fuzzy_match?(block_info.name, query)
            if span = block_info.definition_span
              results << SymbolInformation.new(
                name: block_info.name,
                kind: SymbolKind::Class,
                location: Location.new(uri: uri, range: span_to_range(span)),
                container_name: extract_filename(uri)
              )
            end
          end
        end
      end

      # Search set variables (top-level)
      variable_source.each do |uri, variables|
        variables.each do |var_info|
          # Only include set/set_block variables (not loop vars or params)
          next unless var_info.source.set? || var_info.source.set_block?
          if fuzzy_match?(var_info.name, query)
            if span = var_info.definition_span
              results << SymbolInformation.new(
                name: var_info.name,
                kind: SymbolKind::Variable,
                location: Location.new(uri: uri, range: span_to_range(span)),
                container_name: extract_filename(uri)
              )
            end
          end
        end
      end

      # Sort by relevance (exact matches first, then by score)
      results.sort_by! { |symbol| -match_score(symbol.name, query) }
      results
    end

    private def macro_source : Hash(String, Array(MacroInfo))
      if index = @index
        index.all_macros
      else
        @inference.all_macros
      end
    end

    private def block_source : Hash(String, Array(BlockInfo))
      if index = @index
        index.all_blocks
      else
        @inference.all_blocks
      end
    end

    private def variable_source : Hash(String, Array(VariableInfo))
      if index = @index
        index.all_variables
      else
        @inference.all_variables
      end
    end

    # Fuzzy match a name against a query
    private def fuzzy_match?(name : String, query : String) : Bool
      return true if query.empty?

      # Case-insensitive containment check
      name_lower = name.downcase
      query_lower = query.downcase

      # Direct substring match
      return true if name_lower.includes?(query_lower)

      # Fuzzy match: all query chars appear in order
      query_idx = 0
      name_lower.each_char do |char|
        if char == query_lower[query_idx]
          query_idx += 1
          return true if query_idx >= query_lower.size
        end
      end

      false
    end

    # Score a match (higher is better)
    private def match_score(name : String, query : String) : Int32
      return 100 if query.empty?

      name_lower = name.downcase
      query_lower = query.downcase

      # Exact match
      return 100 if name_lower == query_lower

      # Prefix match
      return 90 if name_lower.starts_with?(query_lower)

      # Contains match
      return 80 if name_lower.includes?(query_lower)

      # Word boundary match (e.g., "rb" matches "render_button")
      if word_boundary_match?(name_lower, query_lower)
        return 70
      end

      # Fuzzy match score based on character positions
      fuzzy_score(name_lower, query_lower)
    end

    # Check if query matches at word boundaries
    private def word_boundary_match?(name : String, query : String) : Bool
      # Extract first chars of each word
      boundaries = String.build do |str|
        prev_underscore = true
        name.each_char do |char|
          if char == '_'
            prev_underscore = true
          elsif prev_underscore
            str << char
            prev_underscore = false
          end
        end
      end

      boundaries.includes?(query)
    end

    # Calculate fuzzy match score
    private def fuzzy_score(name : String, query : String) : Int32
      score = 0
      query_idx = 0
      consecutive = 0

      name.each_char_with_index do |char, idx|
        next if query_idx >= query.size

        if char == query[query_idx]
          # Bonus for consecutive matches
          consecutive += 1
          score += 10 + consecutive * 5

          # Bonus for matching at start or after underscore
          if idx == 0 || (idx > 0 && name[idx - 1] == '_')
            score += 20
          end

          query_idx += 1
        else
          consecutive = 0
        end
      end

      # Only count if we matched all query chars
      query_idx >= query.size ? score : 0
    end

    # Extract filename from URI
    private def extract_filename(uri : String) : String
      path = uri.sub(/^file:\/\//, "")
      File.basename(path)
    end

    # Convert a Span (1-based lines from lexer) to an LSP Range (0-based lines)
    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column)
      )
    end
  end
end
