module Crinkle::LSP
  # Represents an open text document in the LSP server.
  class Document
    getter uri : String
    getter language_id : String
    property text : String
    property version : Int32

    def initialize(@uri : String, @language_id : String, @text : String, @version : Int32) : Nil
    end

    # Update the document content (full sync).
    def update(text : String, version : Int32) : Nil
      @text = text
      @version = version
    end

    # Get the number of lines in the document.
    def line_count : Int32
      @text.count('\n') + 1
    end

    # Get a specific line (0-indexed).
    def line(index : Int32) : String?
      lines = @text.split('\n')
      return if index < 0 || index >= lines.size
      lines[index]
    end

    # Convert an LSP position to a byte offset.
    def offset_at(position : Position) : Int32
      offset = 0
      current_line = 0

      @text.each_char_with_index do |char, idx|
        if current_line == position.line
          # Count characters (UTF-16 code units for LSP)
          char_offset = 0
          remaining = @text[offset..]
          remaining.each_char do |rem_char|
            break if rem_char == '\n'
            break if char_offset >= position.character
            char_offset += 1
          end
          return offset + char_offset.clamp(0, remaining.index('\n') || remaining.size)
        end

        if char == '\n'
          current_line += 1
        end
        offset = idx + 1
      end

      # Position beyond end of document
      @text.bytesize
    end

    # Convert a byte offset to an LSP position.
    def position_at(offset : Int32) : Position
      line = 0
      character = 0
      current_offset = 0

      @text.each_char do |char|
        break if current_offset >= offset

        if char == '\n'
          line += 1
          character = 0
        else
          character += 1
        end
        current_offset += 1
      end

      Position.new(line, character)
    end
  end

  # Stores open documents by URI.
  class DocumentStore
    @documents : Hash(String, Document)

    def initialize : Nil
      @documents = Hash(String, Document).new
    end

    # Open a new document.
    def open(uri : String, language_id : String, text : String, version : Int32) : Document
      doc = Document.new(uri, language_id, text, version)
      @documents[uri] = doc
      doc
    end

    # Update an existing document.
    def update(uri : String, text : String, version : Int32) : Document?
      doc = @documents[uri]?
      doc.try(&.update(text, version))
      doc
    end

    # Close a document.
    def close(uri : String) : Document?
      @documents.delete(uri)
    end

    # Get a document by URI.
    def get(uri : String) : Document?
      @documents[uri]?
    end

    # Check if a document is open.
    def open?(uri : String) : Bool
      @documents.has_key?(uri)
    end

    # Get all open document URIs.
    def uris : Array(String)
      @documents.keys
    end

    # Get the number of open documents.
    def size : Int32
      @documents.size
    end
  end
end
