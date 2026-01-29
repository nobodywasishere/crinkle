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

          template.body.each do |node|
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

      class TrailingWhitespace < Rule
        def initialize : Nil
          super("Style/TrailingWhitespace")
        end

        def check(_template : AST::Template, context : Context) : Array(Issue)
          issues = Array(Issue).new
          source = context.source
          line_no = 1
          offset = 0
          lines = source.split("\n", remove_empty: false)

          lines.each_with_index do |line, index|
            issues.concat(issues_for_line(line, line_no, offset))
            line_no += 1
            offset += line.bytesize
            offset += 1 if index < lines.size - 1
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
          chars[0, trail_index].each { |ch| byte_offset += ch.bytesize }
          start_offset = line_offset + byte_offset
          end_offset = line_offset + line.bytesize

          start_pos = Position.new(start_offset, line_no, trail_index + 1)
          end_pos = Position.new(end_offset, line_no, chars.size + 1)
          span = Span.new(start_pos, end_pos)
          [issue(span, "Trailing whitespace.")]
        end
      end
    end
  end
end
