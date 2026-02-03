require "./protocol"
require "./schema_provider"
require "./inference"
require "../lexer/lexer"
require "../parser/parser"

module Crinkle::LSP
  # Completion context types
  enum CompletionContextType
    None
    Filter
    Test
    Function
    Property
  end

  # Completion context information
  struct CompletionContext
    property type : CompletionContextType
    property prefix : String
    property variable : String?

    def initialize(@type : CompletionContextType, @prefix : String, @variable : String? = nil) : Nil
    end
  end

  # Provides completions for filters, tests, functions, and properties
  class CompletionProvider
    @schema_provider : SchemaProvider
    @inference : InferenceEngine

    def initialize(@schema_provider : SchemaProvider, @inference : InferenceEngine) : Nil
    end

    # Get completions for the given position in the document
    def completions(uri : String, text : String, position : Position) : Array(CompletionItem)
      # Get the context at the cursor position
      context = analyze_context(text, position)

      case context.type
      when .filter?
        filter_completions(context.prefix)
      when .test?
        test_completions(context.prefix)
      when .function?
        function_completions(context.prefix)
      when .property?
        if var = context.variable
          property_completions(uri, var, context.prefix)
        else
          Array(CompletionItem).new
        end
      else
        Array(CompletionItem).new
      end
    end

    # Get filter completions
    private def filter_completions(prefix : String) : Array(CompletionItem)
      @schema_provider.filters.values.select do |filter|
        filter.name.starts_with?(prefix)
      end.map do |filter|
        CompletionItem.new(
          label: filter.name,
          kind: CompletionItemKind::Function,
          detail: @schema_provider.filter_args_signature(filter),
          documentation: filter.doc,
          sort_text: filter.name
        )
      end
    end

    # Get test completions
    private def test_completions(prefix : String) : Array(CompletionItem)
      @schema_provider.tests.values.select do |test|
        test.name.starts_with?(prefix)
      end.map do |test|
        CompletionItem.new(
          label: test.name,
          kind: CompletionItemKind::Function,
          detail: @schema_provider.test_args_signature(test),
          documentation: test.doc,
          sort_text: test.name
        )
      end
    end

    # Get function completions
    private def function_completions(prefix : String) : Array(CompletionItem)
      @schema_provider.functions.values.select do |func|
        func.name.starts_with?(prefix)
      end.map do |func|
        CompletionItem.new(
          label: func.name,
          kind: CompletionItemKind::Function,
          detail: @schema_provider.function_signature(func),
          documentation: func.doc,
          sort_text: func.name
        )
      end
    end

    # Get property completions based on inference
    private def property_completions(uri : String, variable : String, prefix : String) : Array(CompletionItem)
      properties = @inference.properties_for(uri, variable)
      properties.select do |prop|
        prop.starts_with?(prefix)
      end.map do |prop|
        CompletionItem.new(
          label: prop,
          kind: CompletionItemKind::Property,
          detail: "property",
          sort_text: prop
        )
      end
    end

    # Analyze the context at the cursor position to determine what kind of completion to provide
    private def analyze_context(text : String, position : Position) : CompletionContext
      lines = text.split('\n')
      return CompletionContext.new(CompletionContextType::None, "") if position.line >= lines.size

      line = lines[position.line]
      return CompletionContext.new(CompletionContextType::None, "") if position.character > line.size

      # Get the text before the cursor
      before_cursor = line[0...position.character]

      # Check for filter context: {{ value | fil█
      if match = before_cursor.match(/\|\s*(\w*)$/)
        return CompletionContext.new(CompletionContextType::Filter, match[1])
      end

      # Check for test context: {% if value is tes█
      if match = before_cursor.match(/\bis\s+(\w*)$/)
        return CompletionContext.new(CompletionContextType::Test, match[1])
      end

      # Check for function context: {{ func█
      # This is tricky - we need to distinguish from variables
      # For now, match word at cursor that follows {{ or {%
      if match = before_cursor.match(/[{][{%]\s*(\w+)$/)
        return CompletionContext.new(CompletionContextType::Function, match[1])
      end

      # Check for property context: {{ variable.prop█
      if match = before_cursor.match(/(\w+)\.(\w*)$/)
        return CompletionContext.new(CompletionContextType::Property, match[2], match[1])
      end

      CompletionContext.new(CompletionContextType::None, "")
    end
  end
end
