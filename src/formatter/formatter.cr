module Jinja
  class Formatter
    # Configuration options for the formatter
    struct Options
      getter indent_string : String
      getter max_line_length : Int32
      getter? html_aware : Bool
      getter? space_inside_braces : Bool
      getter? space_around_operators : Bool
      getter? normalize_whitespace_control : Bool
      getter? normalize_text_indent : Bool

      # HTML tags that increase indentation
      HTML_INDENT_TAGS = Set{"html", "head", "body", "div", "section", "article",
                             "nav", "header", "footer", "main", "aside", "ul",
                             "ol", "li", "table", "thead", "tbody", "tr", "form",
                             "dl", "dd", "dt", "figure", "figcaption", "blockquote"}

      # Self-closing HTML tags (void elements)
      HTML_VOID_TAGS = Set{"br", "hr", "img", "input", "meta", "link", "area",
                           "base", "col", "embed", "param", "source", "track", "wbr"}

      # Tags where whitespace is significant (don't format inside)
      HTML_PREFORMATTED_TAGS = Set{"pre", "code", "script", "style", "textarea"}

      def initialize(
        @indent_string : String = "  ",
        @max_line_length : Int32 = 120,
        @html_aware : Bool = true,
        @space_inside_braces : Bool = true,
        @space_around_operators : Bool = true,
        @normalize_whitespace_control : Bool = false,
        @normalize_text_indent : Bool = true,
      ) : Nil
      end
    end

    # Tracks HTML tag nesting for indentation
    private class HtmlContext
      getter indent_level : Int32
      getter? in_preformatted : Bool

      def initialize(@options : Options) : Nil
        @indent_level = 0
        @tag_stack = Array(String).new
        @in_preformatted = false
      end

      def process_text(text : String) : Nil
        return unless @options.html_aware?

        # Scan for HTML tags using regex
        text.scan(/<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/) do |match|
          full = match[0]
          tag = match[1].downcase

          # Skip void/self-closing tags
          next if Options::HTML_VOID_TAGS.includes?(tag)
          next if full.ends_with?("/>")

          if full.starts_with?("</")
            close_tag(tag)
          else
            open_tag(tag)
          end
        end
      end

      def open_tag(tag : String) : Nil
        @tag_stack << tag
        if Options::HTML_PREFORMATTED_TAGS.includes?(tag)
          @in_preformatted = true
        end
        if Options::HTML_INDENT_TAGS.includes?(tag)
          @indent_level += 1
        end
      end

      def close_tag(tag : String) : Nil
        # Find and remove the matching opening tag
        if idx = @tag_stack.rindex(tag)
          @tag_stack.pop(@tag_stack.size - idx)
          # Update preformatted state
          @in_preformatted = @tag_stack.any? { |html_tag| Options::HTML_PREFORMATTED_TAGS.includes?(html_tag) }
          # Recalculate indent level
          @indent_level = @tag_stack.count { |html_tag| Options::HTML_INDENT_TAGS.includes?(html_tag) }
        end
      end
    end

    # Output string builder with indentation management
    private class Printer
      property indent_level : Int32

      def initialize(@options : Options) : Nil
        @buffer = String::Builder.new
        @current_line = String::Builder.new
        @indent_level = 0
        @at_line_start = true
      end

      def indent : Nil
        @indent_level += 1
      end

      def dedent : Nil
        @indent_level -= 1 if @indent_level > 0
      end

      def write(text : String) : Nil
        return if text.empty?

        if @at_line_start && !text.starts_with?("\n")
          @current_line << (@options.indent_string * @indent_level)
          @at_line_start = false
        end

        @current_line << text
      end

      def write_raw(text : String) : Nil
        # Write without any indent processing, but keep line tracking correct
        text.each_char do |char|
          if char == '\n'
            @buffer << @current_line.to_s
            @buffer << "\n"
            @current_line = String::Builder.new
            @at_line_start = true
          else
            @current_line << char
            @at_line_start = false
          end
        end
      end

      def newline : Nil
        @buffer << @current_line.to_s
        @buffer << "\n"
        @current_line = String::Builder.new
        @at_line_start = true
      end

      def write_line(text : String) : Nil
        write(text)
        newline
      end

      def to_s : String
        result = @buffer.to_s
        trailing = @current_line.to_s
        if trailing.empty?
          result
        else
          result + trailing
        end
      end
    end

    getter diagnostics : Array(Diagnostic)

    def initialize(@source : String, @options : Options = Options.new) : Nil
      @lexer = Lexer.new(@source)
      @tokens = @lexer.lex_all
      @parser = Parser.new(@tokens)
      @template = @parser.parse
      @diagnostics = @lexer.diagnostics + @parser.diagnostics
      @printer = Printer.new(@options)
      @html_context = HtmlContext.new(@options)
      @jinja_indent = 0
    end

    def format : String
      format_nodes(@template.body)
      result = @printer.to_s

      # Ensure single trailing newline
      if result.empty?
        ""
      elsif result.ends_with?("\n\n")
        result.rstrip + "\n"
      elsif !result.ends_with?("\n")
        result + "\n"
      else
        result
      end
    end

    private def format_nodes(nodes : Array(AST::Node)) : Nil
      nodes.each do |node|
        format_node(node)
      end
    end

    private def format_node(node : AST::Node) : Nil
      case node
      when AST::Text
        format_text(node)
      when AST::Comment
        format_comment(node)
      when AST::Output
        format_output(node)
      when AST::If
        format_if(node)
      when AST::For
        format_for(node)
      when AST::Set
        format_set(node)
      when AST::SetBlock
        format_set_block(node)
      when AST::Block
        format_block(node)
      when AST::Extends
        format_extends(node)
      when AST::Include
        format_include(node)
      when AST::Import
        format_import(node)
      when AST::FromImport
        format_from_import(node)
      when AST::Macro
        format_macro(node)
      when AST::CallBlock
        format_call_block(node)
      when AST::Raw
        format_raw(node)
      when AST::CustomTag
        format_custom_tag(node)
      end
    end

    private def format_text(node : AST::Text) : Nil
      text = node.value

      # In preformatted context, preserve exactly
      if @html_context.in_preformatted?
        @printer.write_raw(text)
        @html_context.process_text(text)
        return
      end

      # If not normalizing indent, preserve original text
      unless @options.normalize_text_indent?
        @printer.write_raw(text)
        @html_context.process_text(text)
        return
      end

      # Split text by lines and handle indentation
      lines = text.split('\n', remove_empty: false)

      lines.each_with_index do |line, i|
        if i > 0
          @printer.newline
        end

        # Strip leading whitespace (we'll re-indent)
        stripped = line.lstrip

        # Process closing tags first to dedent before writing
        process_closing_tags(stripped)
        sync_indent

        unless stripped.empty?
          @printer.write(stripped)
        end

        # Process opening tags after writing to affect following lines
        process_opening_tags(stripped)
      end
    end

    private def process_closing_tags(text : String) : Nil
      return unless @options.html_aware?

      text.scan(/<\/([a-zA-Z][a-zA-Z0-9]*)[^>]*>/) do |match|
        tag = match[1].downcase
        @html_context.close_tag(tag)
      end
    end

    private def process_opening_tags(text : String) : Nil
      return unless @options.html_aware?

      text.scan(/<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/) do |match|
        full = match[0]
        tag = match[1].downcase

        # Skip if it's a closing tag
        next if full.starts_with?("</")
        # Skip void/self-closing tags
        next if Options::HTML_VOID_TAGS.includes?(tag)
        next if full.ends_with?("/>")

        @html_context.open_tag(tag)
      end
    end

    private def format_comment(node : AST::Comment) : Nil
      sync_indent
      brace_space = @options.space_inside_braces? ? " " : ""
      start_delim = node.trim_left? ? "{#-" : "{#"
      end_delim = node.trim_right? ? "-#}" : "#}"
      text = node.text.strip
      @printer.write("#{start_delim}#{brace_space}#{text}#{brace_space}#{end_delim}")
    end

    private def format_output(node : AST::Output) : Nil
      sync_indent
      brace_space = @options.space_inside_braces? ? " " : ""
      start_delim = node.trim_left? ? "{{-" : "{{"
      end_delim = node.trim_right? ? "-}}" : "}}"
      @printer.write("#{start_delim}#{brace_space}")
      format_expr(node.expr)
      @printer.write("#{brace_space}#{end_delim}")
    end

    private def format_if(node : AST::If) : Nil
      format_if_chain(node, true)
    end

    private def format_for(node : AST::For) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} for ")
      format_target(node.target)
      @printer.write(" in ")
      format_expr(node.iter)
      @printer.write(" #{block_end(node.trim_right?)}")

      @jinja_indent += 1
      format_nodes(node.body)
      @jinja_indent -= 1

      unless node.else_body.empty?
        sync_indent
        @printer.write("#{block_start(node.else_trim_left?)} else #{block_end(node.else_trim_right?)}")
        @jinja_indent += 1
        format_nodes(node.else_body)
        @jinja_indent -= 1
      end

      sync_indent
      @printer.write("#{block_start(node.end_trim_left?)} endfor #{block_end(node.end_trim_right?)}")
    end

    private def format_set(node : AST::Set) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} set ")
      format_target(node.target)
      @printer.write(" = ")
      format_expr(node.value)
      @printer.write(" #{block_end(node.trim_right?)}")
    end

    private def format_set_block(node : AST::SetBlock) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} set ")
      format_target(node.target)
      @printer.write(" #{block_end(node.trim_right?)}")

      @jinja_indent += 1
      format_nodes(node.body)
      @jinja_indent -= 1

      sync_indent
      @printer.write("#{block_start(node.end_trim_left?)} endset #{block_end(node.end_trim_right?)}")
    end

    private def format_block(node : AST::Block) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} block #{node.name} #{block_end(node.trim_right?)}")

      @jinja_indent += 1
      format_nodes(node.body)
      @jinja_indent -= 1

      sync_indent
      @printer.write("#{block_start(node.end_trim_left?)} endblock #{block_end(node.end_trim_right?)}")
    end

    private def format_extends(node : AST::Extends) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} extends ")
      format_expr(node.template)
      @printer.write(" #{block_end(node.trim_right?)}")
    end

    private def format_include(node : AST::Include) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} include ")
      format_expr(node.template)

      if node.ignore_missing?
        @printer.write(" ignore missing")
      end

      unless node.with_context?
        @printer.write(" without context")
      end

      @printer.write(" #{block_end(node.trim_right?)}")
    end

    private def format_import(node : AST::Import) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} import ")
      format_expr(node.template)
      @printer.write(" as #{node.alias} #{block_end(node.trim_right?)}")
    end

    private def format_from_import(node : AST::FromImport) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} from ")
      format_expr(node.template)
      @printer.write(" import ")

      node.names.each_with_index do |name, i|
        @printer.write(", ") if i > 0
        @printer.write(name.name)
        if alias_name = name.alias
          @printer.write(" as #{alias_name}")
        end
      end

      # Only output context suffix when explicitly disabled
      if !node.with_context? && !node.names.empty?
        @printer.write(" without context")
      end

      @printer.write(" #{block_end(node.trim_right?)}")
    end

    private def format_macro(node : AST::Macro) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} macro #{node.name}(")

      node.params.each_with_index do |param, i|
        @printer.write(", ") if i > 0
        @printer.write(param.name)
        if default_val = param.default_value
          @printer.write("=")
          format_expr(default_val)
        end
      end

      @printer.write(") #{block_end(node.trim_right?)}")

      @jinja_indent += 1
      format_nodes(node.body)
      @jinja_indent -= 1

      sync_indent
      @printer.write("#{block_start(node.end_trim_left?)} endmacro #{block_end(node.end_trim_right?)}")
    end

    private def format_call_block(node : AST::CallBlock) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} call ")
      format_expr(node.callee)
      @printer.write("(")
      format_args(node.args, node.kwargs)
      @printer.write(") #{block_end(node.trim_right?)}")

      @jinja_indent += 1
      format_nodes(node.body)
      @jinja_indent -= 1

      sync_indent
      @printer.write("#{block_start(node.end_trim_left?)} endcall #{block_end(node.end_trim_right?)}")
    end

    private def format_raw(node : AST::Raw) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} raw #{block_end(node.trim_right?)}")
      @printer.write_raw(node.text)
      sync_indent
      @printer.write("#{block_start(node.end_trim_left?)} endraw #{block_end(node.end_trim_right?)}")
    end

    private def format_custom_tag(node : AST::CustomTag) : Nil
      sync_indent
      @printer.write("#{block_start(node.trim_left?)} #{node.name}")

      unless node.args.empty? && node.kwargs.empty?
        @printer.write(" ")
        format_args(node.args, node.kwargs)
      end

      if node.body.empty?
        @printer.write(" #{block_end(node.trim_right?)}")
      else
        @printer.write(" #{block_end(node.trim_right?)}")
        @jinja_indent += 1
        format_nodes(node.body)
        @jinja_indent -= 1
        sync_indent
        @printer.write("#{block_start(node.end_trim_left?)} end#{node.name} #{block_end(node.end_trim_right?)}")
      end
    end

    private def format_if_chain(node : AST::If, first : Bool) : Nil
      sync_indent
      if first
        @printer.write("#{block_start(node.trim_left?)} if ")
      else
        @printer.write("#{block_start(node.trim_left?)} elif ")
      end
      format_expr(node.test)
      @printer.write(" #{block_end(node.trim_right?)}")

      @jinja_indent += 1
      format_nodes(node.body)
      @jinja_indent -= 1

      if node.else_body.size == 1
        child = node.else_body.first
        if child.is_a?(AST::If) && child.is_elif?
          format_if_chain(child, false)
        elsif !node.else_body.empty?
          sync_indent
          @printer.write("#{block_start(node.else_trim_left?)} else #{block_end(node.else_trim_right?)}")
          @jinja_indent += 1
          format_nodes(node.else_body)
          @jinja_indent -= 1
        end
      elsif !node.else_body.empty?
        sync_indent
        @printer.write("#{block_start(node.else_trim_left?)} else #{block_end(node.else_trim_right?)}")
        @jinja_indent += 1
        format_nodes(node.else_body)
        @jinja_indent -= 1
      end

      if first
        end_node = last_elif_node(node)
        sync_indent
        @printer.write("#{block_start(end_node.end_trim_left?)} endif #{block_end(end_node.end_trim_right?)}")
      end
    end

    private def last_elif_node(node : AST::If) : AST::If
      current = node
      loop do
        if current.else_body.size == 1
          child = current.else_body.first
          if child.is_a?(AST::If) && child.is_elif?
            current = child
            next
          end
        end
        return current
      end
    end

    private def block_start(trim_left : Bool) : String
      trim_left ? "{%-" : "{%"
    end

    private def block_end(trim_right : Bool) : String
      trim_right ? "-%}" : "%}"
    end

    # Expression formatting

    private def format_expr(expr : AST::Expr) : Nil
      case expr
      when AST::Name
        @printer.write(expr.value)
      when AST::Literal
        format_literal(expr)
      when AST::Binary
        format_binary(expr)
      when AST::Unary
        format_unary(expr)
      when AST::Group
        @printer.write("(")
        format_expr(expr.expr)
        @printer.write(")")
      when AST::Call
        format_call(expr)
      when AST::Filter
        format_filter(expr)
      when AST::Test
        format_test(expr)
      when AST::GetAttr
        format_expr(expr.target)
        @printer.write(".")
        @printer.write(expr.name)
      when AST::GetItem
        format_expr(expr.target)
        @printer.write("[")
        format_expr(expr.index)
        @printer.write("]")
      when AST::ListLiteral
        format_list(expr)
      when AST::DictLiteral
        format_dict(expr)
      when AST::TupleLiteral
        format_tuple(expr)
      end
    end

    private def format_target(target : AST::Target) : Nil
      case target
      when AST::Name
        @printer.write(target.value)
      when AST::GetAttr
        format_expr(target.target)
        @printer.write(".")
        @printer.write(target.name)
      when AST::GetItem
        format_expr(target.target)
        @printer.write("[")
        format_expr(target.index)
        @printer.write("]")
      when AST::TupleLiteral
        target.items.each_with_index do |item, i|
          @printer.write(", ") if i > 0
          format_expr(item)
        end
      end
    end

    private def format_literal(expr : AST::Literal) : Nil
      case value = expr.value
      when String
        # Use double quotes for consistency
        escaped = value.gsub("\\", "\\\\").gsub("\"", "\\\"")
        @printer.write("\"#{escaped}\"")
      when Int64
        @printer.write(value.to_s)
      when Float64
        @printer.write(value.to_s)
      when Bool
        @printer.write(value ? "true" : "false")
      when Nil
        @printer.write("none")
      end
    end

    private def format_binary(expr : AST::Binary) : Nil
      format_expr(expr.left)
      if @options.space_around_operators?
        @printer.write(" #{expr.op} ")
      else
        @printer.write(expr.op)
      end
      format_expr(expr.right)
    end

    private def format_unary(expr : AST::Unary) : Nil
      op = expr.op
      @printer.write(op)
      # Add space after word operators like 'not'
      @printer.write(" ") if op == "not"
      format_expr(expr.expr)
    end

    private def format_call(expr : AST::Call) : Nil
      format_expr(expr.callee)
      @printer.write("(")
      format_args(expr.args, expr.kwargs)
      @printer.write(")")
    end

    private def format_filter(expr : AST::Filter) : Nil
      format_expr(expr.expr)
      @printer.write(" | ") if @options.space_around_operators?
      @printer.write("|") unless @options.space_around_operators?
      @printer.write(expr.name)

      unless expr.args.empty? && expr.kwargs.empty?
        @printer.write("(")
        format_args(expr.args, expr.kwargs)
        @printer.write(")")
      end
    end

    private def format_test(expr : AST::Test) : Nil
      format_expr(expr.expr)
      if expr.negated?
        @printer.write(" is not ")
      else
        @printer.write(" is ")
      end
      @printer.write(expr.name)

      unless expr.args.empty? && expr.kwargs.empty?
        @printer.write("(")
        format_args(expr.args, expr.kwargs)
        @printer.write(")")
      end
    end

    private def format_list(expr : AST::ListLiteral) : Nil
      @printer.write("[")
      expr.items.each_with_index do |item, i|
        @printer.write(", ") if i > 0
        format_expr(item)
      end
      @printer.write("]")
    end

    private def format_dict(expr : AST::DictLiteral) : Nil
      @printer.write("{")
      expr.pairs.each_with_index do |pair, i|
        @printer.write(", ") if i > 0
        format_expr(pair.key)
        @printer.write(": ")
        format_expr(pair.value)
      end
      @printer.write("}")
    end

    private def format_tuple(expr : AST::TupleLiteral) : Nil
      @printer.write("(")
      expr.items.each_with_index do |item, i|
        @printer.write(", ") if i > 0
        format_expr(item)
      end
      # Single-element tuples need trailing comma
      @printer.write(",") if expr.items.size == 1
      @printer.write(")")
    end

    private def format_args(args : Array(AST::Expr), kwargs : Array(AST::KeywordArg)) : Nil
      index = 0

      args.each do |arg|
        @printer.write(", ") if index > 0
        format_expr(arg)
        index += 1
      end

      kwargs.each do |kwarg|
        @printer.write(", ") if index > 0
        @printer.write(kwarg.name)
        @printer.write("=")
        format_expr(kwarg.value)
        index += 1
      end
    end

    private def compute_effective_indent : Int32
      if @options.html_aware?
        @html_context.indent_level + @jinja_indent
      else
        @jinja_indent
      end
    end

    private def sync_indent : Nil
      @printer.indent_level = compute_effective_indent
    end
  end
end
