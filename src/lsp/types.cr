require "../jinja"

module Jinja
  module LSP
    struct Document
      getter uri : URI
      property version : Int32?
      property text : String
      property template : AST::Template?
      property symbols : SymbolIndex?

      def initialize(@uri : URI, @text : String, @version : Int32? = nil) : Nil
        @template = nil
        @symbols = nil
      end
    end

    struct SymbolDefinition
      getter name : String
      getter kind : LSProtocol::SymbolKind
      getter span : Jinja::Span
      getter detail : String?

      def initialize(
        @name : String,
        @kind : LSProtocol::SymbolKind,
        @span : Jinja::Span,
        @detail : String? = nil,
      ) : Nil
      end
    end

    struct SymbolReference
      getter name : String
      getter span : Jinja::Span

      def initialize(@name : String, @span : Jinja::Span) : Nil
      end
    end

    class SymbolIndex
      getter definitions : Hash(String, Array(SymbolDefinition))
      getter references : Array(SymbolReference)
      getter foldable_spans : Array(Jinja::Span)

      def initialize : Nil
        @definitions = Hash(String, Array(SymbolDefinition)).new { |hash, key| hash[key] = Array(SymbolDefinition).new }
        @references = Array(SymbolReference).new
        @foldable_spans = Array(Jinja::Span).new
      end
    end
  end
end
