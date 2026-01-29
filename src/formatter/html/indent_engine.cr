require "./tokenizer"
require "./parser"

module Jinja
  module HTML
    class IndentEngine
      getter indent_level : Int32
      getter? in_preformatted : Bool
      getter diagnostics : Array(Diagnostic)

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

      def finalize : Array(Diagnostic)
        @parser.finalize
        @diagnostics = @parser.diagnostics
      end

      private def sync_state : Nil
        @indent_level = @parser.indent_level
        @in_preformatted = @parser.in_preformatted?
      end
    end
  end
end
