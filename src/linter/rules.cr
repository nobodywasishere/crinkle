module Jinja
  module Linter
    module Rules
      class MultipleExtends < Rule
        def initialize : Nil
          super("Lint/MultipleExtends")
        end

        def check(template : AST::Template, _context : Context) : Array(Issue)
          extends_nodes = template.body.select(AST::Extends)
          return Array(Issue).new if extends_nodes.size <= 1

          issues = Array(Issue).new
          extends_nodes[1..].each do |node|
            issues << issue(node.span, "Multiple extends tags found; only one is allowed.")
          end
          issues
        end
      end

      class ExtendsNotFirst < Rule
        def initialize : Nil
          super("Lint/ExtendsNotFirst")
        end

        def check(template : AST::Template, _context : Context) : Array(Issue)
          extends_index = template.body.index { |node| node.is_a?(AST::Extends) }
          return Array(Issue).new unless extends_index

          extends_node = template.body[extends_index].as(AST::Extends)
          before_nodes = template.body[0, extends_index]
          return Array(Issue).new if before_nodes.all? { |node| ignorable_before_extends?(node) }

          [issue(extends_node.span, "Extends must be the first non-whitespace node in template.")]
        end

        private def ignorable_before_extends?(node : AST::Node) : Bool
          case node
          when AST::Text
            node.value.strip.empty?
          when AST::Comment
            true
          else
            false
          end
        end
      end

      class DuplicateBlock < Rule
        def initialize : Nil
          super("Lint/DuplicateBlock")
        end

        def check(template : AST::Template, _context : Context) : Array(Issue)
          seen = Hash(String, Span).new
          issues = Array(Issue).new

          ASTWalker.walk_nodes(template.body) do |node|
            next unless node.is_a?(AST::Block)

            name = node.name
            if seen.has_key?(name)
              issues << issue(node.span, "Duplicate block name '#{name}'.")
            else
              seen[name] = node.span
            end
          end

          issues
        end
      end

      class DuplicateMacro < Rule
        def initialize : Nil
          super("Lint/DuplicateMacro")
        end

        def check(template : AST::Template, _context : Context) : Array(Issue)
          seen = Hash(String, Span).new
          issues = Array(Issue).new

          ASTWalker.walk_nodes(template.body) do |node|
            next unless node.is_a?(AST::Macro)

            name = node.name
            if seen.has_key?(name)
              issues << issue(node.span, "Duplicate macro name '#{name}'.")
            else
              seen[name] = node.span
            end
          end

          issues
        end
      end

      class UnusedMacro < Rule
        def initialize : Nil
          super("Lint/UnusedMacro")
        end

        def check(template : AST::Template, _context : Context) : Array(Issue)
          macros = Hash(String, Span).new
          used = Set(String).new

          ASTWalker.walk_nodes(template.body) do |node|
            if node.is_a?(AST::Macro)
              macros[node.name] ||= node.span
            end
          end

          ASTWalker.walk_nodes(template.body) do |node|
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
            when AST::Extends
              collect_macro_calls(node.template, used)
            when AST::Include
              collect_macro_calls(node.template, used)
            when AST::Import
              collect_macro_calls(node.template, used)
            when AST::FromImport
              collect_macro_calls(node.template, used)
            when AST::CallBlock
              collect_macro_calls(node.callee, used)
              node.args.each { |arg| collect_macro_calls(arg, used) }
              node.kwargs.each { |arg| collect_macro_calls(arg.value, used) }
            when AST::CustomTag
              node.args.each { |arg| collect_macro_calls(arg, used) }
              node.kwargs.each { |arg| collect_macro_calls(arg.value, used) }
            end
          end

          issues = Array(Issue).new
          macros.each do |name, span|
            next if used.includes?(name)
            issues << issue(span, "Macro '#{name}' is never used.")
          end

          issues
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
            node.else_body.each { |child| collect_macro_calls_in_node(child, used) }
          when AST::Set
            collect_macro_calls(node.value, used)
          when AST::SetBlock
            node.body.each { |child| collect_macro_calls_in_node(child, used) }
          when AST::Block
            node.body.each { |child| collect_macro_calls_in_node(child, used) }
          when AST::Macro
            node.body.each { |child| collect_macro_calls_in_node(child, used) }
          when AST::CallBlock
            collect_macro_calls(node.callee, used)
            node.args.each { |arg| collect_macro_calls(arg, used) }
            node.kwargs.each { |arg| collect_macro_calls(arg.value, used) }
            node.body.each { |child| collect_macro_calls_in_node(child, used) }
          when AST::CustomTag
            node.args.each { |arg| collect_macro_calls(arg, used) }
            node.kwargs.each { |arg| collect_macro_calls(arg.value, used) }
            node.body.each { |child| collect_macro_calls_in_node(child, used) }
          when AST::Extends
            collect_macro_calls(node.template, used)
          when AST::Include
            collect_macro_calls(node.template, used)
          when AST::Import
            collect_macro_calls(node.template, used)
          when AST::FromImport
            collect_macro_calls(node.template, used)
          else
            # no-op
          end
        end

        private def collect_macro_calls(expr : AST::Expr, used : Set(String)) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            next unless inner.is_a?(AST::Call)

            callee = inner.callee
            next unless callee.is_a?(AST::Name)

            used << callee.value
          end
        end
      end

      class TrailingWhitespace < Rule
        def initialize : Nil
          super("Style/TrailingWhitespace")
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new
          SourceLines.each_line(context.source) do |line, line_no, offset|
            issues.concat(issues_for_line(line, line_no, offset))
          end

          issues
        end

        private def issues_for_line(line : String, line_no : Int32, line_offset : Int32) : Array(Issue)
          chars = line.chars
          return Array(Issue).new if chars.empty?

          trail_index = chars.size
          while trail_index > 0
            ch = chars[trail_index - 1]
            break unless ch == ' ' || ch == '\t'
            trail_index -= 1
          end

          trail_len = chars.size - trail_index
          return Array(Issue).new if trail_len == 0

          byte_offset = 0
          chars[0, trail_index].each { |char| byte_offset += char.bytesize }
          start_offset = line_offset + byte_offset
          end_offset = line_offset + line.bytesize

          start_pos = Position.new(start_offset, line_no, trail_index + 1)
          end_pos = Position.new(end_offset, line_no, chars.size + 1)
          span = Span.new(start_pos, end_pos)
          [issue(span, "Trailing whitespace.")]
        end
      end

      class MixedIndentation < Rule
        def initialize : Nil
          super("Style/MixedIndentation")
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          SourceLines.each_line(context.source) do |line, line_no, offset|
            leading = leading_whitespace(line)
            next if leading.empty?
            next unless leading.includes?('\t') && leading.includes?(' ')

            span = span_for_leading_whitespace(line, line_no, offset, leading)
            issues << issue(span, "Mixed indentation (tabs and spaces).")
          end

          issues
        end

        private def leading_whitespace(line : String) : String
          index = 0
          while index < line.size
            ch = line.byte_at(index)
            break unless ch == ' '.ord || ch == '\t'.ord
            index += 1
          end
          line.byte_slice(0, index)
        end

        private def span_for_leading_whitespace(line : String, line_no : Int32, offset : Int32, leading : String) : Span
          start_pos = Position.new(offset, line_no, 1)
          end_pos = Position.new(offset + leading.bytesize, line_no, leading.size + 1)
          Span.new(start_pos, end_pos)
        end
      end

      class ExcessiveBlankLines < Rule
        MAX_BLANK_LINES = 2

        def initialize : Nil
          super("Style/ExcessiveBlankLines")
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new
          blank_run = 0

          SourceLines.each_line(context.source) do |line, line_no, offset|
            if line.strip.empty?
              blank_run += 1
              if blank_run > MAX_BLANK_LINES
                span = span_for_line(line, line_no, offset)
                issues << issue(span, "Excessive blank lines (max #{MAX_BLANK_LINES}).")
              end
            else
              blank_run = 0
            end
          end

          issues
        end

        private def span_for_line(line : String, line_no : Int32, offset : Int32) : Span
          start_pos = Position.new(offset, line_no, 1)
          end_pos = Position.new(offset + line.bytesize, line_no, line.size + 1)
          Span.new(start_pos, end_pos)
        end
      end

      class Formatting < Rule
        def initialize : Nil
          super("Style/Formatting")
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          formatted = Formatter.new(context.source).format
          return Array(Issue).new if formatted == context.source

          [issue(full_span(context.source), "File is not formatted.")]
        end

        private def full_span(source : String) : Span
          return Span.new(Position.new(0, 1, 1), Position.new(0, 1, 1)) if source.empty?

          last_line = 1
          last_offset = 0
          last_content = ""

          SourceLines.each_line(source) do |line, line_no, offset|
            last_line = line_no
            last_offset = offset
            last_content = line
          end

          end_pos = Position.new(last_offset + last_content.bytesize, last_line, last_content.size + 1)
          Span.new(Position.new(0, 1, 1), end_pos)
        end
      end
    end

    module SourceLines
      def self.each_line(source : String, & : String, Int32, Int32 ->) : Nil
        lines = source.split("\n", remove_empty: false)
        line_no = 1
        offset = 0

        lines.each_with_index do |line, index|
          yield line, line_no, offset
          line_no += 1
          offset += line.bytesize
          offset += 1 if index < lines.size - 1
        end
      end
    end

    module ASTWalker
      def self.walk_nodes(nodes : Array(AST::Node), & : AST::Node ->) : Nil
        stack = nodes.reverse
        until stack.empty?
          node = stack.pop
          yield node
          children_for(node).each { |child| stack << child }
        end
      end

      private def self.children_for(node : AST::Node) : Array(AST::Node)
        case node
        when AST::If
          node.body + node.else_body
        when AST::For
          node.body + node.else_body
        when AST::SetBlock
          node.body
        when AST::Block
          node.body
        when AST::Macro
          node.body
        when AST::CallBlock
          node.body
        when AST::CustomTag
          node.body
        else
          Array(AST::Node).new
        end
      end

      def self.walk_expr(expr : AST::Expr, & : AST::Expr ->) : Nil
        stack = [expr] of AST::Expr
        until stack.empty?
          current = stack.pop
          yield current
          expr_children(current).each { |child| stack << child }
        end
      end

      private def self.expr_children(expr : AST::Expr) : Array(AST::Expr)
        case expr
        when AST::Binary
          [expr.left, expr.right]
        when AST::Unary
          [expr.expr]
        when AST::Group
          [expr.expr]
        when AST::Call
          children = [expr.callee] of AST::Expr
          expr.args.each { |arg| children << arg }
          expr.kwargs.each { |arg| children << arg.value }
          children
        when AST::Filter
          children = [expr.expr] of AST::Expr
          expr.args.each { |arg| children << arg }
          expr.kwargs.each { |arg| children << arg.value }
          children
        when AST::Test
          children = [expr.expr] of AST::Expr
          expr.args.each { |arg| children << arg }
          expr.kwargs.each { |arg| children << arg.value }
          children
        when AST::GetAttr
          [expr.target]
        when AST::GetItem
          [expr.target, expr.index]
        when AST::ListLiteral
          expr.items
        when AST::TupleLiteral
          expr.items
        when AST::DictLiteral
          children = Array(AST::Expr).new
          expr.pairs.each do |pair|
            children << pair.key
            children << pair.value
          end
          children
        else
          Array(AST::Expr).new
        end
      end
    end
  end
end
