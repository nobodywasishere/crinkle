module Crinkle::LSP
  # Reference context types (reuse from definition for consistency)
  enum ReferenceContextType
    None
    Variable
    Macro
    Block
  end

  # Reference context information
  struct ReferenceContext
    property type : ReferenceContextType
    property name : String

    def initialize(@type : ReferenceContextType, @name : String) : Nil
    end
  end

  # Provides find-all-references for variables, macros, and blocks
  class ReferencesProvider
    @inference : InferenceEngine
    @documents : DocumentStore

    def initialize(@inference : InferenceEngine, @documents : DocumentStore) : Nil
    end

    # Find all references to the symbol at the given position
    def references(uri : String, text : String, position : Position, include_declaration : Bool = true) : Array(Location)
      context = analyze_reference_context(text, position)

      case context.type
      when .variable?
        variable_references(uri, text, context.name, include_declaration)
      when .macro?
        macro_references(uri, text, context.name, include_declaration)
      when .block?
        block_references(uri, text, context.name, include_declaration)
      else
        Array(Location).new
      end
    end

    # Parse text into an AST
    private def parse(text : String) : AST::Template
      lexer = Lexer.new(text)
      tokens = lexer.lex_all
      parser = Parser.new(tokens)
      parser.parse
    end

    # Find all references to a variable in the current file
    private def variable_references(uri : String, text : String, name : String, include_declaration : Bool) : Array(Location)
      locations = Array(Location).new

      begin
        ast = parse(text)

        # Find all Name nodes that match this variable
        find_variable_refs(ast.body, name, locations, uri)

        # If not including declaration, remove the definition location
        unless include_declaration
          if var_info = @inference.variable_info(uri, name)
            if def_span = var_info.definition_span
              def_range = span_to_range(def_span)
              # Check if reference is within the definition range (e.g., variable in set statement)
              locations.reject! do |loc|
                loc.range.start.line == def_range.start.line &&
                  loc.range.start.character >= def_range.start.character &&
                  loc.range.start.character < def_range.end_pos.character
              end
            end
          end
        end
      rescue
        # Parse error - return empty
      end

      locations
    end

    # Find all references to a macro (call sites)
    private def macro_references(uri : String, text : String, name : String, include_declaration : Bool) : Array(Location)
      locations = Array(Location).new

      # First, find references in the current file
      begin
        ast = parse(text)
        find_macro_refs(ast.body, name, locations, uri, include_declaration)
      rescue
        # Parse error - continue
      end

      # Also search related templates
      @documents.uris.each do |doc_uri|
        next if doc_uri == uri
        if doc = @documents.get(doc_uri)
          begin
            ast = parse(doc.text)
            find_macro_refs(ast.body, name, locations, doc_uri, include_declaration: false)
          rescue
            # Parse error - skip
          end
        end
      end

      locations
    end

    # Find all references to a block (overrides)
    private def block_references(uri : String, text : String, name : String, include_declaration : Bool) : Array(Location)
      locations = Array(Location).new

      # Search all open templates for block definitions with this name
      @documents.uris.each do |doc_uri|
        if doc = @documents.get(doc_uri)
          begin
            ast = parse(doc.text)
            find_block_refs(ast.body, name, locations, doc_uri)
          rescue
            # Parse error - skip
          end
        end
      end

      # If not including declaration, remove the original definition
      unless include_declaration
        if block_info = @inference.block_info(uri, name)
          if def_span = block_info.definition_span
            def_range = span_to_range(def_span)
            source_uri = block_info.source_uri || uri
            locations.reject! do |loc|
              loc.uri == source_uri &&
                loc.range.start.line == def_range.start.line &&
                loc.range.start.character == def_range.start.character
            end
          end
        end
      end

      locations
    end

    # Recursively find variable references in AST
    private def find_variable_refs(nodes : Array(AST::Node), name : String, locations : Array(Location), uri : String) : Nil
      nodes.each do |node|
        case node
        when AST::Output
          find_variable_refs_in_expr(node.expr, name, locations, uri)
        when AST::If
          find_variable_refs_in_expr(node.test, name, locations, uri)
          find_variable_refs(node.body, name, locations, uri)
          find_variable_refs(node.else_body, name, locations, uri)
        when AST::For
          # Check target (for variable definition)
          find_variable_refs_in_target(node.target, name, locations, uri)
          find_variable_refs_in_expr(node.iter, name, locations, uri)
          find_variable_refs(node.body, name, locations, uri)
          find_variable_refs(node.else_body, name, locations, uri)
        when AST::Set
          find_variable_refs_in_target(node.target, name, locations, uri)
          find_variable_refs_in_expr(node.value, name, locations, uri)
        when AST::SetBlock
          find_variable_refs_in_target(node.target, name, locations, uri)
          find_variable_refs(node.body, name, locations, uri)
        when AST::Block
          find_variable_refs(node.body, name, locations, uri)
        when AST::Macro
          # Check params for definition
          node.params.each do |param|
            if param.name == name
              locations << Location.new(uri: uri, range: span_to_range(param.span))
            end
            if default = param.default_value
              find_variable_refs_in_expr(default, name, locations, uri)
            end
          end
          find_variable_refs(node.body, name, locations, uri)
        when AST::CallBlock
          find_variable_refs_in_expr(node.callee, name, locations, uri)
          node.args.each { |arg| find_variable_refs_in_expr(arg, name, locations, uri) }
          node.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, locations, uri) }
          find_variable_refs(node.body, name, locations, uri)
        when AST::Include
          find_variable_refs_in_expr(node.template, name, locations, uri)
        when AST::Import
          find_variable_refs_in_expr(node.template, name, locations, uri)
        when AST::FromImport
          find_variable_refs_in_expr(node.template, name, locations, uri)
        when AST::Extends
          find_variable_refs_in_expr(node.template, name, locations, uri)
        when AST::CustomTag
          node.args.each { |arg| find_variable_refs_in_expr(arg, name, locations, uri) }
          node.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, locations, uri) }
          find_variable_refs(node.body, name, locations, uri)
        end
      end
    end

    # Find variable references in an expression
    private def find_variable_refs_in_expr(expr : AST::Expr, name : String, locations : Array(Location), uri : String) : Nil
      case expr
      when AST::Name
        if expr.value == name
          locations << Location.new(uri: uri, range: span_to_range(expr.span))
        end
      when AST::Binary
        find_variable_refs_in_expr(expr.left, name, locations, uri)
        find_variable_refs_in_expr(expr.right, name, locations, uri)
      when AST::Unary
        find_variable_refs_in_expr(expr.expr, name, locations, uri)
      when AST::Group
        find_variable_refs_in_expr(expr.expr, name, locations, uri)
      when AST::Call
        find_variable_refs_in_expr(expr.callee, name, locations, uri)
        expr.args.each { |arg| find_variable_refs_in_expr(arg, name, locations, uri) }
        expr.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, locations, uri) }
      when AST::Filter
        find_variable_refs_in_expr(expr.expr, name, locations, uri)
        expr.args.each { |arg| find_variable_refs_in_expr(arg, name, locations, uri) }
        expr.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, locations, uri) }
      when AST::Test
        find_variable_refs_in_expr(expr.expr, name, locations, uri)
        expr.args.each { |arg| find_variable_refs_in_expr(arg, name, locations, uri) }
        expr.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, locations, uri) }
      when AST::GetAttr
        find_variable_refs_in_expr(expr.target, name, locations, uri)
      when AST::GetItem
        find_variable_refs_in_expr(expr.target, name, locations, uri)
        find_variable_refs_in_expr(expr.index, name, locations, uri)
      when AST::ListLiteral
        expr.items.each { |item| find_variable_refs_in_expr(item, name, locations, uri) }
      when AST::DictLiteral
        expr.pairs.each do |pair|
          find_variable_refs_in_expr(pair.key, name, locations, uri)
          find_variable_refs_in_expr(pair.value, name, locations, uri)
        end
      when AST::TupleLiteral
        expr.items.each { |item| find_variable_refs_in_expr(item, name, locations, uri) }
      end
    end

    # Find variable references in a target (for set/for targets)
    private def find_variable_refs_in_target(target : AST::Target, name : String, locations : Array(Location), uri : String) : Nil
      case target
      when AST::Name
        if target.value == name
          locations << Location.new(uri: uri, range: span_to_range(target.span))
        end
      when AST::TupleLiteral
        target.items.each do |item|
          if item.is_a?(AST::Name) && item.value == name
            locations << Location.new(uri: uri, range: span_to_range(item.span))
          end
        end
      when AST::GetAttr
        find_variable_refs_in_expr(target.target, name, locations, uri)
      when AST::GetItem
        find_variable_refs_in_expr(target.target, name, locations, uri)
        find_variable_refs_in_expr(target.index, name, locations, uri)
      end
    end

    # Find macro references (definitions and call sites)
    private def find_macro_refs(nodes : Array(AST::Node), name : String, locations : Array(Location), uri : String, include_declaration : Bool = true) : Nil
      nodes.each do |node|
        case node
        when AST::Macro
          # Macro definition
          if node.name == name && include_declaration
            locations << Location.new(uri: uri, range: span_to_range(node.span))
          end
          find_macro_refs(node.body, name, locations, uri, include_declaration)
        when AST::CallBlock
          # Call block - check if calling this macro
          if callee_name = extract_callee_name(node.callee)
            if callee_name == name
              locations << Location.new(uri: uri, range: span_to_range(node.span))
            end
          end
          find_macro_refs(node.body, name, locations, uri, include_declaration)
        when AST::Output
          # Check for macro calls in output
          find_macro_refs_in_expr(node.expr, name, locations, uri)
        when AST::If
          find_macro_refs_in_expr(node.test, name, locations, uri)
          find_macro_refs(node.body, name, locations, uri, include_declaration)
          find_macro_refs(node.else_body, name, locations, uri, include_declaration)
        when AST::For
          find_macro_refs_in_expr(node.iter, name, locations, uri)
          find_macro_refs(node.body, name, locations, uri, include_declaration)
          find_macro_refs(node.else_body, name, locations, uri, include_declaration)
        when AST::Set
          find_macro_refs_in_expr(node.value, name, locations, uri)
        when AST::SetBlock
          find_macro_refs(node.body, name, locations, uri, include_declaration)
        when AST::Block
          find_macro_refs(node.body, name, locations, uri, include_declaration)
        end
      end
    end

    # Find macro calls in expressions
    private def find_macro_refs_in_expr(expr : AST::Expr, name : String, locations : Array(Location), uri : String) : Nil
      case expr
      when AST::Call
        if callee_name = extract_callee_name(expr.callee)
          if callee_name == name
            locations << Location.new(uri: uri, range: span_to_range(expr.span))
          end
        end
        find_macro_refs_in_expr(expr.callee, name, locations, uri)
        expr.args.each { |arg| find_macro_refs_in_expr(arg, name, locations, uri) }
        expr.kwargs.each { |kwarg| find_macro_refs_in_expr(kwarg.value, name, locations, uri) }
      when AST::Binary
        find_macro_refs_in_expr(expr.left, name, locations, uri)
        find_macro_refs_in_expr(expr.right, name, locations, uri)
      when AST::Unary
        find_macro_refs_in_expr(expr.expr, name, locations, uri)
      when AST::Group
        find_macro_refs_in_expr(expr.expr, name, locations, uri)
      when AST::Filter
        find_macro_refs_in_expr(expr.expr, name, locations, uri)
        expr.args.each { |arg| find_macro_refs_in_expr(arg, name, locations, uri) }
        expr.kwargs.each { |kwarg| find_macro_refs_in_expr(kwarg.value, name, locations, uri) }
      when AST::Test
        find_macro_refs_in_expr(expr.expr, name, locations, uri)
        expr.args.each { |arg| find_macro_refs_in_expr(arg, name, locations, uri) }
        expr.kwargs.each { |kwarg| find_macro_refs_in_expr(kwarg.value, name, locations, uri) }
      when AST::GetAttr
        find_macro_refs_in_expr(expr.target, name, locations, uri)
      when AST::GetItem
        find_macro_refs_in_expr(expr.target, name, locations, uri)
        find_macro_refs_in_expr(expr.index, name, locations, uri)
      when AST::ListLiteral
        expr.items.each { |item| find_macro_refs_in_expr(item, name, locations, uri) }
      when AST::DictLiteral
        expr.pairs.each do |pair|
          find_macro_refs_in_expr(pair.key, name, locations, uri)
          find_macro_refs_in_expr(pair.value, name, locations, uri)
        end
      when AST::TupleLiteral
        expr.items.each { |item| find_macro_refs_in_expr(item, name, locations, uri) }
      end
    end

    # Extract callee name from expression (handles Name and GetAttr for imported macros)
    private def extract_callee_name(expr : AST::Expr) : String?
      case expr
      when AST::Name
        expr.value
      when AST::GetAttr
        # For forms.input() style calls, return "input"
        expr.name
      end
    end

    # Find block references (all blocks with the same name)
    private def find_block_refs(nodes : Array(AST::Node), name : String, locations : Array(Location), uri : String) : Nil
      nodes.each do |node|
        case node
        when AST::Block
          if node.name == name
            locations << Location.new(uri: uri, range: span_to_range(node.span))
          end
          find_block_refs(node.body, name, locations, uri)
        when AST::If
          find_block_refs(node.body, name, locations, uri)
          find_block_refs(node.else_body, name, locations, uri)
        when AST::For
          find_block_refs(node.body, name, locations, uri)
        when AST::Macro
          find_block_refs(node.body, name, locations, uri)
        end
      end
    end

    # Analyze context using token-based analysis (similar to definition/hover)
    private def analyze_reference_context(text : String, position : Position) : ReferenceContext
      cursor_offset = offset_for_position(text, position)
      return ReferenceContext.new(ReferenceContextType::None, "") if cursor_offset < 0

      lexer = Lexer.new(text)
      tokens = lexer.lex_all

      token_index = find_token_at_offset(tokens, cursor_offset)
      return ReferenceContext.new(ReferenceContextType::None, "") if token_index < 0

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
      # First, try to find a token that starts exactly at the offset (prefer this)
      tokens.each_with_index do |token, idx|
        next if token.type == TokenType::EOF
        if token.span.start_pos.offset == offset
          return idx
        end
      end

      # Otherwise, find a token that contains the offset
      tokens.each_with_index do |token, idx|
        next if token.type == TokenType::EOF
        if token.span.start_pos.offset <= offset && offset < token.span.end_pos.offset
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

    # Analyze token context to determine what reference to look for
    private def analyze_token_context(tokens : Array(Token), index : Int32, cursor_offset : Int32) : ReferenceContext
      token = tokens[index]

      return ReferenceContext.new(ReferenceContextType::None, "") unless token.type == TokenType::Identifier

      name = token.lexeme

      # Look back to determine context
      prev_significant = find_prev_significant(tokens, index)

      if prev_token = prev_significant
        case prev_token.type
        when TokenType::Identifier
          lexeme = prev_token.lexeme
          # "block" keyword -> block name context
          if lexeme == "block"
            return ReferenceContext.new(ReferenceContextType::Block, name)
          end
          # "call" keyword -> macro context
          if lexeme == "call"
            return ReferenceContext.new(ReferenceContextType::Macro, name)
          end
          # "macro" keyword -> macro definition
          if lexeme == "macro"
            return ReferenceContext.new(ReferenceContextType::Macro, name)
          end
        end
      end

      # Check if this is a function/macro call (followed by open paren)
      next_token = find_next_significant(tokens, index)
      if next_token && next_token.type == TokenType::Punct && next_token.lexeme == "("
        return ReferenceContext.new(ReferenceContextType::Macro, name)
      end

      # Check broader context
      if in_block_context?(tokens, index)
        first_ident = find_first_ident_after_block_start(tokens, index)
        if first_ident
          case first_ident.lexeme
          when "block"
            return ReferenceContext.new(ReferenceContextType::Block, name)
          when "call", "macro"
            return ReferenceContext.new(ReferenceContextType::Macro, name)
          end
        end
        # Default to variable in block context
        return ReferenceContext.new(ReferenceContextType::Variable, name)
      end

      if in_var_context?(tokens, index)
        return ReferenceContext.new(ReferenceContextType::Variable, name)
      end

      ReferenceContext.new(ReferenceContextType::None, "")
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

    # Convert a Span (1-based lines from lexer) to an LSP Range (0-based lines)
    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column)
      )
    end
  end
end
