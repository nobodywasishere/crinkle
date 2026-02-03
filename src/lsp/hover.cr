require "./protocol"
require "./schema_provider"
require "./inference"
require "../lexer/lexer"
require "../std/tags"

module Crinkle::LSP
  # Hover context types
  enum HoverContextType
    None
    Filter
    Test
    Function
    Variable
    Macro
    Block
    Tag
  end

  # Hover context information
  struct HoverContext
    property type : HoverContextType
    property name : String

    def initialize(@type : HoverContextType, @name : String) : Nil
    end
  end

  # Provides hover information for filters, tests, functions, variables, macros, blocks, and tags
  class HoverProvider
    @schema_provider : SchemaProvider
    @inference : InferenceEngine

    def initialize(@schema_provider : SchemaProvider, @inference : InferenceEngine) : Nil
    end

    # Get hover information for the given position
    def hover(uri : String, text : String, position : Position) : Hover?
      context = analyze_hover_context(text, position)

      case context.type
      when .filter?
        filter_hover(context.name)
      when .test?
        test_hover(context.name)
      when .function?
        function_hover(context.name)
      when .variable?
        variable_hover(uri, context.name)
      when .macro?
        macro_hover(uri, context.name)
      when .block?
        block_hover(uri, context.name)
      when .tag?
        tag_hover(context.name)
      end
    end

    # Get hover info for a filter
    private def filter_hover(name : String) : Hover?
      filter = @schema_provider.filter(name)
      return unless filter

      # Build markdown documentation
      markdown = String.build do |str|
        str << "```crystal\n"
        str << @schema_provider.filter_signature(filter)
        str << "\n```\n"

        if doc = filter.doc
          str << "\n---\n\n"
          str << doc
        end

        if filter.deprecated?
          str << "\n\n**Deprecated**"
        end

        unless filter.examples.empty?
          str << "\n\n**Examples:**\n\n"
          filter.examples.each do |example|
            str << "```jinja\n"
            str << example.input
            str << "\n```\n"
            str << "-> `#{example.output}`\n\n"
          end
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Get hover info for a test
    private def test_hover(name : String) : Hover?
      test = @schema_provider.test(name)
      return unless test

      markdown = String.build do |str|
        str << "```crystal\n"
        str << @schema_provider.test_signature(test)
        str << "\n```\n"

        if doc = test.doc
          str << "\n---\n\n"
          str << doc
        end

        if test.deprecated?
          str << "\n\n**Deprecated**"
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Get hover info for a function
    private def function_hover(name : String) : Hover?
      func = @schema_provider.function(name)
      return unless func

      markdown = String.build do |str|
        str << "```crystal\n"
        str << @schema_provider.function_signature(func)
        str << "\n```\n"

        if doc = func.doc
          str << "\n---\n\n"
          str << doc
        end

        if func.deprecated?
          str << "\n\n**Deprecated**"
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Get hover info for a variable
    private def variable_hover(uri : String, name : String) : Hover?
      var_info = @inference.variable_info(uri, name)
      return unless var_info

      # Don't show hover for context variables - they're just inferred from usage
      # and don't have useful definition information
      return if var_info.source.context?

      markdown = String.build do |str|
        str << "**#{name}**"

        # Show source type
        source_desc = case var_info.source
                      when .for_loop?    then "loop variable"
                      when .set?         then "assigned variable"
                      when .set_block?   then "block assigned variable"
                      when .macro_param? then "macro parameter"
                      else                    return # shouldn't happen, but be safe
                      end
        str << " - " << source_desc

        # Show detail if available
        if detail = var_info.detail
          str << "\n\n" << detail
        end

        # Show definition location if available (lexer uses 1-based lines)
        if span = var_info.definition_span
          str << "\n\nDefined at line #{span.start_pos.line}"
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Get hover info for a macro
    private def macro_hover(uri : String, name : String) : Hover?
      macro_info = @inference.macro_info(uri, name)
      return unless macro_info

      markdown = String.build do |str|
        str << "```jinja\n"
        str << "{% macro " << macro_info.signature << " %}\n"
        str << "```\n"

        # Show definition location if available (lexer uses 1-based lines)
        if span = macro_info.definition_span
          str << "\nDefined at line #{span.start_pos.line}"
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Get hover info for a block
    private def block_hover(uri : String, name : String) : Hover?
      block_info = @inference.block_info(uri, name)
      return unless block_info

      markdown = String.build do |str|
        str << "**block** `#{name}`"

        # Show where the block is defined (lexer uses 1-based lines)
        if span = block_info.definition_span
          str << "\n\nDefined at line #{span.start_pos.line}"
        end

        # Show source template if it's from a parent
        if source_uri = block_info.source_uri
          if source_uri != uri
            # Extract just the filename
            filename = File.basename(source_uri.sub(/^file:\/\//, ""))
            str << " in `#{filename}`"
          end
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Get hover info for a tag
    private def tag_hover(name : String) : Hover?
      # First check built-in tags
      tag_def = Std::Tags::BUILTINS.find { |tag| tag.name == name }

      if tag_def
        markdown = String.build do |str|
          str << "**#{name}**"
          if tag_def.has_body?
            str << " (block tag)"
          else
            str << " (statement)"
          end

          str << "\n\n" << tag_def.doc

          if end_tag = tag_def.end_tag
            str << "\n\nRequires `{% #{end_tag} %}`"
          end
        end

        return Hover.new(
          contents: MarkupContent.new(kind: "markdown", value: markdown)
        )
      end

      # Check custom tags from schema
      if custom_tag = @schema_provider.tags[name]?
        markdown = String.build do |str|
          str << "**#{name}**"
          if custom_tag.has_body?
            str << " (custom block tag)"
          else
            str << " (custom statement)"
          end

          if doc = custom_tag.doc
            str << "\n\n" << doc
          end
        end

        return Hover.new(
          contents: MarkupContent.new(kind: "markdown", value: markdown)
        )
      end

      nil
    end

    # Analyze context using token-based analysis (like CompletionProvider)
    private def analyze_hover_context(text : String, position : Position) : HoverContext
      # Calculate the byte offset for the cursor position
      cursor_offset = offset_for_position(text, position)
      return HoverContext.new(HoverContextType::None, "") if cursor_offset < 0

      # Lex the text to get tokens with precise positions
      lexer = Lexer.new(text)
      tokens = lexer.lex_all

      # Find the token at the cursor
      token_index = find_token_at_offset(tokens, cursor_offset)
      return HoverContext.new(HoverContextType::None, "") if token_index < 0

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
      # Handle cursor at end of last line
      return offset + position.character if line == position.line
      -1
    end

    # Find the index of the token at or containing the given offset
    private def find_token_at_offset(tokens : Array(Token), offset : Int32) : Int32
      # Find the token that contains the offset
      tokens.each_with_index do |token, idx|
        next if token.type == TokenType::EOF
        if token.span.start_pos.offset <= offset && offset <= token.span.end_pos.offset
          return idx
        end
      end

      # Fall back to finding the last token before the offset
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

    # Analyze token context to determine what's being hovered
    private def analyze_token_context(tokens : Array(Token), index : Int32, cursor_offset : Int32) : HoverContext
      token = tokens[index]

      # We only care about identifiers for hover
      return HoverContext.new(HoverContextType::None, "") unless token.type == TokenType::Identifier

      name = token.lexeme

      # Look back to determine context
      prev_significant = find_prev_significant(tokens, index)

      if prev_token = prev_significant
        case prev_token.type
        when TokenType::Operator
          if prev_token.lexeme == "|"
            # After pipe - filter context
            return HoverContext.new(HoverContextType::Filter, name)
          end
        when TokenType::Identifier
          lexeme = prev_token.lexeme
          # "is" keyword -> test context
          if lexeme == "is"
            return HoverContext.new(HoverContextType::Test, name)
          end
          # "block" keyword -> block name context
          if lexeme == "block"
            return HoverContext.new(HoverContextType::Block, name)
          end
          # "call" keyword -> macro context
          if lexeme == "call"
            return HoverContext.new(HoverContextType::Macro, name)
          end
        when TokenType::BlockStart
          # Right after {% - could be a tag
          return HoverContext.new(HoverContextType::Tag, name)
        end
      end

      # Check if this is a function call (followed by open paren)
      next_token = find_next_significant(tokens, index)
      if next_token && next_token.type == TokenType::Punct && next_token.lexeme == "("
        # Check if this is a built-in function
        if @schema_provider.function(name)
          return HoverContext.new(HoverContextType::Function, name)
        end
        # Could be a macro call
        return HoverContext.new(HoverContextType::Macro, name)
      end

      # Check broader context
      if in_block_context?(tokens, index)
        # Inside a block tag
        first_ident = find_first_ident_after_block_start(tokens, index)
        if first_ident
          if first_ident.span.start_pos.offset == token.span.start_pos.offset
            # This is the first identifier - it's a tag
            return HoverContext.new(HoverContextType::Tag, name)
          end
          case first_ident.lexeme
          when "block"
            return HoverContext.new(HoverContextType::Block, name)
          when "call"
            return HoverContext.new(HoverContextType::Macro, name)
          end
        end
        # Default to variable in block context (could be in if/for conditions)
        return HoverContext.new(HoverContextType::Variable, name)
      end

      if in_var_context?(tokens, index)
        # Inside {{ }} - default to variable
        return HoverContext.new(HoverContextType::Variable, name)
      end

      HoverContext.new(HoverContextType::None, "")
    end

    # Find the previous non-whitespace token
    private def find_prev_significant(tokens : Array(Token), index : Int32) : Token?
      i = index - 1
      while i >= 0
        return tokens[i] unless tokens[i].type == TokenType::Whitespace
        i -= 1
      end
      nil
    end

    # Find the next non-whitespace token
    private def find_next_significant(tokens : Array(Token), index : Int32) : Token?
      i = index + 1
      while i < tokens.size
        return tokens[i] unless tokens[i].type == TokenType::Whitespace
        i += 1
      end
      nil
    end

    # Check if we're inside a block tag ({% ... %})
    private def in_block_context?(tokens : Array(Token), index : Int32) : Bool
      i = index - 1
      while i >= 0
        case tokens[i].type
        when TokenType::BlockStart
          return true
        when TokenType::BlockEnd, TokenType::VarStart, TokenType::VarEnd, TokenType::Text
          return false
        end
        i -= 1
      end
      false
    end

    # Check if we're inside a variable output ({{ ... }})
    private def in_var_context?(tokens : Array(Token), index : Int32) : Bool
      i = index - 1
      while i >= 0
        case tokens[i].type
        when TokenType::VarStart
          return true
        when TokenType::VarEnd, TokenType::BlockStart, TokenType::BlockEnd, TokenType::Text
          return false
        end
        i -= 1
      end
      false
    end

    # Find the first identifier after the most recent BlockStart
    private def find_first_ident_after_block_start(tokens : Array(Token), index : Int32) : Token?
      # First, find the BlockStart
      block_start_idx = -1
      i = index - 1
      while i >= 0
        if tokens[i].type == TokenType::BlockStart
          block_start_idx = i
          break
        elsif tokens[i].type.in?(TokenType::BlockEnd, TokenType::VarStart, TokenType::VarEnd, TokenType::Text)
          return
        end
        i -= 1
      end
      return if block_start_idx < 0

      # Now find the first identifier after it
      i = block_start_idx + 1
      while i < tokens.size && i <= index
        return tokens[i] if tokens[i].type == TokenType::Identifier
        i += 1 if tokens[i].type == TokenType::Whitespace
        break unless tokens[i].type == TokenType::Whitespace
      end
      tokens[i]? if i < tokens.size && tokens[i].type == TokenType::Identifier
    end
  end
end
