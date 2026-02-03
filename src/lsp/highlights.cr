require "./protocol"
require "./inference"
require "../lexer/lexer"
require "../parser/parser"
require "../ast/nodes"

module Crinkle::LSP
  # Highlight context types
  enum HighlightContextType
    None
    Variable
    Macro
    Block
  end

  # Highlight context information
  struct HighlightContext
    property type : HighlightContextType
    property name : String

    def initialize(@type : HighlightContextType, @name : String) : Nil
    end
  end

  # Provides document highlights for variables, macros, and blocks
  class DocumentHighlightProvider
    @inference : InferenceEngine

    def initialize(@inference : InferenceEngine) : Nil
    end

    # Find all highlights for the symbol at the given position
    def highlights(uri : String, text : String, position : Position) : Array(DocumentHighlight)
      context = analyze_highlight_context(text, position)

      case context.type
      when .variable?
        variable_highlights(uri, text, context.name)
      when .macro?
        macro_highlights(uri, text, context.name)
      when .block?
        block_highlights(uri, text, context.name)
      else
        Array(DocumentHighlight).new
      end
    end

    # Parse text into an AST
    private def parse(text : String) : AST::Template
      lexer = Lexer.new(text)
      tokens = lexer.lex_all
      parser = Parser.new(tokens)
      parser.parse
    end

    # Find all highlights for a variable in the current file
    private def variable_highlights(uri : String, text : String, name : String) : Array(DocumentHighlight)
      highlights = Array(DocumentHighlight).new

      begin
        ast = parse(text)

        # Find definition (write highlight)
        if var_info = @inference.variable_info(uri, name)
          if def_span = var_info.definition_span
            highlights << DocumentHighlight.new(
              range: span_to_range(def_span),
              kind: DocumentHighlightKind::Write
            )
          end
        end

        # Find all usages (read highlights)
        find_variable_refs(ast.body, name, highlights)
      rescue
        # Parse error - return empty
      end

      highlights
    end

    # Find all highlights for a macro in the current file
    private def macro_highlights(uri : String, text : String, name : String) : Array(DocumentHighlight)
      highlights = Array(DocumentHighlight).new

      begin
        ast = parse(text)
        find_macro_refs(ast.body, name, highlights)
      rescue
        # Parse error - return empty
      end

      highlights
    end

    # Find all highlights for a block in the current file
    private def block_highlights(uri : String, text : String, name : String) : Array(DocumentHighlight)
      highlights = Array(DocumentHighlight).new

      begin
        ast = parse(text)
        find_block_refs(ast.body, name, highlights)
      rescue
        # Parse error - return empty
      end

      highlights
    end

    # Recursively find variable references in AST
    private def find_variable_refs(nodes : Array(AST::Node), name : String, highlights : Array(DocumentHighlight)) : Nil
      nodes.each do |node|
        case node
        when AST::Output
          find_variable_refs_in_expr(node.expr, name, highlights)
        when AST::If
          find_variable_refs_in_expr(node.test, name, highlights)
          find_variable_refs(node.body, name, highlights)
          find_variable_refs(node.else_body, name, highlights)
        when AST::For
          # Check if this is a definition of the variable
          check_for_target_definition(node.target, name, highlights)
          find_variable_refs_in_expr(node.iter, name, highlights)
          find_variable_refs(node.body, name, highlights)
          find_variable_refs(node.else_body, name, highlights)
        when AST::Set
          # Check if this is a definition
          check_set_target_definition(node.target, name, highlights)
          find_variable_refs_in_expr(node.value, name, highlights)
        when AST::SetBlock
          check_set_target_definition(node.target, name, highlights)
          find_variable_refs(node.body, name, highlights)
        when AST::Block
          find_variable_refs(node.body, name, highlights)
        when AST::Macro
          # Check params for definitions
          node.params.each do |param|
            if param.name == name
              highlights << DocumentHighlight.new(
                range: span_to_range(param.span),
                kind: DocumentHighlightKind::Write
              )
            end
            if default = param.default_value
              find_variable_refs_in_expr(default, name, highlights)
            end
          end
          find_variable_refs(node.body, name, highlights)
        when AST::CallBlock
          find_variable_refs_in_expr(node.callee, name, highlights)
          node.args.each { |arg| find_variable_refs_in_expr(arg, name, highlights) }
          node.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, highlights) }
          find_variable_refs(node.body, name, highlights)
        when AST::Include
          find_variable_refs_in_expr(node.template, name, highlights)
        when AST::Import
          find_variable_refs_in_expr(node.template, name, highlights)
        when AST::FromImport
          find_variable_refs_in_expr(node.template, name, highlights)
        when AST::Extends
          find_variable_refs_in_expr(node.template, name, highlights)
        when AST::CustomTag
          node.args.each { |arg| find_variable_refs_in_expr(arg, name, highlights) }
          node.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, highlights) }
          find_variable_refs(node.body, name, highlights)
        end
      end
    end

    # Check if a for loop target defines the variable
    private def check_for_target_definition(target : AST::Target, name : String, highlights : Array(DocumentHighlight)) : Nil
      case target
      when AST::Name
        if target.value == name
          highlights << DocumentHighlight.new(
            range: span_to_range(target.span),
            kind: DocumentHighlightKind::Write
          )
        end
      when AST::TupleLiteral
        target.items.each do |item|
          if item.is_a?(AST::Name) && item.value == name
            highlights << DocumentHighlight.new(
              range: span_to_range(item.span),
              kind: DocumentHighlightKind::Write
            )
          end
        end
      end
    end

    # Check if a set target defines the variable
    private def check_set_target_definition(target : AST::Target, name : String, highlights : Array(DocumentHighlight)) : Nil
      case target
      when AST::Name
        if target.value == name
          highlights << DocumentHighlight.new(
            range: span_to_range(target.span),
            kind: DocumentHighlightKind::Write
          )
        end
      when AST::TupleLiteral
        target.items.each do |item|
          if item.is_a?(AST::Name) && item.value == name
            highlights << DocumentHighlight.new(
              range: span_to_range(item.span),
              kind: DocumentHighlightKind::Write
            )
          end
        end
      end
    end

    # Find variable references in an expression (all are reads)
    private def find_variable_refs_in_expr(expr : AST::Expr, name : String, highlights : Array(DocumentHighlight)) : Nil
      case expr
      when AST::Name
        if expr.value == name
          highlights << DocumentHighlight.new(
            range: span_to_range(expr.span),
            kind: DocumentHighlightKind::Read
          )
        end
      when AST::Binary
        find_variable_refs_in_expr(expr.left, name, highlights)
        find_variable_refs_in_expr(expr.right, name, highlights)
      when AST::Unary
        find_variable_refs_in_expr(expr.expr, name, highlights)
      when AST::Group
        find_variable_refs_in_expr(expr.expr, name, highlights)
      when AST::Call
        find_variable_refs_in_expr(expr.callee, name, highlights)
        expr.args.each { |arg| find_variable_refs_in_expr(arg, name, highlights) }
        expr.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, highlights) }
      when AST::Filter
        find_variable_refs_in_expr(expr.expr, name, highlights)
        expr.args.each { |arg| find_variable_refs_in_expr(arg, name, highlights) }
        expr.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, highlights) }
      when AST::Test
        find_variable_refs_in_expr(expr.expr, name, highlights)
        expr.args.each { |arg| find_variable_refs_in_expr(arg, name, highlights) }
        expr.kwargs.each { |kwarg| find_variable_refs_in_expr(kwarg.value, name, highlights) }
      when AST::GetAttr
        find_variable_refs_in_expr(expr.target, name, highlights)
      when AST::GetItem
        find_variable_refs_in_expr(expr.target, name, highlights)
        find_variable_refs_in_expr(expr.index, name, highlights)
      when AST::ListLiteral
        expr.items.each { |item| find_variable_refs_in_expr(item, name, highlights) }
      when AST::DictLiteral
        expr.pairs.each do |pair|
          find_variable_refs_in_expr(pair.key, name, highlights)
          find_variable_refs_in_expr(pair.value, name, highlights)
        end
      when AST::TupleLiteral
        expr.items.each { |item| find_variable_refs_in_expr(item, name, highlights) }
      end
    end

    # Find macro references (definition and call sites)
    private def find_macro_refs(nodes : Array(AST::Node), name : String, highlights : Array(DocumentHighlight)) : Nil
      nodes.each do |node|
        case node
        when AST::Macro
          if node.name == name
            # Macro definition is a write
            highlights << DocumentHighlight.new(
              range: span_to_range(node.span),
              kind: DocumentHighlightKind::Write
            )
          end
          find_macro_refs(node.body, name, highlights)
        when AST::CallBlock
          if callee_name = extract_callee_name(node.callee)
            if callee_name == name
              highlights << DocumentHighlight.new(
                range: span_to_range(node.span),
                kind: DocumentHighlightKind::Read
              )
            end
          end
          find_macro_refs(node.body, name, highlights)
        when AST::Output
          find_macro_refs_in_expr(node.expr, name, highlights)
        when AST::If
          find_macro_refs_in_expr(node.test, name, highlights)
          find_macro_refs(node.body, name, highlights)
          find_macro_refs(node.else_body, name, highlights)
        when AST::For
          find_macro_refs_in_expr(node.iter, name, highlights)
          find_macro_refs(node.body, name, highlights)
          find_macro_refs(node.else_body, name, highlights)
        when AST::Set
          find_macro_refs_in_expr(node.value, name, highlights)
        when AST::SetBlock
          find_macro_refs(node.body, name, highlights)
        when AST::Block
          find_macro_refs(node.body, name, highlights)
        end
      end
    end

    # Find macro calls in expressions
    private def find_macro_refs_in_expr(expr : AST::Expr, name : String, highlights : Array(DocumentHighlight)) : Nil
      case expr
      when AST::Call
        if callee_name = extract_callee_name(expr.callee)
          if callee_name == name
            highlights << DocumentHighlight.new(
              range: span_to_range(expr.span),
              kind: DocumentHighlightKind::Read
            )
          end
        end
        find_macro_refs_in_expr(expr.callee, name, highlights)
        expr.args.each { |arg| find_macro_refs_in_expr(arg, name, highlights) }
        expr.kwargs.each { |kwarg| find_macro_refs_in_expr(kwarg.value, name, highlights) }
      when AST::Binary
        find_macro_refs_in_expr(expr.left, name, highlights)
        find_macro_refs_in_expr(expr.right, name, highlights)
      when AST::Unary
        find_macro_refs_in_expr(expr.expr, name, highlights)
      when AST::Group
        find_macro_refs_in_expr(expr.expr, name, highlights)
      when AST::Filter
        find_macro_refs_in_expr(expr.expr, name, highlights)
        expr.args.each { |arg| find_macro_refs_in_expr(arg, name, highlights) }
        expr.kwargs.each { |kwarg| find_macro_refs_in_expr(kwarg.value, name, highlights) }
      when AST::Test
        find_macro_refs_in_expr(expr.expr, name, highlights)
        expr.args.each { |arg| find_macro_refs_in_expr(arg, name, highlights) }
        expr.kwargs.each { |kwarg| find_macro_refs_in_expr(kwarg.value, name, highlights) }
      when AST::GetAttr
        find_macro_refs_in_expr(expr.target, name, highlights)
      when AST::GetItem
        find_macro_refs_in_expr(expr.target, name, highlights)
        find_macro_refs_in_expr(expr.index, name, highlights)
      when AST::ListLiteral
        expr.items.each { |item| find_macro_refs_in_expr(item, name, highlights) }
      when AST::DictLiteral
        expr.pairs.each do |pair|
          find_macro_refs_in_expr(pair.key, name, highlights)
          find_macro_refs_in_expr(pair.value, name, highlights)
        end
      when AST::TupleLiteral
        expr.items.each { |item| find_macro_refs_in_expr(item, name, highlights) }
      end
    end

    # Extract callee name from expression
    private def extract_callee_name(expr : AST::Expr) : String?
      case expr
      when AST::Name
        expr.value
      when AST::GetAttr
        expr.name
      end
    end

    # Find block references
    private def find_block_refs(nodes : Array(AST::Node), name : String, highlights : Array(DocumentHighlight)) : Nil
      nodes.each do |node|
        case node
        when AST::Block
          if node.name == name
            highlights << DocumentHighlight.new(
              range: span_to_range(node.span),
              kind: DocumentHighlightKind::Write
            )
          end
          find_block_refs(node.body, name, highlights)
        when AST::If
          find_block_refs(node.body, name, highlights)
          find_block_refs(node.else_body, name, highlights)
        when AST::For
          find_block_refs(node.body, name, highlights)
        when AST::Macro
          find_block_refs(node.body, name, highlights)
        end
      end
    end

    # Analyze context using token-based analysis
    private def analyze_highlight_context(text : String, position : Position) : HighlightContext
      cursor_offset = offset_for_position(text, position)
      return HighlightContext.new(HighlightContextType::None, "") if cursor_offset < 0

      lexer = Lexer.new(text)
      tokens = lexer.lex_all

      token_index = find_token_at_offset(tokens, cursor_offset)
      return HighlightContext.new(HighlightContextType::None, "") if token_index < 0

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
        if token.span.start_pos.offset <= offset && offset < token.span.end_pos.offset
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

    # Analyze token context to determine what to highlight
    private def analyze_token_context(tokens : Array(Token), index : Int32, cursor_offset : Int32) : HighlightContext
      token = tokens[index]

      return HighlightContext.new(HighlightContextType::None, "") unless token.type == TokenType::Identifier

      name = token.lexeme

      # Look back to determine context
      prev_significant = find_prev_significant(tokens, index)

      if prev_token = prev_significant
        case prev_token.type
        when TokenType::Identifier
          lexeme = prev_token.lexeme
          if lexeme == "block"
            return HighlightContext.new(HighlightContextType::Block, name)
          end
          if lexeme == "call" || lexeme == "macro"
            return HighlightContext.new(HighlightContextType::Macro, name)
          end
        end
      end

      # Check if this is a function/macro call (followed by open paren)
      next_token = find_next_significant(tokens, index)
      if next_token && next_token.type == TokenType::Punct && next_token.lexeme == "("
        return HighlightContext.new(HighlightContextType::Macro, name)
      end

      # Check broader context
      if in_block_context?(tokens, index)
        first_ident = find_first_ident_after_block_start(tokens, index)
        if first_ident
          case first_ident.lexeme
          when "block"
            return HighlightContext.new(HighlightContextType::Block, name)
          when "call", "macro"
            return HighlightContext.new(HighlightContextType::Macro, name)
          end
        end
        return HighlightContext.new(HighlightContextType::Variable, name)
      end

      if in_var_context?(tokens, index)
        return HighlightContext.new(HighlightContextType::Variable, name)
      end

      HighlightContext.new(HighlightContextType::None, "")
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
