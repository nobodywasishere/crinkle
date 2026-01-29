require "./tokenizer"
require "./parser"

module Jinja
  module HTML
    class IndentEngine
      getter indent_level : Int32
      getter? in_preformatted : Bool
      getter diagnostics : Array(Diagnostic)
      @attr_indent : String?
      @preformatted_source_indent : String?

      def initialize(
        @indent_tags : Set(String),
        @void_tags : Set(String),
        @preformatted_tags : Set(String),
      ) : Nil
        @tokenizer = Tokenizer.new
        @parser = Parser.new(@indent_tags, @void_tags, @preformatted_tags)
        @indent_level = 0
        @in_preformatted = false
        @diagnostics = Array(Diagnostic).new
        @attr_indent = nil
        @preformatted_source_indent = nil
      end

      def process_closing(text : String) : Nil
        tokens = @tokenizer.tokens(text)
        @parser.apply_closing(tokens)
        sync_state
      end

      def process_opening(text : String) : Nil
        tokens = @tokenizer.tokens(text)
        @parser.apply_opening(tokens)
        sync_state
      end

      def preformatted_open?(text : String) : Bool
        tokens = @tokenizer.tokens(text)
        @parser.preformatted_open?(tokens)
      end

      def note_preformatted_open(line : String) : Nil
        @preformatted_source_indent = nil
      end

      def clear_preformatted_source : Nil
        @preformatted_source_indent = nil
      end

      def handle_attr_line(
        line : String,
        current_indent : String,
        indent_string : String,
        at_line_start : Bool,
      ) : String?
        stripped = line.lstrip
        if indent = @attr_indent
          output = if at_line_start
                     stripped.empty? ? "" : indent + stripped
                   else
                     line
                   end
          @attr_indent = nil if ends_multiline_tag?(line)
          return output
        end

        if at_line_start && starts_multiline_tag?(stripped)
          @attr_indent = current_indent + indent_string
        end

        nil
      end

      def format_preformatted_line(
        line : String,
        base_indent : String,
        indent_string : String,
        at_line_start : Bool,
      ) : String
        return "" if line.strip.empty?
        return line unless at_line_start
        return line if base_indent.empty?

        stripped = line.lstrip
        return base_indent + stripped if preformatted_end_tag_line?(stripped)
        @preformatted_source_indent ||= leading_whitespace(line)
        return base_indent + indent_string + stripped if jinja_line?(stripped)
        rebase_preformatted_line(line, base_indent, indent_string)
      end

      def finalize : Array(Diagnostic)
        @parser.finalize
        @diagnostics = @parser.diagnostics
      end

      private def sync_state : Nil
        @indent_level = @parser.indent_level
        @in_preformatted = @parser.in_preformatted?
      end

      private def starts_multiline_tag?(text : String) : Bool
        return false unless text.starts_with?("<")
        return false if text.starts_with?("</")
        return false if text.includes?(">")
        true
      end

      private def ends_multiline_tag?(text : String) : Bool
        text.strip.ends_with?(">")
      end

      private def leading_whitespace(text : String) : String
        index = 0
        while index < text.size
          ch = text.byte_at(index)
          break unless ch == ' '.ord || ch == '\t'.ord
          index += 1
        end
        text.byte_slice(0, index)
      end

      private def preformatted_end_tag_line?(line : String) : Bool
        return false unless line.starts_with?("</")

        name = line[2..].split(/[ \t>]/, 2).first?
        return false unless name

        @preformatted_tags.includes?(name.downcase)
      end

      private def jinja_line?(line : String) : Bool
        line.starts_with?("{{") || line.starts_with?("{%") || line.starts_with?("{#")
      end

      private def preformatted_shift(base_indent : String) : String
        source_indent = @preformatted_source_indent
        return base_indent unless source_indent
        return "" if base_indent.size <= source_indent.size
        return base_indent.byte_slice(source_indent.size, base_indent.size - source_indent.size) if base_indent.starts_with?(source_indent)

        base_indent
      end

      private def rebase_preformatted_line(line : String, base_indent : String, indent_string : String) : String
        source_indent = @preformatted_source_indent
        stripped = line.lstrip
        return base_indent + indent_string + stripped unless source_indent

        line_indent = leading_whitespace(line)
        relative_indent = if line_indent.starts_with?(source_indent)
                            line_indent.byte_slice(source_indent.size, line_indent.size - source_indent.size)
                          else
                            line_indent
                          end
        base_indent + indent_string + relative_indent + stripped
      end
    end
  end
end
