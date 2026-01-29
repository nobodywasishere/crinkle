module Crinkle
  module HTML
    class Parser
      getter indent_level : Int32
      getter? in_preformatted : Bool
      getter diagnostics : Array(Diagnostic)

      def initialize(
        @indent_tags : Set(String),
        @void_tags : Set(String),
        @preformatted_tags : Set(String),
      ) : Nil
        @tag_stack = Array(StackFrame).new
        @indent_level = 0
        @in_preformatted = false
        @diagnostics = Array(Diagnostic).new
      end

      def apply_closing(tokens : Array(Token)) : Nil
        tokens.each do |token|
          if @in_preformatted
            if token.kind == TokenKind::EndTag && @preformatted_tags.includes?(token.name)
              close_tag(token)
            end
            next
          end

          next unless token.kind == TokenKind::EndTag
          next if @void_tags.includes?(token.name)
          close_tag(token)
        end
      end

      def apply_opening(tokens : Array(Token)) : Nil
        tokens.each do |token|
          next if @in_preformatted
          next unless token.kind == TokenKind::StartTag || token.kind == TokenKind::SelfClosingTag
          next if @void_tags.includes?(token.name)
          next if token.kind == TokenKind::SelfClosingTag
          open_tag(token)
        end
      end

      def preformatted_open?(tokens : Array(Token)) : Bool
        tokens.any? do |token|
          token.kind == TokenKind::StartTag &&
            @preformatted_tags.includes?(token.name) &&
            !@void_tags.includes?(token.name)
        end
      end

      def finalize : Nil
        @tag_stack.each do |frame|
          @diagnostics << Diagnostic.new(
            DiagnosticType::HtmlUnclosedTag,
            Severity::Warning,
            "Unclosed HTML tag '#{frame.tag}'.",
            frame.span,
          )
        end
      end

      private def open_tag(token : Token) : Nil
        frame = StackFrame.new(token.name, token.span)
        @tag_stack << frame
        @indent_level += 1 if @indent_tags.includes?(token.name)
        @in_preformatted = true if @preformatted_tags.includes?(token.name)
      end

      private def close_tag(token : Token) : Nil
        tag = token.name
        if idx = @tag_stack.rindex { |frame| frame.tag == tag }
          if idx != @tag_stack.size - 1
            @diagnostics << Diagnostic.new(
              DiagnosticType::HtmlMismatchedEndTag,
              Severity::Warning,
              "Mismatched HTML end tag '#{tag}'.",
              token.span,
            )
          end
          @tag_stack.pop(@tag_stack.size - idx)
          @indent_level = @tag_stack.count { |frame| @indent_tags.includes?(frame.tag) }
          @in_preformatted = @tag_stack.any? { |frame| @preformatted_tags.includes?(frame.tag) }
        else
          @diagnostics << Diagnostic.new(
            DiagnosticType::HtmlUnexpectedEndTag,
            Severity::Warning,
            "Unexpected HTML end tag '#{tag}'.",
            token.span,
          )
        end
      end
    end

    struct StackFrame
      getter tag : String
      getter span : Span

      def initialize(@tag : String, @span : Span) : Nil
      end
    end
  end
end
