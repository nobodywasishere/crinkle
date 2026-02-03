module Crinkle::LSP
  # Provides code actions (quick fixes) for diagnostics
  class CodeActionProvider
    @inference : InferenceEngine
    @root_path : String?
    @index : WorkspaceIndex?

    def initialize(@inference : InferenceEngine, @root_path : String? = nil, @index : WorkspaceIndex? = nil) : Nil
    end

    # Get code actions for the given range and diagnostics
    def code_actions(uri : String, range : Range, context : CodeActionContext, text : String? = nil) : Array(CodeAction)
      actions = Array(CodeAction).new

      context.diagnostics.each do |diagnostic|
        # Track if we've handled this diagnostic via code
        handled = false

        # Extract diagnostic code if present
        code = diagnostic.code

        case code
        when String
          case code
          when "Inference/PossibleTypo"
            if action = typo_fix_action(uri, diagnostic)
              actions << action
              handled = true
            end
          when "Lint/UnknownFunction"
            if text
              import_actions = import_macro_actions(uri, diagnostic, text)
              if !import_actions.empty?
                actions.concat(import_actions)
                handled = true
              end
            end
          end
        end

        # Only try to match by message patterns if not already handled by code
        next if handled

        message = diagnostic.message

        # Typo suggestions: "Did you mean 'X'?"
        if message.includes?("Did you mean")
          if action = typo_fix_from_message(uri, diagnostic)
            actions << action
          end
        end

        # Unclosed tag: "Expected '%}' to close..."
        if message.includes?("Expected '%}'") || message.includes?("unclosed")
          if action = close_tag_action(uri, diagnostic)
            actions << action
          end
        end
      end

      # Remove unused imports when requested range overlaps an unused import name.
      if text
        actions.concat(unused_import_actions(uri, range, text))
      end

      actions
    end

    # Create a code action to fix a typo
    private def typo_fix_action(uri : String, diagnostic : Diagnostic) : CodeAction?
      suggestion = extract_suggestion(diagnostic.message)
      return unless suggestion

      CodeAction.new(
        title: "Change to '#{suggestion}'",
        kind: CodeActionKind::QuickFix,
        diagnostics: [diagnostic],
        edit: WorkspaceEdit.new(
          changes: {uri => [TextEdit.new(range: diagnostic.range, new_text: suggestion)]}
        )
      )
    end

    # Create a code action from a "Did you mean" message
    private def typo_fix_from_message(uri : String, diagnostic : Diagnostic) : CodeAction?
      suggestion = extract_suggestion(diagnostic.message)
      return unless suggestion

      CodeAction.new(
        title: "Change to '#{suggestion}'",
        kind: CodeActionKind::QuickFix,
        diagnostics: [diagnostic],
        edit: WorkspaceEdit.new(
          changes: {uri => [TextEdit.new(range: diagnostic.range, new_text: suggestion)]}
        )
      )
    end

    # Create a code action to close an unclosed tag
    private def close_tag_action(uri : String, diagnostic : Diagnostic) : CodeAction?
      # The fix is to add "%}" at the end of the range
      # This is a simple heuristic - for more complex cases we'd need AST analysis
      fix_position = diagnostic.range.end_pos
      fix_range = Range.new(start: fix_position, end_pos: fix_position)

      CodeAction.new(
        title: "Add missing '%}'",
        kind: CodeActionKind::QuickFix,
        diagnostics: [diagnostic],
        edit: WorkspaceEdit.new(
          changes: {uri => [TextEdit.new(range: fix_range, new_text: " %}")]}
        )
      )
    end

    # Extract suggestion from "Did you mean 'X'?" message
    private def extract_suggestion(message : String) : String?
      # Match patterns like "Did you mean 'suggestion'?" or "did you mean `suggestion`?"
      if match = message.match(/[Dd]id you mean ['`]([^'`]+)['`]/)
        return match[1]
      end

      # Match patterns like "Perhaps you meant 'suggestion'"
      if match = message.match(/[Pp]erhaps you meant ['`]([^'`]+)['`]/)
        return match[1]
      end

      nil
    end

    # Create code actions to import a macro from another template
    private def import_macro_actions(uri : String, diagnostic : Diagnostic, text : String) : Array(CodeAction)
      actions = Array(CodeAction).new

      macro_name = extract_unknown_function_name(diagnostic.message)
      return actions unless macro_name

      candidates = macro_candidates(macro_name, uri)
      candidates.each do |candidate|
        next if candidate.uri == uri

        import_path = template_path_for_uri(candidate.uri)
        next unless import_path
        next if already_imported?(text, import_path, macro_name)

        if edit = build_import_edit(uri, text, macro_name, import_path)
          actions << CodeAction.new(
            title: "Import '#{macro_name}' from \"#{import_path}\"",
            kind: CodeActionKind::QuickFix,
            diagnostics: [diagnostic],
            edit: edit
          )
        end
      end

      actions
    end

    private struct MacroCandidate
      getter uri : String
      getter info : MacroInfo
      getter score : Int32

      def initialize(@uri : String, @info : MacroInfo, @score : Int32) : Nil
      end
    end

    private def macro_candidates(macro_name : String, uri : String) : Array(MacroCandidate)
      candidates = Array(MacroCandidate).new
      source = if index = @index
                 index.all_macros
               else
                 @inference.all_macros
               end

      source.each do |macro_uri, macros|
        macros.each do |macro_info|
          next unless macro_info.name == macro_name
          score = macro_candidate_score(uri, macro_uri, macro_name)
          candidates << MacroCandidate.new(macro_uri, macro_info, score)
        end
      end

      candidates.sort_by! do |candidate|
        import_path = template_path_for_uri(candidate.uri) || candidate.uri
        {-candidate.score, import_path}
      end
      candidates
    end

    private def macro_candidate_score(request_uri : String, macro_uri : String, macro_name : String) : Int32
      score = 0
      score += name_similarity_score(macro_name, macro_name)
      score += path_proximity_score(request_uri, macro_uri)
      score
    end

    private def name_similarity_score(name : String, query : String) : Int32
      name_lower = name.downcase
      query_lower = query.downcase
      return 80 if name_lower == query_lower
      return 60 if name_lower.starts_with?(query_lower)
      return 40 if name_lower.includes?(query_lower)
      10
    end

    private def path_proximity_score(request_uri : String, macro_uri : String) : Int32
      request_path = path_for_uri(request_uri)
      macro_path = path_for_uri(macro_uri)
      return 0 unless request_path && macro_path

      request_rel = relative_path(request_path)
      macro_rel = relative_path(macro_path)

      request_dir = File.dirname(request_rel)
      macro_dir = File.dirname(macro_rel)

      return 50 if request_dir == macro_dir

      request_parts = request_dir.split("/", remove_empty: true)
      macro_parts = macro_dir.split("/", remove_empty: true)

      common = 0
      request_parts.each_with_index do |part, idx|
        break if idx >= macro_parts.size
        break unless macro_parts[idx] == part
        common += 1
      end

      depth_diff = (request_parts.size - macro_parts.size).abs
      (common * 10) - (depth_diff * 3)
    end

    private def path_for_uri(uri : String) : String?
      return unless uri.starts_with?("file://")
      uri.sub(/^file:\/\//, "")
    end

    private def relative_path(path : String) : String
      if root = @root_path
        root = root.rstrip('/')
        return path[root.size..].lstrip('/') if path.starts_with?(root)
      end
      path
    end

    private def extract_unknown_function_name(message : String) : String?
      if match = message.match(/Unknown function ['`]([^'`]+)['`]/)
        return match[1]
      end
      nil
    end

    private def build_import_edit(uri : String, text : String, macro_name : String, import_path : String) : WorkspaceEdit?
      insertion_offset = find_import_insertion_offset(text)
      insertion_pos = position_at(text, insertion_offset)

      prefix = if insertion_offset > 0 && text[insertion_offset - 1]? != '\n'
                 "\n"
               else
                 ""
               end

      insert_text = "#{prefix}{% from \"#{import_path}\" import #{macro_name} %}\n"

      edit = TextEdit.new(
        range: Range.new(start: insertion_pos, end_pos: insertion_pos),
        new_text: insert_text
      )

      WorkspaceEdit.new(changes: {uri => [edit]})
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

    private def already_imported?(text : String, import_path : String, macro_name : String) : Bool
      ast = parse(text)
      found = false
      AST::Walker.walk_nodes(ast.body) do |node|
        next unless node.is_a?(AST::FromImport)

        if path = extract_string_value(node.template)
          next unless path == import_path

          node.names.each do |import_name|
            name = import_name.alias || import_name.name
            if name == macro_name
              found = true
              break
            end
          end
        end
      end
      found
    rescue
      false
    end

    # Create code actions to remove unused import names within the requested range
    private def unused_import_actions(uri : String, range : Range, text : String) : Array(CodeAction)
      actions = Array(CodeAction).new

      begin
        ast = parse(text)
        used_names = collect_used_macro_names(ast.body)

        AST::Walker.walk_nodes(ast.body) do |node|
          next unless node.is_a?(AST::FromImport)

          node.names.each_with_index do |import_name, idx|
            name = import_name.alias || import_name.name
            next if used_names.includes?(name)

            name_range = span_to_range(import_name.span)
            next unless ranges_overlap?(name_range, range)

            if edit = remove_import_name_edit(uri, text, node, idx)
              actions << CodeAction.new(
                title: "Remove unused import '#{name}'",
                kind: CodeActionKind::QuickFix,
                edit: edit
              )
            end
          end
        end
      rescue
        # Return whatever we collected so far
      end

      actions
    end

    private def remove_import_name_edit(uri : String, text : String, node : AST::FromImport, index : Int32) : WorkspaceEdit?
      names = node.names
      return if index >= names.size

      if names.size == 1
        delete_range = expand_to_line(text, node.span)
        edit = TextEdit.new(range: delete_range, new_text: "")
        return WorkspaceEdit.new(changes: {uri => [edit]})
      end

      name_span = names[index].span
      start_offset = name_span.start_pos.offset
      end_offset = name_span.end_pos.offset

      # Prefer removing trailing comma
      right = end_offset
      while right < text.bytesize && text.byte_at(right).chr.in?(" ", "\t")
        right += 1
      end
      if right < text.bytesize && text.byte_at(right).chr == ','
        right += 1
        while right < text.bytesize && text.byte_at(right).chr.in?(" ", "\t")
          right += 1
        end
        delete_range = range_from_offsets(text, start_offset, right)
        edit = TextEdit.new(range: delete_range, new_text: "")
        return WorkspaceEdit.new(changes: {uri => [edit]})
      end

      # Otherwise remove leading comma
      left = start_offset
      while left > 0 && text.byte_at(left - 1).chr.in?(" ", "\t")
        left -= 1
      end
      if left > 0 && text.byte_at(left - 1).chr == ','
        left -= 1
        while left > 0 && text.byte_at(left - 1).chr.in?(" ", "\t")
          left -= 1
        end
        delete_range = range_from_offsets(text, left, end_offset)
        edit = TextEdit.new(range: delete_range, new_text: "")
        return WorkspaceEdit.new(changes: {uri => [edit]})
      end

      delete_range = range_from_offsets(text, start_offset, end_offset)
      edit = TextEdit.new(range: delete_range, new_text: "")
      WorkspaceEdit.new(changes: {uri => [edit]})
    end

    private def collect_used_macro_names(nodes : Array(AST::Node)) : Set(String)
      used = Set(String).new
      AST::Walker.walk_nodes(nodes) do |node|
        case node
        when AST::Output
          collect_macro_calls(node.expr, used)
        when AST::If
          collect_macro_calls(node.test, used)
        when AST::For
          collect_macro_calls(node.iter, used)
        when AST::Set
          collect_macro_calls(node.value, used)
        when AST::SetBlock
          node.body.each { |child| collect_macro_calls_in_node(child, used) }
        when AST::CallBlock
          collect_macro_calls(node.callee, used)
          node.args.each { |arg| collect_macro_calls(arg, used) }
          node.kwargs.each { |kwarg| collect_macro_calls(kwarg.value, used) }
        end
      end
      used
    end

    private def collect_macro_calls_in_node(node : AST::Node, used : Set(String)) : Nil
      case node
      when AST::Output
        collect_macro_calls(node.expr, used)
      when AST::If
        collect_macro_calls(node.test, used)
        node.body.each { |child| collect_macro_calls_in_node(child, used) }
        node.else_body.each { |child| collect_macro_calls_in_node(child, used) }
      when AST::For
        collect_macro_calls(node.iter, used)
        node.body.each { |child| collect_macro_calls_in_node(child, used) }
      when AST::Set
        collect_macro_calls(node.value, used)
      when AST::SetBlock
        node.body.each { |child| collect_macro_calls_in_node(child, used) }
      when AST::CallBlock
        collect_macro_calls(node.callee, used)
        node.args.each { |arg| collect_macro_calls(arg, used) }
        node.kwargs.each { |kwarg| collect_macro_calls(kwarg.value, used) }
        node.body.each { |child| collect_macro_calls_in_node(child, used) }
      end
    end

    private def collect_macro_calls(expr : AST::Expr, used : Set(String)) : Nil
      AST::Walker.walk_expr(expr) do |inner|
        case inner
        when AST::Call
          callee = inner.callee
          used << callee.value if callee.is_a?(AST::Name)
        end
      end
    end

    private def parse(text : String) : AST::Template
      lexer = Lexer.new(text)
      tokens = lexer.lex_all
      parser = Parser.new(tokens)
      parser.parse
    end

    private def extract_string_value(expr : AST::Expr) : String?
      case expr
      when AST::Literal
        value = expr.value
        value.is_a?(String) ? value : nil
      end
    end

    private def find_import_insertion_offset(text : String) : Int32
      ast = parse(text)
      insertion_offset = 0

      ast.body.each do |node|
        case node
        when AST::Extends, AST::Import, AST::FromImport
          insertion_offset = node.span.end_pos.offset
        else
          break
        end
      end

      insertion_offset
    rescue
      0
    end

    private def ranges_overlap?(range1 : Range, range2 : Range) : Bool
      !(range1.end_pos.line < range2.start.line ||
        (range1.end_pos.line == range2.start.line && range1.end_pos.character < range2.start.character) ||
        range1.start.line > range2.end_pos.line ||
        (range1.start.line == range2.end_pos.line && range1.start.character > range2.end_pos.character))
    end

    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column - 1),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column - 1)
      )
    end

    private def range_from_offsets(text : String, start_offset : Int32, end_offset : Int32) : Range
      Range.new(
        start: position_at(text, start_offset),
        end_pos: position_at(text, end_offset)
      )
    end

    private def expand_to_line(text : String, span : Span) : Range
      start_offset = span.start_pos.offset
      end_offset = span.end_pos.offset

      line_start = start_offset
      while line_start > 0 && text.byte_at(line_start - 1).chr != '\n'
        line_start -= 1
      end

      line_end = end_offset
      while line_end < text.bytesize && text.byte_at(line_end).chr != '\n'
        line_end += 1
      end
      line_end += 1 if line_end < text.bytesize && text.byte_at(line_end).chr == '\n'

      range_from_offsets(text, line_start, line_end)
    end

    private def position_at(text : String, offset : Int32) : Position
      line = 0
      character = 0
      current_offset = 0

      text.each_char do |char|
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
end
