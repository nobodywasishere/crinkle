require "levenshtein"

module Crinkle
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
              if call_args = node.call_args
                call_args.each { |arg| collect_macro_calls(arg, used) }
              end
              if call_kwargs = node.call_kwargs
                call_kwargs.each { |arg| collect_macro_calls(arg.value, used) }
              end
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
            if call_args = node.call_args
              call_args.each { |arg| collect_macro_calls(arg, used) }
            end
            if call_kwargs = node.call_kwargs
              call_kwargs.each { |arg| collect_macro_calls(arg.value, used) }
            end
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

          # Only highlight the first character to avoid overwhelming the editor
          span = Span.new(Position.new(0, 1, 1), Position.new(1, 1, 2))
          [issue(span, "File is not formatted.")]
        end
      end

      # Schema-aware lint rules for filters, tests, and functions
      class UnknownFilter < Rule
        def initialize(@schema : Schema::Registry) : Nil
          super("Lint/UnknownFilter", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_filter_issues(node.expr, issues)
            when AST::If
              collect_filter_issues(node.test, issues)
            when AST::For
              collect_filter_issues(node.iter, issues)
            when AST::Set
              collect_filter_issues(node.value, issues)
            end
          end

          issues
        end

        private def collect_filter_issues(expr : AST::Expr, issues : Array(Issue)) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            next unless inner.is_a?(AST::Filter)

            unless @schema.filters.has_key?(inner.name)
              issues << issue(inner.span, "Unknown filter '#{inner.name}'.")
            end
          end
        end
      end

      class UnknownTest < Rule
        def initialize(@schema : Schema::Registry) : Nil
          super("Lint/UnknownTest", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::If
              collect_test_issues(node.test, issues)
            when AST::For
              collect_test_issues(node.iter, issues)
            when AST::Set
              collect_test_issues(node.value, issues)
            end
          end

          issues
        end

        private def collect_test_issues(expr : AST::Expr, issues : Array(Issue)) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            next unless inner.is_a?(AST::Test)

            unless @schema.tests.has_key?(inner.name)
              issues << issue(inner.span, "Unknown test '#{inner.name}'.")
            end
          end
        end
      end

      class UnknownFunction < Rule
        def initialize(@schema : Schema::Registry) : Nil
          super("Lint/UnknownFunction", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_function_issues(node.expr, issues)
            when AST::If
              collect_function_issues(node.test, issues)
            when AST::For
              collect_function_issues(node.iter, issues)
            when AST::Set
              collect_function_issues(node.value, issues)
            end
          end

          issues
        end

        private def collect_function_issues(expr : AST::Expr, issues : Array(Issue)) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            next unless inner.is_a?(AST::Call)

            # Check if callee is a simple name (function call)
            callee = inner.callee
            next unless callee.is_a?(AST::Name)

            unless @schema.functions.has_key?(callee.value)
              issues << issue(inner.span, "Unknown function '#{callee.value}'.")
            end
          end
        end
      end

      class WrongArgumentCount < Rule
        def initialize(@schema : Schema::Registry) : Nil
          super("Lint/WrongArgumentCount", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_arg_count_issues(node.expr, issues)
            when AST::If
              collect_arg_count_issues(node.test, issues)
            when AST::For
              collect_arg_count_issues(node.iter, issues)
            when AST::Set
              collect_arg_count_issues(node.value, issues)
            end
          end

          issues
        end

        private def collect_arg_count_issues(expr : AST::Expr, issues : Array(Issue)) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            case inner
            when AST::Filter
              check_filter_args(inner, issues)
            when AST::Test
              check_test_args(inner, issues)
            when AST::Call
              check_function_args(inner, issues)
            end
          end
        end

        private def check_filter_args(node : AST::Filter, issues : Array(Issue)) : Nil
          schema = @schema.filters[node.name]?
          return unless schema

          # Count positional args (first param is the value being filtered)
          provided_positional = node.args.size
          max_positional = schema.params.size - 1 # Exclude first param (the value)

          if provided_positional > max_positional
            issues << issue(
              node.span,
              "Filter '#{node.name}' takes at most #{max_positional} argument(s), got #{provided_positional}."
            )
          end
        end

        private def check_test_args(node : AST::Test, issues : Array(Issue)) : Nil
          schema = @schema.tests[node.name]?
          return unless schema

          # Count positional args (first param is the value being tested)
          provided_positional = node.args.size
          max_positional = schema.params.size - 1 # Exclude first param (the value)

          if provided_positional > max_positional
            issues << issue(
              node.span,
              "Test '#{node.name}' takes at most #{max_positional} argument(s), got #{provided_positional}."
            )
          end
        end

        private def check_function_args(node : AST::Call, issues : Array(Issue)) : Nil
          callee = node.callee
          return unless callee.is_a?(AST::Name)

          schema = @schema.functions[callee.value]?
          return unless schema

          provided_positional = node.args.size
          max_positional = schema.params.size

          if provided_positional > max_positional
            issues << issue(
              node.span,
              "Function '#{callee.value}' takes at most #{max_positional} argument(s), got #{provided_positional}."
            )
          end
        end
      end

      class UnknownKwarg < Rule
        def initialize(@schema : Schema::Registry) : Nil
          super("Lint/UnknownKwarg", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_kwarg_issues(node.expr, issues)
            when AST::If
              collect_kwarg_issues(node.test, issues)
            when AST::For
              collect_kwarg_issues(node.iter, issues)
            when AST::Set
              collect_kwarg_issues(node.value, issues)
            end
          end

          issues
        end

        private def collect_kwarg_issues(expr : AST::Expr, issues : Array(Issue)) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            case inner
            when AST::Filter
              check_filter_kwargs(inner, issues)
            when AST::Test
              check_test_kwargs(inner, issues)
            when AST::Call
              check_function_kwargs(inner, issues)
            end
          end
        end

        private def check_filter_kwargs(node : AST::Filter, issues : Array(Issue)) : Nil
          schema = @schema.filters[node.name]?
          return unless schema

          known_params = schema.params.map(&.name)

          node.kwargs.each do |kwarg|
            unless known_params.includes?(kwarg.name)
              message = "Unknown kwarg '#{kwarg.name}' for filter '#{node.name}'."
              if suggestion = DidYouMean.suggest(kwarg.name, known_params)
                message += " Did you mean '#{suggestion}'?"
              end
              issues << issue(kwarg.span, message)
            end
          end
        end

        private def check_test_kwargs(node : AST::Test, issues : Array(Issue)) : Nil
          schema = @schema.tests[node.name]?
          return unless schema

          known_params = schema.params.map(&.name)

          node.kwargs.each do |kwarg|
            unless known_params.includes?(kwarg.name)
              message = "Unknown kwarg '#{kwarg.name}' for test '#{node.name}'."
              if suggestion = DidYouMean.suggest(kwarg.name, known_params)
                message += " Did you mean '#{suggestion}'?"
              end
              issues << issue(kwarg.span, message)
            end
          end
        end

        private def check_function_kwargs(node : AST::Call, issues : Array(Issue)) : Nil
          callee = node.callee
          return unless callee.is_a?(AST::Name)

          schema = @schema.functions[callee.value]?
          return unless schema

          known_params = schema.params.map(&.name)

          node.kwargs.each do |kwarg|
            unless known_params.includes?(kwarg.name)
              message = "Unknown kwarg '#{kwarg.name}' for function '#{callee.value}'."
              if suggestion = DidYouMean.suggest(kwarg.name, known_params)
                message += " Did you mean '#{suggestion}'?"
              end
              issues << issue(kwarg.span, message)
            end
          end
        end
      end

      class MissingRequiredArgument < Rule
        def initialize(@schema : Schema::Registry) : Nil
          super("Lint/MissingRequiredArgument", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_missing_arg_issues(node.expr, issues)
            when AST::If
              collect_missing_arg_issues(node.test, issues)
            when AST::For
              collect_missing_arg_issues(node.iter, issues)
            when AST::Set
              collect_missing_arg_issues(node.value, issues)
            end
          end

          issues
        end

        private def collect_missing_arg_issues(expr : AST::Expr, issues : Array(Issue)) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            case inner
            when AST::Filter
              check_filter_required(inner, issues)
            when AST::Test
              check_test_required(inner, issues)
            when AST::Call
              check_function_required(inner, issues)
            end
          end
        end

        private def check_filter_required(node : AST::Filter, issues : Array(Issue)) : Nil
          schema = @schema.filters[node.name]?
          return unless schema

          provided_kwargs = node.kwargs.map(&.name).to_set
          provided_positional = node.args.size

          schema.params.each_with_index do |param, index|
            next unless param.required?
            next if index == 0 # Skip first param (the value being filtered)

            # Check if provided as kwarg
            next if provided_kwargs.includes?(param.name)

            # Check if provided as positional arg
            positional_index = index - 1
            next if positional_index < provided_positional

            issues << issue(
              node.span,
              "Filter '#{node.name}' requires argument '#{param.name}'."
            )
          end
        end

        private def check_test_required(node : AST::Test, issues : Array(Issue)) : Nil
          schema = @schema.tests[node.name]?
          return unless schema

          provided_kwargs = node.kwargs.map(&.name).to_set
          provided_positional = node.args.size

          schema.params.each_with_index do |param, index|
            next unless param.required?
            next if index == 0 # Skip first param (the value being tested)

            # Check if provided as kwarg
            next if provided_kwargs.includes?(param.name)

            # Check if provided as positional arg
            positional_index = index - 1
            next if positional_index < provided_positional

            issues << issue(
              node.span,
              "Test '#{node.name}' requires argument '#{param.name}'."
            )
          end
        end

        private def check_function_required(node : AST::Call, issues : Array(Issue)) : Nil
          callee = node.callee
          return unless callee.is_a?(AST::Name)

          schema = @schema.functions[callee.value]?
          return unless schema

          provided_kwargs = node.kwargs.map(&.name).to_set
          provided_positional = node.args.size

          schema.params.each_with_index do |param, index|
            next unless param.required?

            # Check if provided as kwarg
            next if provided_kwargs.includes?(param.name)

            # Check if provided as positional arg
            next if index < provided_positional

            issues << issue(
              node.span,
              "Function '#{callee.value}' requires argument '#{param.name}'."
            )
          end
        end
      end

      class DeprecatedUsage < Rule
        def initialize(@schema : Schema::Registry) : Nil
          super("Lint/DeprecatedUsage", Severity::Warning)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_deprecated_issues(node.expr, issues)
            when AST::If
              collect_deprecated_issues(node.test, issues)
            when AST::For
              collect_deprecated_issues(node.iter, issues)
            when AST::Set
              collect_deprecated_issues(node.value, issues)
            end
          end

          issues
        end

        private def collect_deprecated_issues(expr : AST::Expr, issues : Array(Issue)) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            case inner
            when AST::Filter
              schema = @schema.filters[inner.name]?
              if schema && schema.deprecated?
                issues << issue(inner.span, "Filter '#{inner.name}' is deprecated.")
              end
            when AST::Test
              schema = @schema.tests[inner.name]?
              if schema && schema.deprecated?
                issues << issue(inner.span, "Test '#{inner.name}' is deprecated.")
              end
            when AST::Call
              callee = inner.callee
              if callee.is_a?(AST::Name)
                schema = @schema.functions[callee.value]?
                if schema && schema.deprecated?
                  issues << issue(inner.span, "Function '#{callee.value}' is deprecated.")
                end
              end
            end
          end
        end
      end

      # Callable validation rules - require template context schema
      class CallableNotCallable < Rule
        def initialize(@schema : Schema::Registry, @template_path : String? = nil) : Nil
          super("Lint/CallableNotCallable", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          # Get template context schema if available
          template_context = find_template_context(@template_path)
          return issues unless template_context

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_not_callable_issues(node.expr, template_context, issues)
            when AST::If
              collect_not_callable_issues(node.test, template_context, issues)
            when AST::For
              collect_not_callable_issues(node.iter, template_context, issues)
            when AST::Set
              collect_not_callable_issues(node.value, template_context, issues)
            end
          end

          issues
        end

        private def find_template_context(path : String?) : Schema::TemplateContextSchema?
          return unless path
          @schema.templates[path]?
        end

        private def collect_not_callable_issues(
          expr : AST::Expr,
          template_context : Schema::TemplateContextSchema,
          issues : Array(Issue),
        ) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            next unless inner.is_a?(AST::Call)

            # Check if it's a direct call to a variable (not a function or method)
            callee = inner.callee
            next unless callee.is_a?(AST::Name)

            # Skip if it's a known function
            next if @schema.functions.has_key?(callee.value)

            # Check if the variable is in the template context
            type_name = template_context.context[callee.value]?
            next unless type_name

            # Check if the type is a callable
            callable_schema = @schema.callables[type_name]?
            next unless callable_schema

            # Check if the callable has a default_call
            unless callable_schema.default_call
              message = "Object '#{callee.value}' (#{type_name}) is not directly callable."
              if callable_schema.methods.present?
                method_names = callable_schema.methods.keys.join(", ")
                message += " Available methods: #{method_names}."
              end
              issues << issue(inner.span, message)
            end
          end
        end
      end

      class CallableDefaultCall < Rule
        def initialize(@schema : Schema::Registry, @template_path : String? = nil) : Nil
          super("Lint/CallableDefaultCall", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          # Get template context schema if available
          template_context = find_template_context(@template_path)
          return issues unless template_context

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_default_call_issues(node.expr, template_context, issues)
            when AST::If
              collect_default_call_issues(node.test, template_context, issues)
            when AST::For
              collect_default_call_issues(node.iter, template_context, issues)
            when AST::Set
              collect_default_call_issues(node.value, template_context, issues)
            end
          end

          issues
        end

        private def find_template_context(path : String?) : Schema::TemplateContextSchema?
          return unless path
          @schema.templates[path]?
        end

        private def collect_default_call_issues(
          expr : AST::Expr,
          template_context : Schema::TemplateContextSchema,
          issues : Array(Issue),
        ) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            next unless inner.is_a?(AST::Call)

            callee = inner.callee
            next unless callee.is_a?(AST::Name)
            next if @schema.functions.has_key?(callee.value)

            type_name = template_context.context[callee.value]?
            next unless type_name

            callable_schema = @schema.callables[type_name]?
            next unless callable_schema

            default_call = callable_schema.default_call
            next unless default_call

            # Validate arguments
            validate_method_args(inner, default_call, callee.value, issues)
          end
        end

        private def validate_method_args(
          node : AST::Call,
          method_schema : Schema::MethodSchema,
          name : String,
          issues : Array(Issue),
        ) : Nil
          provided_positional = node.args.size
          max_positional = method_schema.params.size

          if provided_positional > max_positional
            issues << issue(
              node.span,
              "Default call for '#{name}' takes at most #{max_positional} argument(s), got #{provided_positional}."
            )
          end

          # Check required arguments
          provided_kwargs = node.kwargs.map(&.name).to_set

          method_schema.params.each_with_index do |param, index|
            next unless param.required?
            next if provided_kwargs.includes?(param.name)
            next if index < provided_positional

            issues << issue(
              node.span,
              "Default call for '#{name}' requires argument '#{param.name}'."
            )
          end

          # Check kwargs
          known_params = method_schema.params.map(&.name)

          node.kwargs.each do |kwarg|
            unless known_params.includes?(kwarg.name)
              message = "Unknown kwarg '#{kwarg.name}' for default call of '#{name}'."
              if suggestion = DidYouMean.suggest(kwarg.name, known_params)
                message += " Did you mean '#{suggestion}'?"
              end
              issues << issue(kwarg.span, message)
            end
          end
        end
      end

      class CallableUnknownMethod < Rule
        def initialize(@schema : Schema::Registry, @template_path : String? = nil) : Nil
          super("Lint/CallableUnknownMethod", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          # Get template context schema if available
          template_context = find_template_context(@template_path)
          return issues unless template_context

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_unknown_method_issues(node.expr, template_context, issues)
            when AST::If
              collect_unknown_method_issues(node.test, template_context, issues)
            when AST::For
              collect_unknown_method_issues(node.iter, template_context, issues)
            when AST::Set
              collect_unknown_method_issues(node.value, template_context, issues)
            end
          end

          issues
        end

        private def find_template_context(path : String?) : Schema::TemplateContextSchema?
          return unless path
          @schema.templates[path]?
        end

        private def collect_unknown_method_issues(
          expr : AST::Expr,
          template_context : Schema::TemplateContextSchema,
          issues : Array(Issue),
        ) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            next unless inner.is_a?(AST::Call)

            # Check if it's a method call (GetAttr as callee)
            callee = inner.callee
            next unless callee.is_a?(AST::GetAttr)

            # Check if the target is a known variable
            target = callee.target
            next unless target.is_a?(AST::Name)

            type_name = template_context.context[target.value]?
            next unless type_name

            callable_schema = @schema.callables[type_name]?
            next unless callable_schema

            method_name = callee.name
            unless callable_schema.methods.has_key?(method_name)
              message = "Unknown method '#{method_name}' for object '#{target.value}' (#{type_name})."
              known_methods = callable_schema.methods.keys
              if suggestion = DidYouMean.suggest(method_name, known_methods)
                message += " Did you mean '#{suggestion}'?"
              end
              issues << issue(inner.span, message)
            end
          end
        end
      end

      class CallableMethodKwarg < Rule
        def initialize(@schema : Schema::Registry, @template_path : String? = nil) : Nil
          super("Lint/CallableMethodKwarg", Severity::Error)
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new

          # Get template context schema if available
          template_context = find_template_context(@template_path)
          return issues unless template_context

          ASTWalker.walk_nodes(context.template.body) do |node|
            case node
            when AST::Output
              collect_method_kwarg_issues(node.expr, template_context, issues)
            when AST::If
              collect_method_kwarg_issues(node.test, template_context, issues)
            when AST::For
              collect_method_kwarg_issues(node.iter, template_context, issues)
            when AST::Set
              collect_method_kwarg_issues(node.value, template_context, issues)
            end
          end

          issues
        end

        private def find_template_context(path : String?) : Schema::TemplateContextSchema?
          return unless path
          @schema.templates[path]?
        end

        private def collect_method_kwarg_issues(
          expr : AST::Expr,
          template_context : Schema::TemplateContextSchema,
          issues : Array(Issue),
        ) : Nil
          ASTWalker.walk_expr(expr) do |inner|
            next unless inner.is_a?(AST::Call)

            # Check if it's a method call (GetAttr as callee)
            callee = inner.callee
            next unless callee.is_a?(AST::GetAttr)

            # Check if the target is a known variable
            target = callee.target
            next unless target.is_a?(AST::Name)

            type_name = template_context.context[target.value]?
            next unless type_name

            callable_schema = @schema.callables[type_name]?
            next unless callable_schema

            method_name = callee.name
            method_schema = callable_schema.methods[method_name]?
            next unless method_schema

            # Validate arguments
            validate_method_call_args(inner, method_schema, target.value, method_name, issues)
          end
        end

        private def validate_method_call_args(
          node : AST::Call,
          method_schema : Schema::MethodSchema,
          obj_name : String,
          method_name : String,
          issues : Array(Issue),
        ) : Nil
          provided_positional = node.args.size
          max_positional = method_schema.params.size

          if provided_positional > max_positional
            issues << issue(
              node.span,
              "Method '#{obj_name}.#{method_name}' takes at most #{max_positional} argument(s), got #{provided_positional}."
            )
          end

          # Check required arguments
          provided_kwargs = node.kwargs.map(&.name).to_set

          method_schema.params.each_with_index do |param, index|
            next unless param.required?
            next if provided_kwargs.includes?(param.name)
            next if index < provided_positional

            issues << issue(
              node.span,
              "Method '#{obj_name}.#{method_name}' requires argument '#{param.name}'."
            )
          end

          # Check kwargs
          known_params = method_schema.params.map(&.name)

          node.kwargs.each do |kwarg|
            unless known_params.includes?(kwarg.name)
              message = "Unknown kwarg '#{kwarg.name}' for method '#{obj_name}.#{method_name}'."
              if suggestion = DidYouMean.suggest(kwarg.name, known_params)
                message += " Did you mean '#{suggestion}'?"
              end
              issues << issue(kwarg.span, message)
            end
          end
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

    # Helper for "did you mean" suggestions using stdlib Levenshtein
    module DidYouMean
      def self.suggest(unknown : String, known : Array(String), max_distance : Int32 = 2) : String?
        return if known.empty?

        best_match = known.min_by? { |k| Levenshtein.distance(unknown, k) }
        return unless best_match

        dist = Levenshtein.distance(unknown, best_match)
        dist <= max_distance ? best_match : nil
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
