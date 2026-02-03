module Crinkle::LSP
  # Definition context types
  enum DefinitionContextType
    None
    Template # extends/include/import/from template path
    Variable # variable name
    Macro    # macro name (call or definition)
    Block    # block name
  end

  # Definition context information
  struct DefinitionContext
    property type : DefinitionContextType
    property name : String

    def initialize(@type : DefinitionContextType, @name : String) : Nil
    end
  end

  # Provides go-to-definition for template references, variables, macros, and blocks
  class DefinitionProvider
    @inference : InferenceEngine
    @root_path : String?

    # Enable debug logging
    class_property? debug : Bool = false

    private def debug(msg : String) : Nil
      STDERR.puts "[DefinitionProvider] #{msg}" if self.class.debug?
    end

    def initialize(@inference : InferenceEngine, @root_path : String?) : Nil
    end

    # Find the definition location for the token at the given position
    def definition(uri : String, text : String, position : Position) : Location?
      lines = text.split('\n')
      return if position.line >= lines.size

      line = lines[position.line]
      return if position.character > line.size

      # First check for template references (existing functionality)
      if template_ref = find_template_reference(line, position.character)
        return resolve_template_location(uri, template_ref)
      end

      # Use token-based analysis for other definitions
      context = analyze_definition_context(text, position)

      case context.type
      when .variable?
        variable_definition(uri, context.name)
      when .macro?
        macro_definition(uri, context.name)
      when .block?
        block_definition(uri, context.name)
      end
    end

    # Find definition for a variable
    private def variable_definition(uri : String, name : String) : Location?
      var_info = @inference.variable_info(uri, name)
      return unless var_info

      if span = var_info.definition_span
        Location.new(uri: uri, range: span_to_range(span))
      end
    end

    # Find definition for a macro
    private def macro_definition(uri : String, name : String) : Location?
      debug "macro_definition(#{uri}, #{name})"
      macro_info = @inference.macro_info(uri, name)
      debug "  macro_info: #{macro_info.inspect}"
      return unless macro_info

      if span = macro_info.definition_span
        debug "  has definition_span"
        # Find the URI where this macro is actually defined
        macro_uri = find_macro_uri(uri, name)
        debug "  macro_uri: #{macro_uri.inspect}"
        if macro_uri
          Location.new(uri: macro_uri, range: span_to_range(span))
        end
      end
    end

    # Find the URI where a macro is defined
    private def find_macro_uri(uri : String, name : String, visited : Set(String) = Set(String).new) : String?
      debug "find_macro_uri(#{uri}, #{name})"
      return if visited.includes?(uri)
      visited << uri

      # First check if it's in the current file (only local macros, not imports)
      local_macros = @inference.local_macros_for(uri).select { |mac| mac.name == name }
      debug "  local_macros: #{local_macros.map(&.name)}"
      return uri unless local_macros.empty?

      # Check ALL related templates (not just extends_path which only returns the first)
      relationships = @inference.relationships_for(uri)
      debug "  relationships: #{relationships.inspect}"

      relationships.each do |template_path|
        debug "  checking relationship: #{template_path}"
        # Try inference engine's URI resolution first (works with virtual URIs)
        related_uri = @inference.resolve_uri(uri, template_path)
        debug "    resolve_uri result: #{related_uri.inspect}"
        if related_uri
          result = find_macro_uri(related_uri, name, visited)
          return result if result
        end
        # Fall back to file-based resolution
        related_uri = resolve_template_uri_from_path(uri, template_path)
        debug "    resolve_template_uri_from_path result: #{related_uri.inspect}"
        if related_uri
          result = find_macro_uri(related_uri, name, visited)
          return result if result
        end
      end

      debug "  returning nil"
      nil
    end

    # Find definition for a block
    private def block_definition(uri : String, name : String) : Location?
      block_info = @inference.block_info(uri, name)
      return unless block_info

      if span = block_info.definition_span
        # Use the source_uri if available, otherwise current file
        target_uri = block_info.source_uri || uri
        Location.new(uri: target_uri, range: span_to_range(span))
      end
    end

    # Convert a Span (1-based lines from lexer) to an LSP Range (0-based lines)
    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column)
      )
    end

    # Analyze context using token-based analysis
    private def analyze_definition_context(text : String, position : Position) : DefinitionContext
      cursor_offset = offset_for_position(text, position)
      return DefinitionContext.new(DefinitionContextType::None, "") if cursor_offset < 0

      lexer = Lexer.new(text)
      tokens = lexer.lex_all

      token_index = find_token_at_offset(tokens, cursor_offset)
      return DefinitionContext.new(DefinitionContextType::None, "") if token_index < 0

      analyze_token_context(tokens, token_index, cursor_offset)
    end

    # Convert LSP line/character position to byte offset
    private def offset_for_position(text : String, position : Position) : Int32
      offset = 0
      line = 0
      text.each_char_with_index do |char, idx|
        return offset + position.character if line == position.line
        if char == '\n'
          line += 1
        end
        offset = idx + 1
      end
      return offset + position.character if line == position.line
      -1
    end

    # Find the index of the token at or containing the given offset
    private def find_token_at_offset(tokens : Array(Token), offset : Int32) : Int32
      tokens.each_with_index do |token, idx|
        next if token.type == TokenType::EOF
        if token.span.start_pos.offset <= offset && offset <= token.span.end_pos.offset
          return idx
        end
      end

      result = -1
      tokens.each_with_index do |token, idx|
        break if token.type == TokenType::EOF
        if token.span.start_pos.offset <= offset
          result = idx
        else
          break
        end
      end
      result
    end

    # Analyze token context to determine what definition to look for
    private def analyze_token_context(tokens : Array(Token), index : Int32, cursor_offset : Int32) : DefinitionContext
      token = tokens[index]

      return DefinitionContext.new(DefinitionContextType::None, "") unless token.type == TokenType::Identifier

      name = token.lexeme

      # Look back to determine context
      prev_significant = find_prev_significant(tokens, index)

      if prev_token = prev_significant
        case prev_token.type
        when TokenType::Identifier
          lexeme = prev_token.lexeme
          # "block" keyword -> block name context
          if lexeme == "block"
            return DefinitionContext.new(DefinitionContextType::Block, name)
          end
          # "call" keyword -> macro context
          if lexeme == "call"
            return DefinitionContext.new(DefinitionContextType::Macro, name)
          end
        end
      end

      # Check if this is a function/macro call (followed by open paren)
      next_token = find_next_significant(tokens, index)
      if next_token && next_token.type == TokenType::Punct && next_token.lexeme == "("
        return DefinitionContext.new(DefinitionContextType::Macro, name)
      end

      # Check broader context
      if in_block_context?(tokens, index)
        first_ident = find_first_ident_after_block_start(tokens, index)
        if first_ident
          case first_ident.lexeme
          when "block"
            return DefinitionContext.new(DefinitionContextType::Block, name)
          when "call"
            return DefinitionContext.new(DefinitionContextType::Macro, name)
          end
        end
        # Default to variable in block context
        return DefinitionContext.new(DefinitionContextType::Variable, name)
      end

      if in_var_context?(tokens, index)
        return DefinitionContext.new(DefinitionContextType::Variable, name)
      end

      DefinitionContext.new(DefinitionContextType::None, "")
    end

    # Find the previous non-whitespace token
    private def find_prev_significant(tokens : Array(Token), index : Int32) : Token?
      idx = index - 1
      while idx >= 0
        return tokens[idx] unless tokens[idx].type == TokenType::Whitespace
        idx -= 1
      end
      nil
    end

    # Find the next non-whitespace token
    private def find_next_significant(tokens : Array(Token), index : Int32) : Token?
      idx = index + 1
      while idx < tokens.size
        return tokens[idx] unless tokens[idx].type == TokenType::Whitespace
        idx += 1
      end
      nil
    end

    # Check if we're inside a block tag ({% ... %})
    private def in_block_context?(tokens : Array(Token), index : Int32) : Bool
      idx = index - 1
      while idx >= 0
        case tokens[idx].type
        when TokenType::BlockStart
          return true
        when TokenType::BlockEnd, TokenType::VarStart, TokenType::VarEnd, TokenType::Text
          return false
        end
        idx -= 1
      end
      false
    end

    # Check if we're inside a variable output ({{ ... }})
    private def in_var_context?(tokens : Array(Token), index : Int32) : Bool
      idx = index - 1
      while idx >= 0
        case tokens[idx].type
        when TokenType::VarStart
          return true
        when TokenType::VarEnd, TokenType::BlockStart, TokenType::BlockEnd, TokenType::Text
          return false
        end
        idx -= 1
      end
      false
    end

    # Find the first identifier after the most recent BlockStart
    private def find_first_ident_after_block_start(tokens : Array(Token), index : Int32) : Token?
      block_start_idx = -1
      idx = index - 1
      while idx >= 0
        if tokens[idx].type == TokenType::BlockStart
          block_start_idx = idx
          break
        elsif tokens[idx].type.in?(TokenType::BlockEnd, TokenType::VarStart, TokenType::VarEnd, TokenType::Text)
          return
        end
        idx -= 1
      end
      return if block_start_idx < 0

      idx = block_start_idx + 1
      while idx < tokens.size && idx <= index
        return tokens[idx] if tokens[idx].type == TokenType::Identifier
        idx += 1 if tokens[idx].type == TokenType::Whitespace
        break unless tokens[idx].type == TokenType::Whitespace
      end
      tokens[idx]? if idx < tokens.size && tokens[idx].type == TokenType::Identifier
    end

    # Find a template reference at the given character position in the line
    private def find_template_reference(line : String, char_pos : Int32) : TemplateReference?
      # Match extends/include/import/from patterns with quoted strings
      patterns = [
        # {% extends "path" %}
        /\{%\s*extends\s+["']([^"']+)["']/,
        # {% include "path" %}
        /\{%\s*include\s+["']([^"']+)["']/,
        # {% import "path" %}
        /\{%\s*import\s+["']([^"']+)["']/,
        # {% from "path" import ... %}
        /\{%\s*from\s+["']([^"']+)["']\s+import/,
      ]

      patterns.each do |pattern|
        if match = line.match(pattern)
          # Get the full match and the captured path
          full_match = match[0]
          path = match[1]

          # Find the position of the path in the line
          match_start = line.index(full_match)
          next unless match_start

          # Find where the quoted string starts within the match
          quote_start = full_match.index('"') || full_match.index('\'')
          next unless quote_start

          path_start = match_start + quote_start + 1
          path_end = path_start + path.size

          # Check if cursor is within the path
          if char_pos >= path_start && char_pos <= path_end
            return TemplateReference.new(path, path_start, path_end)
          end
        end
      end

      nil
    end

    # Resolve a template path to a file location
    private def resolve_template_location(current_uri : String, ref : TemplateReference) : Location?
      # Try to resolve the template path
      resolved_path = resolve_template_path(current_uri, ref.path)
      return unless resolved_path

      # Check if file exists
      return unless File.exists?(resolved_path)

      # Create location pointing to the start of the file
      Location.new(
        uri: path_to_uri(resolved_path),
        range: Range.new(
          start: Position.new(line: 0, character: 0),
          end_pos: Position.new(line: 0, character: 0)
        )
      )
    end

    # Resolve a template path relative to the current template or root
    private def resolve_template_path(current_uri : String, template_path : String) : String?
      # First try relative to current template's directory
      if current_uri.starts_with?("file://")
        current_path = current_uri.sub(/^file:\/\//, "")
        current_dir = File.dirname(current_path)
        relative_path = File.join(current_dir, template_path)
        return relative_path if File.exists?(relative_path)
      end

      # Try relative to root path
      if root = @root_path
        root_relative = File.join(root, template_path)
        return root_relative if File.exists?(root_relative)

        # Try in common template directories
        ["templates", "views", ""].each do |subdir|
          candidate = File.join(root, subdir, template_path)
          return candidate if File.exists?(candidate)
        end
      end

      nil
    end

    # Resolve a template path to a URI
    private def resolve_template_uri_from_path(current_uri : String, template_path : String) : String?
      resolved_path = resolve_template_path(current_uri, template_path)
      return unless resolved_path
      path_to_uri(resolved_path)
    end

    # Convert a file path to a file:// URI
    private def path_to_uri(path : String) : String
      # Ensure absolute path
      abs_path = File.expand_path(path)
      "file://#{abs_path}"
    end
  end

  # Represents a template reference found in the source
  private struct TemplateReference
    property path : String
    property start_pos : Int32
    property end_pos : Int32

    def initialize(@path : String, @start_pos : Int32, @end_pos : Int32) : Nil
    end
  end
end
