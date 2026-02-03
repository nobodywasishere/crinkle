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
      when .variable?
        PrepareRenameResult.new(
          range: context.range,
          placeholder: context.name
        )
      when .macro?
        return unless find_macro_target(uri, text, context.range, context.name)
        PrepareRenameResult.new(
          range: context.range,
          placeholder: context.name
        )
      when .block?
        return unless find_block_target(uri, text, context.range, context.name)
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
        rename_variable(uri, text, context.range, new_name)
      when .macro?
        rename_macro(uri, text, context.range, context.name, new_name)
      when .block?
        rename_block(uri, text, context.range, context.name, new_name)
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

    # Rename a variable within the current file (scope-aware)
    private def rename_variable(uri : String, text : String, target_range : Range, new_name : String) : WorkspaceEdit?
      edits = Array(TextEdit).new

      begin
        ast = parse(text)
        span_to_range = ->(span : Span) : Range { span_to_range(span) }

        finder = VariableScopeVisitor.new(target_range, span_to_range)
        finder.visit_nodes(ast.body)

        target_decl_id = finder.target_decl_id
        target_name = finder.target_name
        target_is_context = finder.target_is_context?

        return unless target_name

        collector = VariableScopeVisitor.new(
          target_range: nil,
          span_to_range: span_to_range,
          collect: true,
          new_name: new_name,
          target_decl_id: target_decl_id,
          target_name: target_name,
          target_is_context: target_is_context
        )
        collector.visit_nodes(ast.body)
        edits.concat(collector.edits)
      rescue
        return
      end

      return if edits.empty?

      WorkspaceEdit.new(
        changes: {uri => edits}
      )
    end

    # Rename a macro (definition + direct references only)
    private def rename_macro(uri : String, text : String, target_range : Range, target_name : String, new_name : String) : WorkspaceEdit?
      target = find_macro_target(uri, text, target_range, target_name)
      return unless target

      all_edits = Hash(String, Array(TextEdit)).new

      each_workspace_uri do |doc_uri, doc_text|
        begin
          ast = parse(doc_text)
          context = build_macro_context(ast)
          edits = Array(TextEdit).new

          # Rename definition if this file owns the macro and we're renaming the macro itself.
          if target.kind != MacroRenameKind::ImportAlias && target.source_uri && doc_uri == target.source_uri
            if macro_ = context.local_macros[target.macro_name]?
              if name_range = find_macro_name_range(macro_)
                edits << TextEdit.new(range: name_range, new_text: new_name)
              end
            end
          end

          # Rename import statements and call sites that directly reference the target.
          rename_macro_imports_and_calls(
            doc_uri,
            ast,
            context,
            target,
            new_name,
            edits
          )

          all_edits[doc_uri] = edits unless edits.empty?
        rescue
          # Parse error - skip
        end
      end

      return if all_edits.empty?

      WorkspaceEdit.new(changes: all_edits)
    end

    # Rename a block (updates definition and overrides in the same extends chain)
    private def rename_block(uri : String, text : String, target_range : Range, old_name : String, new_name : String) : WorkspaceEdit?
      target_block = find_block_target(uri, text, target_range, old_name)
      return unless target_block

      related_uris = related_block_uris(uri)
      return if related_uris.empty?

      all_edits = Hash(String, Array(TextEdit)).new

      each_workspace_uri do |doc_uri, doc_text|
        next unless related_uris.includes?(doc_uri)
        begin
          ast = parse(doc_text)
          edits = Array(TextEdit).new
          visitor = BlockRenameVisitor.new(
            target_block,
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

    private def import_name_range(import_name : AST::ImportName) : Range
      span = import_name.span
      start = Position.new(
        line: span.start_pos.line - 1,
        character: span.start_pos.column - 1
      )
      end_pos = Position.new(
        line: span.start_pos.line - 1,
        character: start.character + import_name.name.size
      )
      Range.new(start: start, end_pos: end_pos)
    end

    private def import_alias_range(import_name : AST::ImportName, alias_name : String) : Range
      span = import_name.span
      end_col = span.end_pos.column - 1
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

    private def build_macro_context(ast : AST::Template) : MacroContext
      local_macros = Hash(String, AST::Macro).new
      from_imports = Hash(String, MacroImport).new
      import_aliases = Hash(String, String).new

      AST::Walker.walk_nodes(ast.body) do |node|
        case node
        when AST::Macro
          local_macros[node.name] = node
        when AST::FromImport
          if path = extract_template_path(node.template)
            node.names.each do |import_name|
              local_name = import_name.alias || import_name.name
              from_imports[local_name] = MacroImport.new(path, import_name.name, local_name)
            end
          end
        when AST::Import
          if path = extract_template_path(node.template)
            if alias_name = node.alias
              import_aliases[alias_name] = path
            end
          end
        end
      end

      MacroContext.new(local_macros, from_imports, import_aliases)
    end

    private def resolve_macro_binding(expr : AST::Expr, context : MacroContext) : MacroBinding?
      case expr
      when AST::Name
        if context.local_macros.has_key?(expr.value)
          return MacroBinding.new(MacroBindingKind::Local, nil, expr.value, expr.value)
        end
        if binding = context.from_imports[expr.value]?
          return MacroBinding.new(MacroBindingKind::FromImport, binding.path, binding.original_name, binding.local_name)
        end
      when AST::GetAttr
        if target = expr.target
          if target.is_a?(AST::Name)
            if path = context.import_aliases[target.value]?
              return MacroBinding.new(MacroBindingKind::ImportAlias, path, expr.name, expr.name)
            end
          end
        end
      end
      nil
    end

    private def find_macro_target(uri : String, text : String, target_range : Range, target_name : String) : MacroRenameTarget?
      ast = parse(text)
      context = build_macro_context(ast)

      found : MacroRenameTarget? = nil

      context.local_macros.each_value do |macro_|
        if name_range = find_macro_name_range(macro_)
          if ranges_equal?(name_range, target_range)
            template_path = template_path_for_uri(uri)
            return MacroRenameTarget.new(MacroRenameKind::Local, macro_.name, template_path, uri, macro_.name)
          end
        end
      end

      AST::Walker.walk_nodes(ast.body) do |node|
        next if found
        next unless node.is_a?(AST::FromImport)
        next unless path = extract_template_path(node.template)

        node.names.each do |import_name|
          if ranges_equal?(import_name_range(import_name), target_range)
            found = MacroRenameTarget.new(
              MacroRenameKind::Imported,
              import_name.name,
              path,
              resolve_uri_for_template_path(path),
              import_name.name
            )
          end
          if alias_name = import_name.alias
            if ranges_equal?(import_alias_range(import_name, alias_name), target_range)
              found = MacroRenameTarget.new(MacroRenameKind::ImportAlias, import_name.name, path, uri, alias_name)
            end
          end
        end
      end

      if found.nil?
        visitor = MacroCallTargetVisitor.new(
          target_range,
          target_name,
          context,
          uri,
          ->(expr : AST::Expr) : Range? { call_name_range(expr) },
          ->(expr : AST::Expr) : MacroBinding? { resolve_macro_binding(expr, context) },
          ->(macro_name : String) : WorkspaceMacroMatch? { unique_workspace_macro(macro_name) },
          ->(path_uri : String) : String? { template_path_for_uri(path_uri) },
          ->(path : String) : String? { resolve_uri_for_template_path(path) },
          ->(left : Range, right : Range) : Bool { ranges_equal?(left, right) }
        )
        visitor.visit_nodes(ast.body)
        found = visitor.found
      end

      found
    rescue
      nil
    end

    private struct WorkspaceMacroMatch
      getter uri : String
      getter name : String

      def initialize(@uri : String, @name : String) : Nil
      end
    end

    private def unique_workspace_macro(name : String) : WorkspaceMacroMatch?
      matches = Array(WorkspaceMacroMatch).new

      if index = @index
        index.entries.each do |uri, entry|
          entry.macros.each do |macro_info|
            if macro_info.name == name
              matches << WorkspaceMacroMatch.new(uri, macro_info.name)
            end
          end
        end
      else
        @inference.all_macros.each do |uri, macros|
          macros.each do |macro_info|
            if macro_info.name == name
              matches << WorkspaceMacroMatch.new(uri, macro_info.name)
            end
          end
        end
      end

      return unless matches.size == 1
      matches.first
    end

    private class MacroCallTargetVisitor < AST::Visitor
      getter found : MacroRenameTarget?

      def initialize(
        @target_range : Range,
        @target_name : String,
        @context : MacroContext,
        @uri : String,
        @call_name_range : Proc(AST::Expr, Range?),
        @resolve_binding : Proc(AST::Expr, MacroBinding?),
        @unique_workspace_macro : Proc(String, WorkspaceMacroMatch?),
        @template_path_for_uri : Proc(String, String?),
        @resolve_uri_for_path : Proc(String, String?),
        @ranges_equal : Proc(Range, Range, Bool),
      ) : Nil
        @found = nil
      end

      protected def enter_expr(expr : AST::Expr) : Nil
        return if @found
        return unless expr.is_a?(AST::Call)

        callee = expr.callee
        name_range = @call_name_range.call(callee)
        return unless name_range
        return unless @ranges_equal.call(name_range, @target_range)

        if binding = @resolve_binding.call(callee)
          case binding.kind
          when MacroBindingKind::Local
            template_path = @template_path_for_uri.call(@uri)
            @found = MacroRenameTarget.new(
              MacroRenameKind::Local,
              binding.original_name,
              template_path,
              @uri,
              binding.local_name
            )
          when MacroBindingKind::FromImport
            if binding.alias?
              @found = MacroRenameTarget.new(
                MacroRenameKind::ImportAlias,
                binding.original_name,
                binding.path,
                @uri,
                binding.local_name
              )
              return
            end

            path = binding.path
            return unless path
            @found = MacroRenameTarget.new(
              MacroRenameKind::Imported,
              binding.original_name,
              path,
              @resolve_uri_for_path.call(path),
              binding.local_name
            )
          when MacroBindingKind::ImportAlias
            path = binding.path
            return unless path
            @found = MacroRenameTarget.new(
              MacroRenameKind::Imported,
              binding.original_name,
              path,
              @resolve_uri_for_path.call(path),
              binding.local_name
            )
          end
        else
          if callee.is_a?(AST::Name) && callee.value == @target_name
            if unique = @unique_workspace_macro.call(@target_name)
              template_path = @template_path_for_uri.call(unique.uri)
              @found = MacroRenameTarget.new(
                MacroRenameKind::Imported,
                unique.name,
                template_path,
                unique.uri,
                unique.name
              )
            end
          end
        end
      end
    end

    private class MacroCallRenameVisitor < AST::Visitor
      def initialize(
        @context : MacroContext,
        @target : MacroRenameTarget,
        @new_name : String,
        @edits : Array(TextEdit),
        @rename_proc : Proc(AST::Expr, MacroContext, MacroRenameTarget, String, Array(TextEdit), Nil),
      ) : Nil
      end

      protected def enter_expr(expr : AST::Expr) : Nil
        return unless expr.is_a?(AST::Call)
        @rename_proc.call(expr.callee, @context, @target, @new_name, @edits)
      end
    end

    private def rename_macro_imports_and_calls(
      doc_uri : String,
      ast : AST::Template,
      context : MacroContext,
      target : MacroRenameTarget,
      new_name : String,
      edits : Array(TextEdit),
    ) : Nil
      return if target.kind == MacroRenameKind::ImportAlias && doc_uri != target.source_uri

      AST::Walker.walk_nodes(ast.body) do |node|
        next unless node.is_a?(AST::FromImport)
        next unless target.template_path
        next unless path = extract_template_path(node.template)
        next unless path == target.template_path

        node.names.each do |import_name|
          if target.kind == MacroRenameKind::ImportAlias
            next unless doc_uri == target.source_uri
            if alias_name = import_name.alias
              if alias_name == target.local_name
                edits << TextEdit.new(range: import_alias_range(import_name, alias_name), new_text: new_name)
              end
            end
            next
          end

          if import_name.name == target.macro_name
            edits << TextEdit.new(range: import_name_range(import_name), new_text: new_name)
          end
        end
      end

      visitor = MacroCallRenameVisitor.new(
        context,
        target,
        new_name,
        edits,
        ->(callee : AST::Expr, ctx : MacroContext, tgt : MacroRenameTarget, name : String, out_edits : Array(TextEdit)) : Nil {
          rename_macro_call(callee, ctx, tgt, name, out_edits)
        }
      )
      visitor.visit_nodes(ast.body)
    end

    private def rename_macro_call(
      callee : AST::Expr,
      context : MacroContext,
      target : MacroRenameTarget,
      new_name : String,
      edits : Array(TextEdit),
    ) : Nil
      binding = resolve_macro_binding(callee, context)
      unless binding
        if target.kind == MacroRenameKind::Imported && callee.is_a?(AST::Name)
          if callee.value == target.macro_name
            if name_range = call_name_range(callee)
              edits << TextEdit.new(range: name_range, new_text: new_name)
            end
          end
        end
        return
      end

      case target.kind
      when MacroRenameKind::ImportAlias
        return unless binding.kind == MacroBindingKind::FromImport
        return unless binding.alias?
        return unless binding.local_name == target.local_name

        if name_range = call_name_range(callee)
          edits << TextEdit.new(range: name_range, new_text: new_name)
        end
        return
      end

      case binding.kind
      when MacroBindingKind::Local
        return unless target.kind == MacroRenameKind::Local
        return unless binding.original_name == target.macro_name
        return unless name_range = call_name_range(callee)
        edits << TextEdit.new(range: name_range, new_text: new_name)
      when MacroBindingKind::FromImport
        return unless target.template_path && binding.path == target.template_path
        return unless binding.original_name == target.macro_name
        return if binding.alias?
        return unless name_range = call_name_range(callee)
        edits << TextEdit.new(range: name_range, new_text: new_name)
      when MacroBindingKind::ImportAlias
        return unless target.template_path && binding.path == target.template_path
        return unless binding.original_name == target.macro_name
        return unless name_range = call_name_range(callee)
        edits << TextEdit.new(range: name_range, new_text: new_name)
      end
    end

    private def call_name_range(expr : AST::Expr) : Range?
      case expr
      when AST::Name
        span_to_range(expr.span)
      when AST::GetAttr
        getattr_name_range(expr)
      end
    end

    private def getattr_name_range(expr : AST::GetAttr) : Range?
      span = expr.span
      end_col = span.end_pos.column - 1
      start_col = end_col - expr.name.size
      start_col = 0 if start_col < 0
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

    private def extract_template_path(expr : AST::Expr) : String?
      case expr
      when AST::Literal
        value = expr.value
        value.is_a?(String) ? value : nil
      end
    end

    private def template_path_for_uri(uri : String) : String?
      return unless uri.starts_with?("file://")
      full_path = uri.sub(/^file:\/\//, "")

      if root = @root_path
        root = root.rstrip('/')
        if full_path.starts_with?(root)
          relative = full_path[root.size..]
          return relative.lstrip('/')
        end
      end

      File.basename(full_path)
    end

    private def resolve_uri_for_template_path(path : String) : String?
      if path.starts_with?("/")
        return "file://#{File.expand_path(path)}" if File.exists?(path)
      end

      if root = @root_path
        candidate = File.join(root, path)
        return "file://#{File.expand_path(candidate)}" if File.exists?(candidate)
      end

      if index = @index
        return index.entries.keys.find do |uri|
          uri_path = uri.sub(/^file:\/\//, "")
          uri_path.ends_with?("/#{path}") || File.basename(uri_path) == path
        end
      end

      nil
    end

    private class VariableScopeVisitor < AST::Visitor
      getter edits : Array(TextEdit)
      getter target_decl_id : Int32?
      getter target_name : String?
      getter? target_is_context : Bool

      def initialize(
        @target_range : Range?,
        @span_to_range : Proc(Span, Range),
        @collect : Bool = false,
        @new_name : String? = nil,
        @target_decl_id : Int32? = nil,
        @target_name : String? = nil,
        @target_is_context : Bool = false,
      ) : Nil
        @scopes = [Hash(String, Int32).new]
        @decl_counter = 0
        @edits = Array(TextEdit).new
      end

      def visit_target(target : AST::Target) : Nil
        case target
        when AST::Name
          declare(target.value, target.span)
        when AST::TupleLiteral
          target.items.each do |item|
            if item.is_a?(AST::Name)
              declare(item.value, item.span)
            end
          end
        end
      end

      protected def enter_expr(expr : AST::Expr) : Nil
        return unless expr.is_a?(AST::Name)

        name = expr.value
        decl_id = resolve(name)
        range = @span_to_range.call(expr.span)

        if target = @target_range
          if ranges_equal?(range, target)
            if decl_id
              @target_decl_id = decl_id
              @target_name = name
            else
              @target_is_context = true
              @target_name = name
            end
          end
        end

        return unless @collect

        new_name = @new_name
        return unless new_name

        if @target_decl_id && decl_id == @target_decl_id
          @edits << TextEdit.new(range: range, new_text: new_name)
        elsif @target_is_context && decl_id.nil? && name == @target_name
          @edits << TextEdit.new(range: range, new_text: new_name)
        end
      end

      protected def visit_node_children(node : AST::Node) : Nil
        case node
        when AST::For
          visit_expr(node.iter)
          push_scope
          visit_target(node.target)
          visit_nodes(node.body)
          pop_scope
          visit_nodes(node.else_body)
        when AST::Set
          visit_expr(node.value)
          visit_target(node.target)
        when AST::SetBlock
          visit_nodes(node.body)
          visit_target(node.target)
        when AST::Macro
          push_scope
          node.params.each do |param|
            declare(param.name, param.span)
          end
          node.params.each do |param|
            if default = param.default_value
              visit_expr(default)
            end
          end
          visit_nodes(node.body)
          pop_scope
        else
          super
        end
      end

      private def declare(name : String, span : Span) : Nil
        @decl_counter += 1
        decl_id = @decl_counter
        @scopes.last[name] = decl_id

        range = @span_to_range.call(span)
        if target = @target_range
          if ranges_equal?(range, target)
            @target_decl_id = decl_id
            @target_name = name
          end
        end

        return unless @collect

        new_name = @new_name
        return unless new_name

        if @target_decl_id && decl_id == @target_decl_id
          @edits << TextEdit.new(range: range, new_text: new_name)
        end
      end

      private def resolve(name : String) : Int32?
        @scopes.reverse_each do |scope|
          if decl_id = scope[name]?
            return decl_id
          end
        end
        nil
      end

      private def push_scope : Nil
        @scopes << Hash(String, Int32).new
      end

      private def pop_scope : Nil
        @scopes.pop
      end

      private def ranges_equal?(left : Range, right : Range) : Bool
        left.start.line == right.start.line &&
          left.start.character == right.start.character &&
          left.end_pos.line == right.end_pos.line &&
          left.end_pos.character == right.end_pos.character
      end
    end

    private struct MacroImport
      getter path : String
      getter original_name : String
      getter local_name : String

      def initialize(@path : String, @original_name : String, @local_name : String) : Nil
      end

      def alias? : Bool
        @local_name != @original_name
      end
    end

    private struct MacroContext
      getter local_macros : Hash(String, AST::Macro)
      getter from_imports : Hash(String, MacroImport)
      getter import_aliases : Hash(String, String)

      def initialize(
        @local_macros : Hash(String, AST::Macro),
        @from_imports : Hash(String, MacroImport),
        @import_aliases : Hash(String, String),
      ) : Nil
      end
    end

    private enum MacroBindingKind
      Local
      FromImport
      ImportAlias
    end

    private struct MacroBinding
      getter kind : MacroBindingKind
      getter path : String?
      getter original_name : String
      getter local_name : String

      def initialize(@kind : MacroBindingKind, @path : String?, @original_name : String, @local_name : String) : Nil
      end

      def alias? : Bool
        @local_name != @original_name
      end
    end

    private enum MacroRenameKind
      Local
      Imported
      ImportAlias
    end

    private struct MacroRenameTarget
      getter kind : MacroRenameKind
      getter macro_name : String
      getter template_path : String?
      getter source_uri : String?
      getter local_name : String

      def initialize(
        @kind : MacroRenameKind,
        @macro_name : String,
        @template_path : String?,
        @source_uri : String?,
        @local_name : String,
      ) : Nil
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

    private def find_block_target(uri : String, text : String, target_range : Range, name : String) : String?
      ast = parse(text)
      found : String? = nil
      AST::Walker.walk_nodes(ast.body) do |node|
        next if found
        next unless node.is_a?(AST::Block)
        next unless node.name == name
        found = node.name
      end
      found
    rescue
      nil
    end

    private def related_block_uris(start_uri : String) : Set(String)
      parent_for = Hash(String, String).new
      children_for = Hash(String, Set(String)).new { |hash, key| hash[key] = Set(String).new }

      each_workspace_uri do |uri, doc_text|
        begin
          ast = parse(doc_text)
          next unless extends_path = extract_extends_path(ast)
          parent_uri = resolve_uri_for_template_path(extends_path)
          next unless parent_uri
          parent_for[uri] = parent_uri
          children_for[parent_uri] << uri
        rescue
          next
        end
      end

      root = start_uri
      while parent = parent_for[root]?
        root = parent
      end

      related = Set(String).new
      queue = [root]
      until queue.empty?
        current = queue.shift
        next if related.includes?(current)
        related << current
        if children = children_for[current]?
          children.each { |child| queue << child }
        end
      end

      related
    end

    private def extract_extends_path(ast : AST::Template) : String?
      ast.body.each do |node|
        next unless node.is_a?(AST::Extends)
        return extract_template_path(node.template)
      end
      nil
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

      if in_var_context?(tokens, index)
        if prev_token = prev_significant
          if (prev_token.type == TokenType::Punct || prev_token.type == TokenType::Operator) && prev_token.lexeme == "|"
            return RenameContext.new(RenameContextType::None, "", empty_range)
          end
        end
        return RenameContext.new(RenameContextType::Variable, name, range)
      end

      # Check broader context
      if in_block_context?(tokens, index)
        if in_from_import_context?(tokens, index)
          unless %w[from import with context as].includes?(name)
            return RenameContext.new(RenameContextType::Macro, name, range)
          end
        end

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

    private def in_from_import_context?(tokens : Array(Token), index : Int32) : Bool
      first_ident = find_first_ident_after_block_start(tokens, index)
      !!(first_ident && first_ident.lexeme == "from")
    end

    # Convert a Span (1-based lines from lexer) to an LSP Range (0-based lines)
    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column - 1),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column - 1)
      )
    end

    private def ranges_equal?(left : Range, right : Range) : Bool
      left.start.line == right.start.line &&
        left.start.character == right.start.character &&
        left.end_pos.line == right.end_pos.line &&
        left.end_pos.character == right.end_pos.character
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
