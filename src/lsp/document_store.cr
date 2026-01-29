require "./types"

module Crinkle
  module LSP
    class DocumentStore
      def initialize : Nil
        @documents = Hash(String, Document).new
      end

      def open(uri : URI, text : String, version : Int32?) : Document
        document = Document.new(uri, text, version)
        @documents[uri.to_s] = document
        document
      end

      def update(uri : URI, text : String, version : Int32?) : Document
        document = @documents[uri.to_s]?
        if document
          document.text = text
          document.version = version
          document
        else
          open(uri, text, version)
        end
      end

      def fetch(uri : URI) : Document?
        @documents[uri.to_s]?
      end

      def close(uri : URI) : Nil
        @documents.delete(uri.to_s)
      end
    end
  end
end
