require "./html/tokenizer"
require "./html/indent_engine"

module Jinja
  class Formatter
    @preformatted_indent : String?

    # Configuration options for the formatter
    struct Options
      getter indent_string : String
      getter max_line_length : Int32
      getter? html_aware : Bool
      getter? space_inside_braces : Bool
      getter? space_around_operators : Bool
      getter? normalize_whitespace_control : Bool
      getter? normalize_text_indent : Bool

      # HTML tags that increase indentation (block and container elements)
      HTML_INDENT_TAGS = Set{
        "a", "abbr", "address", "article", "aside", "audio",
        "b", "bdi", "bdo", "blockquote", "body", "button",
        "canvas", "caption", "center", "cite", "code", "colgroup",
        "data", "datalist", "dd", "del", "details", "dfn", "dialog",
        "div", "dl", "dt", "em", "fieldset", "figcaption", "figure",
        "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "head",
        "header", "html", "i", "iframe", "ins", "kbd", "label", "legend",
        "li", "main", "map", "mark", "menu", "meter", "nav", "noscript",
        "object", "ol", "optgroup", "option", "output", "p", "picture",
        "pre", "progress", "q", "ruby", "s", "samp", "script", "section",
        "select", "small", "span", "strong", "style", "sub", "summary",
        "sup", "svg", "table", "tbody", "td", "template", "textarea",
        "tfoot", "th", "thead", "time", "tr", "u", "ul", "var", "video",
      }

      # Self-closing HTML tags (void elements)
      HTML_VOID_TAGS = Set{
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr",
      }

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

      def at_line_start? : Bool
        @at_line_start
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
      @html_diagnostics = Array(Diagnostic).new
      @printer = Printer.new(@options)
      @html_engine = HTML::IndentEngine.new(
        Options::HTML_INDENT_TAGS,
        Options::HTML_VOID_TAGS,
        Options::HTML_PREFORMATTED_TAGS,
      )
      @html_tokenizer = HTML::Tokenizer.new
      @source_lines = @source.split('\n', remove_empty: false)
      @jinja_indent = 0
      @html_open_buffer = ""
      @preformatted_indent = nil
      @html_in_tag = false
      @html_attr_quote = nil.as(Char?)
      @string_quote_override = nil.as(Char?)
    end

    def format : String
      format_nodes(@template.body)
      @html_diagnostics = @html_engine.finalize
      @diagnostics = @lexer.diagnostics + @parser.diagnostics + @html_diagnostics
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

      # If not normalizing indent, preserve original text
      unless @options.normalize_text_indent?
        @printer.write_raw(text)
        update_html_attribute_state(text)
        update_html_state_from_text(text)
        return
      end

      # Split text by lines and handle indentation
      lines = text.split('\n', remove_empty: false)
      base_line = node.span.start_pos.line - 1

      lines.each_with_index do |line, i|
        source_line = @source_lines[base_line + i]?
        if i > 0
          @printer.newline
        end

        if attr_output = @html_engine.handle_attr_line(line, current_indent_string, @options.indent_string, @printer.at_line_start?)
          @printer.write_raw(attr_output) unless attr_output.empty?
          update_html_attribute_state(attr_output) unless attr_output.empty?
          process_html_opening_with_buffer(line)
          process_html_closing(line)
          next
        end

        if preformatted_open?(line) && !@html_engine.in_preformatted?
          @preformatted_indent = current_indent_string
          @html_engine.note_preformatted_open(line)
        end

        if @html_engine.in_preformatted?
          base_indent = @preformatted_indent || current_indent_string
          preformatted_output = @html_engine.format_preformatted_line(line, base_indent, @options.indent_string, @printer.at_line_start?)
          @printer.write_raw(preformatted_output) unless preformatted_output.empty?
          update_html_attribute_state(preformatted_output) unless preformatted_output.empty?
          process_html_closing(line)
          process_html_opening_with_buffer(line)
          unless @html_engine.in_preformatted?
            @preformatted_indent = nil
            @html_engine.clear_preformatted_source
          end
          next
        end

        # Strip leading whitespace only at line start
        stripped = @printer.at_line_start? ? line.lstrip : line
        inline_source = source_line ? source_line.lstrip : stripped
        inline_pair = inline_tag_pair?(inline_source)

        # Process closing tags first to dedent before writing
        process_html_closing(stripped) unless inline_pair
        sync_indent

        unless stripped.empty?
          @printer.write(stripped)
          update_html_attribute_state(stripped)
        end

        # Process opening tags after writing to affect following lines
        process_html_opening_with_buffer(stripped) unless inline_pair
      end
    end

    private def process_html_closing(text : String) : Nil
      return unless @options.html_aware?
      @html_engine.process_closing(text)
    end

    private def process_html_opening_with_buffer(text : String) : Nil
      return unless @options.html_aware?

      combined = @html_open_buffer + text
      if inline_tag_pair?(combined)
        @html_open_buffer = pending_open_tag(combined)
        return
      end
      @html_engine.process_opening(combined)

      @html_open_buffer = pending_open_tag(combined)
    end

    private def pending_open_tag(text : String) : String
      last_lt = text.rindex('<')
      return "" unless last_lt

      tail = text[last_lt..]
      return "" if tail.includes?('>')

      tail
    end

    private def preformatted_open?(text : String) : Bool
      return false unless @options.html_aware?
      @html_engine.preformatted_open?(text)
    end

    private def inline_tag_pair?(text : String) : Bool
      return false unless @options.html_aware?
      return false unless text.includes?("<")
      return false unless text.includes?("</")

      regex = /<\/?([a-zA-Z][a-zA-Z0-9:-]*)\b/
      stack = Array(String).new
      index = 0

      while match = regex.match(text, index)
        tag = match[1].downcase
        token = match[0]
        index = match.end(0)
        next if Options::HTML_VOID_TAGS.includes?(tag)

        if token.starts_with?("</")
          return false if stack.empty?
          stack.pop
        else
          stack << tag
        end
      end

      stack.empty?
    end

    private def current_indent_string : String
      level = @options.html_aware? ? (@html_engine.indent_level + @jinja_indent) : @jinja_indent
      @options.indent_string * level
    end

    private def format_comment(node : AST::Comment) : Nil
      sync_indent
      start_delim = node.trim_left? ? "{#-" : "{#"
      end_delim = node.trim_right? ? "-#}" : "#}"
      text = node.text.strip
      if comment_multiline?(text)
        indent = @options.indent_string
        @printer.write(start_delim)
        @printer.newline
        lines = text.split('\n', remove_empty: false)
        lines.each_with_index do |line, i|
          @printer.write(indent)
          @printer.write(line.strip)
          @printer.newline if i < lines.size - 1
        end
        @printer.newline
        @printer.write(end_delim)
      else
        brace_space = @options.space_inside_braces? ? " " : ""
        @printer.write("#{start_delim}#{brace_space}#{text}#{brace_space}#{end_delim}")
      end
    end

    private def comment_multiline?(text : String) : Bool
      return true if text.includes?('\n')
      text.size > @options.max_line_length
    end

    private def format_output(node : AST::Output) : Nil
      sync_indent
      brace_space = @options.space_inside_braces? ? " " : ""
      start_delim = node.trim_left? ? "{{-" : "{{"
      end_delim = node.trim_right? ? "-}}" : "}}"
      @printer.write("#{start_delim}#{brace_space}")
      if quote_override = html_attribute_string_quote_override
        with_string_quote(quote_override) { format_expr(node.expr) }
      else
        format_expr(node.expr)
      end
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
      if node.alias.strip.empty?
        @printer.write(" #{block_end(node.trim_right?)}")
      else
        @printer.write(" as #{node.alias} #{block_end(node.trim_right?)}")
      end
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
      @printer.write("#{block_start(node.trim_left?)} call")

      if call_args = node.call_args
        @printer.write("(")
        format_args_inline(call_args, node.call_kwargs || Array(AST::KeywordArg).new)
        @printer.write(") ")
      else
        @printer.write(" ")
      end

      format_expr(node.callee)
      @printer.write("(")
      format_args_inline(node.args, node.kwargs)
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
        format_args_inline(node.args, node.kwargs)
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
        quote = @string_quote_override || '"'
        escaped = value.gsub("\\", "\\\\")
        if quote == '"'
          escaped = escaped.gsub("\"", "\\\"")
        else
          escaped = escaped.gsub("'", "\\'")
        end
        @printer.write("#{quote}#{escaped}#{quote}")
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
      format_paren_args(expr.args, expr.kwargs, expr.span)
    end

    private def format_filter(expr : AST::Filter) : Nil
      format_expr(expr.expr)
      @printer.write(" | ") if @options.space_around_operators?
      @printer.write("|") unless @options.space_around_operators?
      @printer.write(expr.name)

      unless expr.args.empty? && expr.kwargs.empty?
        format_paren_args(expr.args, expr.kwargs, expr.span)
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
        format_paren_args(expr.args, expr.kwargs, expr.span)
      end
    end

    private def format_list(expr : AST::ListLiteral) : Nil
      if pretty_list?(expr)
        current_level = @printer.indent_level
        @printer.write("[")
        @printer.newline
        @printer.indent_level = current_level + 1
        expr.items.each_with_index do |item, i|
          format_expr(item)
          if i < expr.items.size - 1
            @printer.write(",")
            @printer.newline
          end
        end
        @printer.newline
        @printer.indent_level = current_level
        @printer.write("]")
        return
      end

      @printer.write("[")
      expr.items.each_with_index do |item, i|
        @printer.write(", ") if i > 0
        format_expr(item)
      end
      @printer.write("]")
    end

    private def format_dict(expr : AST::DictLiteral) : Nil
      if pretty_dict?(expr)
        current_level = @printer.indent_level
        @printer.write("{")
        @printer.newline
        @printer.indent_level = current_level + 1
        expr.pairs.each_with_index do |pair, i|
          format_expr(pair.key)
          @printer.write(": ")
          format_expr(pair.value)
          if i < expr.pairs.size - 1
            @printer.write(",")
            @printer.newline
          end
        end
        @printer.newline
        @printer.indent_level = current_level
        @printer.write("}")
        return
      end

      @printer.write("{")
      expr.pairs.each_with_index do |pair, i|
        @printer.write(", ") if i > 0
        format_expr(pair.key)
        @printer.write(": ")
        format_expr(pair.value)
      end
      if expr.pairs.last?.try(&.value).is_a?(AST::DictLiteral)
        @printer.write(" ")
      end
      @printer.write("}")
    end

    private def format_tuple(expr : AST::TupleLiteral) : Nil
      if pretty_tuple?(expr)
        current_level = @printer.indent_level
        @printer.write("(")
        @printer.newline
        @printer.indent_level = current_level + 1
        expr.items.each_with_index do |item, i|
          format_expr(item)
          if i < expr.items.size - 1
            @printer.write(",")
            @printer.newline
          end
        end
        @printer.newline
        @printer.indent_level = current_level
        @printer.write(")")
        return
      end

      @printer.write("(")
      expr.items.each_with_index do |item, i|
        @printer.write(", ") if i > 0
        format_expr(item)
      end
      # Single-element tuples need trailing comma
      @printer.write(",") if expr.items.size == 1
      @printer.write(")")
    end

    private def pretty_list?(expr : AST::ListLiteral) : Bool
      pretty_over_length?(expr)
    end

    private def pretty_dict?(expr : AST::DictLiteral) : Bool
      pretty_over_length?(expr)
    end

    private def pretty_tuple?(expr : AST::TupleLiteral) : Bool
      pretty_over_length?(expr)
    end

    private def collection_literal?(expr : AST::Expr) : Bool
      expr.is_a?(AST::ListLiteral) || expr.is_a?(AST::DictLiteral) || expr.is_a?(AST::TupleLiteral)
    end

    private def pretty_over_length?(expr : AST::Expr) : Bool
      span = expr.span
      return true unless span.start_pos.line == span.end_pos.line

      length = span.end_pos.column - span.start_pos.column + 1
      length > @options.max_line_length
    end

    private def format_args_inline(args : Array(AST::Expr), kwargs : Array(AST::KeywordArg)) : Nil
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

    private def format_args_multiline(args : Array(AST::Expr), kwargs : Array(AST::KeywordArg)) : Nil
      index = 0
      total = args.size + kwargs.size

      args.each do |arg|
        format_expr(arg)
        index += 1
        if index < total
          @printer.write(",")
          @printer.newline
        end
      end

      kwargs.each do |kwarg|
        @printer.write(kwarg.name)
        @printer.write("=")
        format_expr(kwarg.value)
        index += 1
        if index < total
          @printer.write(",")
          @printer.newline
        end
      end
    end

    private def format_paren_args(args : Array(AST::Expr), kwargs : Array(AST::KeywordArg), span : Span) : Nil
      if pretty_args?(args, kwargs, span)
        current_level = @printer.indent_level
        @printer.write("(")
        @printer.newline
        @printer.indent_level = current_level + 1
        format_args_multiline(args, kwargs)
        @printer.newline
        @printer.indent_level = current_level
        @printer.write(")")
      else
        @printer.write("(")
        format_args_inline(args, kwargs)
        @printer.write(")")
      end
    end

    private def pretty_args?(args : Array(AST::Expr), kwargs : Array(AST::KeywordArg), span : Span) : Bool
      return false if args.empty? && kwargs.empty?
      return true unless span.start_pos.line == span.end_pos.line

      length = span.end_pos.column - span.start_pos.column + 1
      length > @options.max_line_length
    end

    private def compute_effective_indent : Int32
      if @options.html_aware?
        if @html_engine.in_preformatted? && @preformatted_indent
          return preformatted_indent_level
        end
        @html_engine.indent_level + @jinja_indent
      else
        @jinja_indent
      end
    end

    private def update_html_state_from_text(text : String) : Nil
      return unless @options.html_aware?

      text.split('\n', remove_empty: false).each do |line|
        process_html_closing(line)
        process_html_opening_with_buffer(line)
      end
    end

    private def update_html_attribute_state(text : String) : Nil
      return unless @options.html_aware?

      i = 0
      while i < text.bytesize
        ch = text.byte_at(i)
        if quote = @html_attr_quote
          if ch == quote.ord
            @html_attr_quote = nil
          end
          i += 1
          next
        end

        if ch == '<'.ord
          @html_in_tag = true
          i += 1
          next
        end

        if ch == '>'.ord
          @html_in_tag = false
          i += 1
          next
        end

        if @html_in_tag && (ch == '"'.ord || ch == '\''.ord)
          @html_attr_quote = ch.chr
        end

        i += 1
      end
    end

    private def html_attribute_string_quote_override : Char?
      return unless @options.html_aware?
      quote = @html_attr_quote
      return unless quote
      quote == '"' ? '\'' : '"'
    end

    private def with_string_quote(quote : Char, & : ->) : Nil
      previous = @string_quote_override
      @string_quote_override = quote
      begin
        yield
      ensure
        @string_quote_override = previous
      end
    end

    private def sync_indent : Nil
      @printer.indent_level = compute_effective_indent
    end

    private def preformatted_indent_level : Int32
      indent = @preformatted_indent
      return 0 unless indent
      return 0 unless indent.each_char.all? { |char| char == ' ' || char == '\t' }

      unit = @options.indent_string
      return 0 if unit.empty?
      return 0 unless indent.starts_with?(unit)

      if indent.size % unit.size == 0
        indent.size // unit.size
      else
        0
      end
    end
  end
end
