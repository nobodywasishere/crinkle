require "./protocol"
require "./schema_provider"

module Crinkle::LSP
  # Hover context types
  enum HoverContextType
    None
    Filter
    Test
    Function
  end

  # Hover context information
  struct HoverContext
    property type : HoverContextType
    property name : String

    def initialize(@type : HoverContextType, @name : String) : Nil
    end
  end

  # Provides hover information for filters, tests, and functions
  class HoverProvider
    @schema_provider : SchemaProvider

    def initialize(@schema_provider : SchemaProvider) : Nil
    end

    # Get hover information for the given position
    def hover(text : String, position : Position) : Hover?
      context = analyze_hover_context(text, position)

      case context.type
      when .filter?
        filter_hover(context.name)
      when .test?
        test_hover(context.name)
      when .function?
        function_hover(context.name)
      end
    end

    # Get hover info for a filter
    private def filter_hover(name : String) : Hover?
      filter = @schema_provider.filter(name)
      return unless filter

      # Build markdown documentation
      markdown = String.build do |str|
        str << "```crystal\n"
        str << @schema_provider.filter_signature(filter)
        str << "\n```\n"

        if doc = filter.doc
          str << "\n---\n\n"
          str << doc
        end

        if filter.deprecated?
          str << "\n\n**⚠️ Deprecated**"
        end

        unless filter.examples.empty?
          str << "\n\n**Examples:**\n\n"
          filter.examples.each do |example|
            str << "```jinja\n"
            str << example.input
            str << "\n```\n"
            str << "→ `#{example.output}`\n\n"
          end
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Get hover info for a test
    private def test_hover(name : String) : Hover?
      test = @schema_provider.test(name)
      return unless test

      markdown = String.build do |str|
        str << "```crystal\n"
        str << @schema_provider.test_signature(test)
        str << "\n```\n"

        if doc = test.doc
          str << "\n---\n\n"
          str << doc
        end

        if test.deprecated?
          str << "\n\n**⚠️ Deprecated**"
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Get hover info for a function
    private def function_hover(name : String) : Hover?
      func = @schema_provider.function(name)
      return unless func

      markdown = String.build do |str|
        str << "```crystal\n"
        str << @schema_provider.function_signature(func)
        str << "\n```\n"

        if doc = func.doc
          str << "\n---\n\n"
          str << doc
        end

        if func.deprecated?
          str << "\n\n**⚠️ Deprecated**"
        end
      end

      Hover.new(
        contents: MarkupContent.new(kind: "markdown", value: markdown)
      )
    end

    # Analyze context to find what the user is hovering over
    private def analyze_hover_context(text : String, position : Position) : HoverContext
      lines = text.split('\n')
      return HoverContext.new(HoverContextType::None, "") if position.line >= lines.size

      line = lines[position.line]
      return HoverContext.new(HoverContextType::None, "") if position.character >= line.size

      # Find the word at the cursor position
      # Look backwards and forwards to get the full word
      start_pos = position.character
      end_pos = position.character

      # Move backwards to find start of word
      while start_pos > 0 && line[start_pos - 1] =~ /[a-zA-Z0-9_]/
        start_pos -= 1
      end

      # Move forwards to find end of word
      while end_pos < line.size && line[end_pos] =~ /[a-zA-Z0-9_]/
        end_pos += 1
      end

      word = line[start_pos...end_pos]
      return HoverContext.new(HoverContextType::None, "") if word.empty?

      # Look at context before the word to determine type
      before_word = line[0...start_pos]

      # Check for filter: | word
      if before_word =~ /\|\s*$/
        return HoverContext.new(HoverContextType::Filter, word)
      end

      # Check for test: is word
      if before_word =~ /\bis\s+$/
        return HoverContext.new(HoverContextType::Test, word)
      end

      # Check if it's a function call: word(
      after_word = line[end_pos..-1]? || ""
      if after_word =~ /^\s*\(/
        return HoverContext.new(HoverContextType::Function, word)
      end

      HoverContext.new(HoverContextType::None, "")
    end
  end
end
