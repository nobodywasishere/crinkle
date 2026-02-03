require "./protocol"
require "./schema_provider"
require "./inference"
require "../lexer/lexer"
require "../parser/parser"
require "../std/tags"

module Crinkle::LSP
  # Completion context types
  enum CompletionContextType
    None
    Filter
    Test
    Function
    Property
    Variable # {{ █ }} - suggest known variables
    Block    # {% block █ %} - suggest block names from parent
    Macro    # {% call █ %} - suggest macro names
    Tag      # {% █ %} - suggest tag names
    EndTag   # {% end█ %} - suggest end tags
  end

  # Completion context information
  struct CompletionContext
    property type : CompletionContextType
    property prefix : String
    property variable : String?

    def initialize(@type : CompletionContextType, @prefix : String, @variable : String? = nil) : Nil
    end
  end

  # Provides completions for filters, tests, functions, and properties
  class CompletionProvider
    @schema_provider : SchemaProvider
    @inference : InferenceEngine

    def initialize(@schema_provider : SchemaProvider, @inference : InferenceEngine) : Nil
    end

    # Get completions for the given position in the document
    def completions(uri : String, text : String, position : Position) : Array(CompletionItem)
      # Get the context at the cursor position
      context = analyze_context(text, position)

      case context.type
      when .filter?
        filter_completions(context.prefix)
      when .test?
        test_completions(context.prefix)
      when .function?
        function_completions(context.prefix)
      when .property?
        if var = context.variable
          property_completions(uri, var, context.prefix)
        else
          Array(CompletionItem).new
        end
      when .variable?
        variable_completions(uri, context.prefix)
      when .block?
        block_completions(uri, context.prefix)
      when .macro?
        macro_completions(uri, context.prefix)
      when .tag?
        tag_completions(text, position, context.prefix)
      when .end_tag?
        end_tag_completions(text, position, context.prefix)
      else
        Array(CompletionItem).new
      end
    end

    # Get filter completions
    private def filter_completions(prefix : String) : Array(CompletionItem)
      @schema_provider.filters.values.select do |filter|
        filter.name.starts_with?(prefix)
      end.map do |filter|
        CompletionItem.new(
          label: filter.name,
          kind: CompletionItemKind::Function,
          detail: @schema_provider.filter_args_signature(filter),
          documentation: filter.doc,
          sort_text: filter.name
        )
      end
    end

    # Get test completions
    private def test_completions(prefix : String) : Array(CompletionItem)
      @schema_provider.tests.values.select do |test|
        test.name.starts_with?(prefix)
      end.map do |test|
        CompletionItem.new(
          label: test.name,
          kind: CompletionItemKind::Function,
          detail: @schema_provider.test_args_signature(test),
          documentation: test.doc,
          sort_text: test.name
        )
      end
    end

    # Get function completions
    private def function_completions(prefix : String) : Array(CompletionItem)
      @schema_provider.functions.values.select do |func|
        func.name.starts_with?(prefix)
      end.map do |func|
        CompletionItem.new(
          label: func.name,
          kind: CompletionItemKind::Function,
          detail: @schema_provider.function_signature(func),
          documentation: func.doc,
          sort_text: func.name
        )
      end
    end

    # Get property completions based on inference
    private def property_completions(uri : String, variable : String, prefix : String) : Array(CompletionItem)
      properties = @inference.properties_for(uri, variable)
      properties.select do |prop|
        prop.starts_with?(prefix)
      end.map do |prop|
        CompletionItem.new(
          label: prop,
          kind: CompletionItemKind::Property,
          detail: "property",
          sort_text: prop
        )
      end
    end

    # Get variable completions based on inference
    private def variable_completions(uri : String, prefix : String) : Array(CompletionItem)
      variables = @inference.variables_for(uri)
      variables.select do |var|
        var.name.starts_with?(prefix)
      end.map do |var|
        detail = case var.source
                 when .for_loop?    then "loop variable"
                 when .set?         then "assigned variable"
                 when .set_block?   then "block assigned"
                 when .macro_param? then "macro parameter"
                 else                    "context variable"
                 end
        CompletionItem.new(
          label: var.name,
          kind: CompletionItemKind::Variable,
          detail: detail,
          documentation: var.detail,
          sort_text: var.name
        )
      end
    end

    # Get block name completions (from extended parent templates)
    private def block_completions(uri : String, prefix : String) : Array(CompletionItem)
      blocks = @inference.blocks_for(uri)
      blocks.select do |blk|
        blk.starts_with?(prefix)
      end.map do |blk|
        CompletionItem.new(
          label: blk,
          kind: CompletionItemKind::Struct,
          detail: "block",
          documentation: "Override this block from parent template",
          sort_text: blk
        )
      end
    end

    # Get macro completions based on inference
    private def macro_completions(uri : String, prefix : String) : Array(CompletionItem)
      macros = @inference.macros_for(uri)
      macros.select do |mac|
        mac.name.starts_with?(prefix)
      end.map do |mac|
        CompletionItem.new(
          label: mac.name,
          kind: CompletionItemKind::Function,
          detail: mac.signature,
          documentation: "Macro defined in template",
          insert_text: mac.name,
          sort_text: mac.name
        )
      end
    end

    # Get tag completions
    private def tag_completions(text : String, position : Position, prefix : String) : Array(CompletionItem)
      items = Array(CompletionItem).new

      # Check for unclosed block tags - suggest end tags first
      open_tags = find_open_tags(text, position)
      open_tags.reverse.each do |tag_name|
        end_tag = "end#{tag_name}"
        next unless end_tag.starts_with?(prefix)

        items << CompletionItem.new(
          label: end_tag,
          kind: CompletionItemKind::Keyword,
          detail: "close #{tag_name}",
          documentation: "Close the unclosed {% #{tag_name} %} block",
          sort_text: "!#{end_tag}" # ! sorts before letters, prioritizing end tags
        )
      end

      # Add built-in tags
      Std::Tags::BUILTINS.each do |tag|
        next unless tag.name.starts_with?(prefix)
        items << CompletionItem.new(
          label: tag.name,
          kind: CompletionItemKind::Keyword,
          detail: tag.has_body? ? "block tag" : "statement",
          documentation: tag.doc,
          sort_text: tag.name
        )
      end

      # Add custom tags from schema provider
      @schema_provider.tags.each do |name, tag_schema|
        next unless name.starts_with?(prefix)
        items << CompletionItem.new(
          label: name,
          kind: CompletionItemKind::Keyword,
          detail: tag_schema.has_body? ? "custom block tag" : "custom statement",
          documentation: tag_schema.doc,
          sort_text: "~#{name}" # Sort custom tags after built-ins
        )
      end

      items
    end

    # Get end tag completions based on open block tags
    private def end_tag_completions(text : String, position : Position, prefix : String) : Array(CompletionItem)
      items = Array(CompletionItem).new

      # Find open block tags before the cursor
      open_tags = find_open_tags(text, position)

      # Suggest end tags for open blocks (most recent first)
      open_tags.reverse.each do |tag_name|
        end_tag = "end#{tag_name}"
        next unless end_tag.starts_with?("end#{prefix}")
        next if items.any? { |item| item.label == end_tag }

        items << CompletionItem.new(
          label: end_tag,
          kind: CompletionItemKind::Keyword,
          detail: "close #{tag_name}",
          documentation: "Close the {% #{tag_name} %} block",
          sort_text: "0#{end_tag}" # Prioritize based on nesting
        )
      end

      # Also suggest any valid end tag that matches the prefix
      Std::Tags::BUILTINS.each do |tag|
        next unless tag.has_body?
        if end_tag = tag.end_tag
          next unless end_tag.starts_with?("end#{prefix}")
          next if items.any? { |item| item.label == end_tag }

          items << CompletionItem.new(
            label: end_tag,
            kind: CompletionItemKind::Keyword,
            detail: "close #{tag.name}",
            documentation: "Close a {% #{tag.name} %} block",
            sort_text: "1#{end_tag}" # Lower priority than open tags
          )
        end
      end

      items
    end

    # Find open block tags before the cursor position
    private def find_open_tags(text : String, position : Position) : Array(String)
      # Get text before cursor
      lines = text.split('\n')
      text_before = String.build do |str|
        lines.each_with_index do |line, i|
          if i < position.line
            str << line << '\n'
          elsif i == position.line
            str << line[0...position.character]
          end
        end
      end

      # Track open tags with a stack
      stack = Array(String).new

      # Scan for block tags and their end tags
      text_before.scan(/\{%-?\s*(\w+)/) do |match|
        tag = match[1]
        if Std::Tags::BLOCK_TAGS.includes?(tag)
          stack << tag
        elsif tag.starts_with?("end")
          # Pop matching open tag
          base_tag = tag[3..]
          # Find and remove the most recent matching tag
          idx = stack.rindex(base_tag)
          stack.delete_at(idx) if idx
        end
      end

      stack
    end

    # Analyze the context at the cursor position using the lexer's token stream.
    # This is more robust than regex since it uses proper tokenization.
    private def analyze_context(text : String, position : Position) : CompletionContext
      # Calculate the byte offset for the cursor position
      cursor_offset = offset_for_position(text, position)
      return CompletionContext.new(CompletionContextType::None, "") if cursor_offset < 0

      # Lex the text to get tokens with precise positions
      lexer = Lexer.new(text)
      tokens = lexer.lex_all

      # Find the token at or just before the cursor
      token_index = find_token_at_offset(tokens, cursor_offset)
      return CompletionContext.new(CompletionContextType::None, "") if token_index < 0

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

    # Find the index of the token at or just before the given offset
    private def find_token_at_offset(tokens : Array(Token), offset : Int32) : Int32
      # Find the last token that starts at or before the cursor
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

    # Analyze token context to determine completion type
    private def analyze_token_context(tokens : Array(Token), index : Int32, cursor_offset : Int32) : CompletionContext
      token = tokens[index]

      # Check if cursor is inside or at end of an identifier (partial typing)
      if token.type == TokenType::Identifier && cursor_offset <= token.span.end_pos.offset
        prefix = extract_prefix(token, cursor_offset)
        return analyze_identifier_context(tokens, index, prefix)
      end

      # Check if cursor is right after the token (ready for new input)
      case token.type
      when TokenType::VarStart
        # {{ - ready for variable/function
        return CompletionContext.new(CompletionContextType::Variable, "")
      when TokenType::BlockStart
        # {% - ready for tag
        return CompletionContext.new(CompletionContextType::Tag, "")
      when TokenType::Operator
        if token.lexeme == "|"
          # After pipe - filter context
          next_token = tokens[index + 1]?
          if next_token && next_token.type == TokenType::Identifier && cursor_offset <= next_token.span.end_pos.offset
            prefix = extract_prefix(next_token, cursor_offset)
            return CompletionContext.new(CompletionContextType::Filter, prefix)
          end
          return CompletionContext.new(CompletionContextType::Filter, "")
        end
      when TokenType::Punct
        if token.lexeme == "."
          # After dot - property context, find the variable before the dot
          if index > 0
            prev = tokens[index - 1]
            if prev.type == TokenType::Identifier
              next_token = tokens[index + 1]?
              prefix = ""
              if next_token && next_token.type == TokenType::Identifier && cursor_offset <= next_token.span.end_pos.offset
                prefix = extract_prefix(next_token, cursor_offset)
              end
              return CompletionContext.new(CompletionContextType::Property, prefix, prev.lexeme)
            end
          end
        end
      when TokenType::Whitespace
        # After whitespace - look back to determine context
        return analyze_after_whitespace(tokens, index, cursor_offset)
      when TokenType::Identifier
        # Cursor is after identifier (not inside) - look at what comes before
        return analyze_identifier_context(tokens, index, "")
      end

      CompletionContext.new(CompletionContextType::None, "")
    end

    # Extract the prefix of an identifier up to the cursor position
    private def extract_prefix(token : Token, cursor_offset : Int32) : String
      if cursor_offset >= token.span.end_pos.offset
        token.lexeme
      else
        chars_into_token = cursor_offset - token.span.start_pos.offset
        token.lexeme[0, chars_into_token.clamp(0, token.lexeme.size)]
      end
    end

    # Analyze context when cursor is on/after an identifier
    private def analyze_identifier_context(tokens : Array(Token), index : Int32, prefix : String) : CompletionContext
      token = tokens[index]

      # Look back to find context
      prev_significant = find_prev_significant(tokens, index)

      if prev_token = prev_significant
        case prev_token.type
        when TokenType::Operator
          if prev_token.lexeme == "|"
            return CompletionContext.new(CompletionContextType::Filter, prefix.empty? ? token.lexeme : prefix)
          end
        when TokenType::Punct
          if prev_token.lexeme == "."
            # Property access - find the variable before the dot
            dot_index = tokens.index(prev_token) || -1
            if dot_index > 0
              var_token = find_prev_significant(tokens, dot_index)
              if var_token && var_token.type == TokenType::Identifier
                return CompletionContext.new(CompletionContextType::Property, prefix.empty? ? token.lexeme : prefix, var_token.lexeme)
              end
            end
          end
        when TokenType::Identifier
          lexeme = prev_token.lexeme
          # "is" keyword -> test context
          if lexeme == "is"
            return CompletionContext.new(CompletionContextType::Test, prefix.empty? ? token.lexeme : prefix)
          end
          # "block" keyword -> block name context
          if lexeme == "block"
            return CompletionContext.new(CompletionContextType::Block, prefix.empty? ? token.lexeme : prefix)
          end
          # "call" keyword -> macro context
          if lexeme == "call"
            return CompletionContext.new(CompletionContextType::Macro, prefix.empty? ? token.lexeme : prefix)
          end
        when TokenType::BlockStart
          # Right after {% - tag context
          current_lexeme = prefix.empty? ? token.lexeme : prefix
          if current_lexeme.starts_with?("end")
            return CompletionContext.new(CompletionContextType::EndTag, current_lexeme[3..]? || "")
          end
          return CompletionContext.new(CompletionContextType::Tag, current_lexeme)
        when TokenType::VarStart
          # Right after {{ - variable/function context
          return CompletionContext.new(CompletionContextType::Variable, prefix.empty? ? token.lexeme : prefix)
        end
      end

      # Check for tag context by looking further back for BlockStart
      if in_block_context?(tokens, index)
        current_lexeme = prefix.empty? ? token.lexeme : prefix
        # Check if this is an end tag
        if current_lexeme.starts_with?("end")
          return CompletionContext.new(CompletionContextType::EndTag, current_lexeme[3..]? || "")
        end
        # Check for specific tag keywords
        first_ident = find_first_ident_after_block_start(tokens, index)
        if first_ident
          case first_ident.lexeme
          when "block"
            return CompletionContext.new(CompletionContextType::Block, prefix.empty? ? token.lexeme : prefix)
          when "call"
            return CompletionContext.new(CompletionContextType::Macro, prefix.empty? ? token.lexeme : prefix)
          when "if", "elif", "for", "set"
            return CompletionContext.new(CompletionContextType::Variable, prefix.empty? ? token.lexeme : prefix)
          end
        end
        return CompletionContext.new(CompletionContextType::Tag, current_lexeme)
      end

      # Check for variable context in output
      if in_var_context?(tokens, index)
        return CompletionContext.new(CompletionContextType::Variable, prefix.empty? ? token.lexeme : prefix)
      end

      CompletionContext.new(CompletionContextType::None, "")
    end

    # Analyze context after whitespace
    private def analyze_after_whitespace(tokens : Array(Token), ws_index : Int32, cursor_offset : Int32) : CompletionContext
      # Check if there's an identifier after the whitespace
      next_token = tokens[ws_index + 1]?
      if next_token && next_token.type == TokenType::Identifier && cursor_offset <= next_token.span.end_pos.offset
        prefix = extract_prefix(next_token, cursor_offset)
        return analyze_identifier_context(tokens, ws_index + 1, prefix)
      end

      # Look back past whitespace for context
      prev = find_prev_significant(tokens, ws_index)
      return CompletionContext.new(CompletionContextType::None, "") unless prev

      case prev.type
      when TokenType::Operator
        return CompletionContext.new(CompletionContextType::Filter, "") if prev.lexeme == "|"
      when TokenType::Identifier
        return CompletionContext.new(CompletionContextType::Test, "") if prev.lexeme == "is"
        return CompletionContext.new(CompletionContextType::Block, "") if prev.lexeme == "block"
        return CompletionContext.new(CompletionContextType::Macro, "") if prev.lexeme == "call"
        # After keywords like if, elif, for...in - variable context
        if prev.lexeme.in?("if", "elif", "in", "print") || (prev.lexeme == "=" && in_block_context?(tokens, ws_index))
          return CompletionContext.new(CompletionContextType::Variable, "")
        end
      when TokenType::BlockStart
        return CompletionContext.new(CompletionContextType::Tag, "")
      when TokenType::VarStart
        return CompletionContext.new(CompletionContextType::Variable, "")
      end

      # Check broader context
      if in_block_context?(tokens, ws_index)
        # Inside a block tag - could be tag or variable depending on position
        first_ident = find_first_ident_after_block_start(tokens, ws_index)
        unless first_ident
          return CompletionContext.new(CompletionContextType::Tag, "")
        end
      end

      if in_var_context?(tokens, ws_index)
        return CompletionContext.new(CompletionContextType::Variable, "")
      end

      CompletionContext.new(CompletionContextType::None, "")
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
