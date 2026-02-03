require "./protocol"
require "./inference"
require "./document"
require "./workspace_index"
require "../lexer/lexer"
require "../parser/parser"
require "../ast/nodes"
require "../ast/visitor"

module Crinkle::LSP
  # Rename context types
  enum RenameContextType
    None
    Variable
    Macro
    Block
  end

  # Rename context information
  struct RenameContext
    property type : RenameContextType
    property name : String
    property range : Range

    def initialize(@type : RenameContextType, @name : String, @range : Range) : Nil
    end
  end

  # Provides rename functionality for variables, macros, and blocks
  class RenameProvider
    @inference : InferenceEngine
    @documents : DocumentStore
    @index : WorkspaceIndex?
    @root_path : String?

    # Keywords and reserved names that cannot be renamed to
    RESERVED_NAMES = %w[
      true false none
      and or not in is
      if else elif endif
      for endfor
      block endblock
      macro endmacro call endcall
      set endset
      include import from extends
      raw endraw
      filter endfilter
      with endwith
      autoescape endautoescape
      do trans endtrans pluralize
      loop self super caller varargs kwargs
    ]

    def initialize(@inference : InferenceEngine, @documents : DocumentStore, @index : WorkspaceIndex? = nil, @root_path : String? = nil) : Nil
    end

    # Prepare rename - validate that the symbol can be renamed
    def prepare_rename(uri : String, text : String, position : Position) : PrepareRenameResult?
      context = analyze_rename_context(text, position)

      case context.type
      when .variable?, .macro?, .block?
        PrepareRenameResult.new(
          range: context.range,
          placeholder: context.name
        )
      end
    end

    # Perform the rename
    def rename(uri : String, text : String, position : Position, new_name : String) : WorkspaceEdit?
      # Validate new name
      return if new_name.empty?
      return if RESERVED_NAMES.includes?(new_name.downcase)
      return unless valid_identifier?(new_name)

      context = analyze_rename_context(text, position)

      case context.type
      when .variable?
        rename_variable(uri, text, context.name, new_name)
      when .macro?
        rename_macro(uri, text, context.name, new_name)
      when .block?
        rename_block(uri, text, context.name, new_name)
      end
    end

    # Check if a name is a valid identifier
    private def valid_identifier?(name : String) : Bool
      return false if name.empty?
      # Must start with letter or underscore
      return false unless name[0].letter? || name[0] == '_'
      # Rest must be alphanumeric or underscore
      name.each_char.all? { |char| char.alphanumeric? || char == '_' }
    end

    # Rename a variable within the current file
    private def rename_variable(uri : String, text : String, old_name : String, new_name : String) : WorkspaceEdit?
      edits = Array(TextEdit).new

      begin
        ast = parse(text)
        visitor = VariableRenameVisitor.new(old_name, new_name, edits, ->(span : Span) : Range { span_to_range(span) })
        visitor.visit_nodes(ast.body)
      rescue
        return
      end

      return if edits.empty?

      WorkspaceEdit.new(
        changes: {uri => edits}
      )
    end

    # Rename a macro (updates definition and call sites in current and related files)
    private def rename_macro(uri : String, text : String, old_name : String, new_name : String) : WorkspaceEdit?
      all_edits = Hash(String, Array(TextEdit)).new

      each_workspace_uri do |doc_uri, doc_text|
        begin
          ast = parse(doc_text)
          edits = Array(TextEdit).new
          visitor = MacroRenameVisitor.new(
            old_name,
            new_name,
            edits,
            include_definition: true,
            name_range_proc: ->(node : AST::Macro) : Range? { find_macro_name_range(node) },
            call_range_proc: ->(expr : AST::Expr) : Range? { find_call_name_range(expr) },
            import_name_range_proc: ->(import_name : AST::ImportName) : Range { import_name_range(import_name) },
            import_alias_range_proc: ->(import_name : AST::ImportName, alias_name : String) : Range { import_alias_range(import_name, alias_name) }
          )
          visitor.visit_nodes(ast.body)
          all_edits[doc_uri] = edits unless edits.empty?
        rescue
          # Parse error - skip
        end
      end

      return if all_edits.empty?

      WorkspaceEdit.new(changes: all_edits)
    end

    # Rename a block (updates definition and overrides across templates)
    private def rename_block(uri : String, text : String, old_name : String, new_name : String) : WorkspaceEdit?
      all_edits = Hash(String, Array(TextEdit)).new

      each_workspace_uri do |doc_uri, doc_text|
        begin
          ast = parse(doc_text)
          edits = Array(TextEdit).new
          visitor = BlockRenameVisitor.new(
            old_name,
            new_name,
            edits,
            ->(span : Span) : Range { span_to_range(span) },
            ->(node : AST::Block) : Range? { find_block_name_range(node) }
          )
          visitor.visit_nodes(ast.body)
          all_edits[doc_uri] = edits unless edits.empty?
        rescue
          # Parse error - skip
        end
      end

      return if all_edits.empty?

      WorkspaceEdit.new(changes: all_edits)
    end

    # Parse text into an AST
    private def parse(text : String) : AST::Template
      lexer = Lexer.new(text)
      tokens = lexer.lex_all
      parser = Parser.new(tokens)
      parser.parse
    end

    # Find the range of the macro name in a macro definition
    private def find_macro_name_range(node : AST::Macro) : Range?
      # The macro name is stored in node.name, we need to find its position
      # The span of the macro node covers the whole block, so we estimate
      # based on "{% macro " prefix (7 chars for "macro " after {%)
      span = node.span
      name_start = Position.new(
        line: span.start_pos.line - 1,
        character: span.start_pos.column + 9 # "{% macro " = 9 chars
      )
      name_end = Position.new(
        line: span.start_pos.line - 1,
        character: name_start.character + node.name.size
      )
      Range.new(start: name_start, end_pos: name_end)
    end

    # Find the range of the callee name in a call expression
    private def find_call_name_range(expr : AST::Expr) : Range?
      case expr
      when AST::Name
        span_to_range(expr.span)
      when AST::GetAttr
        # For forms.input() style, return the range of "input"
        # This is tricky - we need to find where the attribute name starts
        # For now, use the whole GetAttr span
        span_to_range(expr.span)
      end
    end

    private def import_name_range(import_name : AST::ImportName) : Range
      span = import_name.span
      start = Position.new(
        line: span.start_pos.line - 1,
        character: span.start_pos.column
      )
      end_pos = Position.new(
        line: span.start_pos.line - 1,
        character: span.start_pos.column + import_name.name.size
      )
      Range.new(start: start, end_pos: end_pos)
    end

    private def import_alias_range(import_name : AST::ImportName, alias_name : String) : Range
      span = import_name.span
      end_col = span.end_pos.column
      start_col = end_col - alias_name.size
      start = Position.new(
        line: span.end_pos.line - 1,
        character: start_col
      )
      end_pos = Position.new(
        line: span.end_pos.line - 1,
        character: end_col
      )
      Range.new(start: start, end_pos: end_pos)
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

    private class VariableRenameVisitor < AST::Visitor
      def initialize(
        @old_name : String,
        @new_name : String,
        @edits : Array(TextEdit),
        @span_to_range : Proc(Span, Range),
      ) : Nil
      end

      protected def enter_node(node : AST::Node) : Nil
        return unless node.is_a?(AST::Macro)

        node.params.each do |param|
          if param.name == @old_name
            @edits << TextEdit.new(range: @span_to_range.call(param.span), new_text: @new_name)
          end
        end
      end

      def visit_target(target : AST::Target) : Nil
        case target
        when AST::Name
          if target.value == @old_name
            @edits << TextEdit.new(range: @span_to_range.call(target.span), new_text: @new_name)
          end
          return
        when AST::TupleLiteral
          target.items.each do |item|
            if item.is_a?(AST::Name) && item.value == @old_name
              @edits << TextEdit.new(range: @span_to_range.call(item.span), new_text: @new_name)
            end
          end
          return
        end
        super
      end

      protected def enter_expr(expr : AST::Expr) : Nil
        return unless expr.is_a?(AST::Name)
        return unless expr.value == @old_name

        @edits << TextEdit.new(range: @span_to_range.call(expr.span), new_text: @new_name)
      end
    end

    private class MacroRenameVisitor < AST::Visitor
      def initialize(
        @old_name : String,
        @new_name : String,
        @edits : Array(TextEdit),
        @include_definition : Bool,
        @name_range_proc : Proc(AST::Macro, Range?),
        @call_range_proc : Proc(AST::Expr, Range?),
        @import_name_range_proc : Proc(AST::ImportName, Range),
        @import_alias_range_proc : Proc(AST::ImportName, String, Range),
      ) : Nil
      end

      protected def enter_node(node : AST::Node) : Nil
        case node
        when AST::Macro
          if @include_definition && node.name == @old_name
            if name_range = @name_range_proc.call(node)
              @edits << TextEdit.new(range: name_range, new_text: @new_name)
            end
          end
        when AST::CallBlock
          if callee_name = extract_callee_name(node.callee)
            if callee_name == @old_name
              if name_range = @call_range_proc.call(node.callee)
                @edits << TextEdit.new(range: name_range, new_text: @new_name)
              end
            end
          end
        when AST::FromImport
          node.names.each do |import_name|
            if import_name.name == @old_name
              @edits << TextEdit.new(range: @import_name_range_proc.call(import_name), new_text: @new_name)
            end
            if alias_name = import_name.alias
              if alias_name == @old_name
                @edits << TextEdit.new(range: @import_alias_range_proc.call(import_name, alias_name), new_text: @new_name)
              end
            end
          end
        end
      end

      protected def enter_expr(expr : AST::Expr) : Nil
        return unless expr.is_a?(AST::Call)

        if callee_name = extract_callee_name(expr.callee)
          if callee_name == @old_name
            if name_range = @call_range_proc.call(expr.callee)
              @edits << TextEdit.new(range: name_range, new_text: @new_name)
            end
          end
        end
      end

      private def extract_callee_name(expr : AST::Expr) : String?
        case expr
        when AST::Name
          expr.value
        when AST::GetAttr
          expr.name
        end
      end
    end

    private class BlockRenameVisitor < AST::Visitor
      def initialize(
        @old_name : String,
        @new_name : String,
        @edits : Array(TextEdit),
        @span_to_range : Proc(Span, Range),
        @name_range_proc : Proc(AST::Block, Range?),
      ) : Nil
      end

      protected def enter_node(node : AST::Node) : Nil
        return unless node.is_a?(AST::Block)
        return unless node.name == @old_name

        if name_range = @name_range_proc.call(node)
          @edits << TextEdit.new(range: name_range, new_text: @new_name)
        end
      end
    end

    # Find the range of the block name in a block definition
    private def find_block_name_range(node : AST::Block) : Range?
      span = node.span
      name_start = Position.new(
        line: span.start_pos.line - 1,
        character: span.start_pos.column + 9 # "{% block " = 9 chars
      )
      name_end = Position.new(
        line: span.start_pos.line - 1,
        character: name_start.character + node.name.size
      )
      Range.new(start: name_start, end_pos: name_end)
    end

    # Analyze rename context using token-based analysis
    private def analyze_rename_context(text : String, position : Position) : RenameContext
      cursor_offset = offset_for_position(text, position)
      return RenameContext.new(RenameContextType::None, "", empty_range) if cursor_offset < 0

      lexer = Lexer.new(text)
      tokens = lexer.lex_all

      token_index = find_token_at_offset(tokens, cursor_offset)
      return RenameContext.new(RenameContextType::None, "", empty_range) if token_index < 0

      analyze_token_context(tokens, token_index, cursor_offset)
    end

    # Empty range helper
    private def empty_range : Range
      Range.new(
        start: Position.new(line: 0, character: 0),
        end_pos: Position.new(line: 0, character: 0)
      )
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

    # Analyze token context
    private def analyze_token_context(tokens : Array(Token), index : Int32, cursor_offset : Int32) : RenameContext
      token = tokens[index]

      return RenameContext.new(RenameContextType::None, "", empty_range) unless token.type == TokenType::Identifier

      name = token.lexeme
      range = span_to_range(token.span)

      # Look back to determine context
      prev_significant = find_prev_significant(tokens, index)

      if prev_token = prev_significant
        case prev_token.type
        when TokenType::Identifier
          lexeme = prev_token.lexeme
          if lexeme == "block"
            return RenameContext.new(RenameContextType::Block, name, range)
          end
          if lexeme == "call" || lexeme == "macro"
            return RenameContext.new(RenameContextType::Macro, name, range)
          end
        end
      end

      # Check if this is a function/macro call (followed by open paren)
      next_token = find_next_significant(tokens, index)
      if next_token && next_token.type == TokenType::Punct && next_token.lexeme == "("
        return RenameContext.new(RenameContextType::Macro, name, range)
      end

      # Check broader context
      if in_block_context?(tokens, index)
        first_ident = find_first_ident_after_block_start(tokens, index)
        if first_ident
          case first_ident.lexeme
          when "block"
            return RenameContext.new(RenameContextType::Block, name, range)
          when "call", "macro"
            return RenameContext.new(RenameContextType::Macro, name, range)
          end
        end
        return RenameContext.new(RenameContextType::Variable, name, range)
      end

      if in_var_context?(tokens, index)
        return RenameContext.new(RenameContextType::Variable, name, range)
      end

      RenameContext.new(RenameContextType::None, "", empty_range)
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

    private def each_workspace_uri(& : String, String ->) : Nil
      seen = Set(String).new

      # Open documents first
      @documents.uris.each do |doc_uri|
        if doc = @documents.get(doc_uri)
          seen << doc_uri
          yield doc_uri, doc.text
        end
      end

      # Workspace index for unopened files
      if index = @index
        index.entries.each_key do |uri|
          next if seen.includes?(uri)
          if text = load_text_from_uri(uri)
            seen << uri
            yield uri, text
          end
        end
      end
    end

    private def load_text_from_uri(uri : String) : String?
      return unless uri.starts_with?("file://")
      path = uri.sub(/^file:\/\//, "")
      return unless File.exists?(path)
      File.read(path)
    rescue
      nil
    end
  end
end
