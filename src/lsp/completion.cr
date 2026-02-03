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
    Variable # {{ █ }} - suggest known variables
    Block    # {% block █ %} - suggest block names from parent
    Macro    # {% call █ %} - suggest macro names
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
      when .variable?
        variable_completions(uri, context.prefix)
      when .block?
        block_completions(uri, context.prefix)
      when .macro?
        macro_completions(uri, context.prefix)
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

    # Get variable completions based on inference
    private def variable_completions(uri : String, prefix : String) : Array(CompletionItem)
      variables = @inference.variables_for(uri)
      variables.select do |var|
        var.name.starts_with?(prefix)
      end.map do |var|
        detail = case var.source
                 when .for_loop?    then "loop variable"
                 when .set?         then "assigned variable"
                 when .set_block?   then "block assigned"
                 when .macro_param? then "macro parameter"
                 else                    "context variable"
                 end
        CompletionItem.new(
          label: var.name,
          kind: CompletionItemKind::Variable,
          detail: detail,
          documentation: var.detail,
          sort_text: var.name
        )
      end
    end

    # Get block name completions (from extended parent templates)
    private def block_completions(uri : String, prefix : String) : Array(CompletionItem)
      blocks = @inference.blocks_for(uri)
      blocks.select do |blk|
        blk.starts_with?(prefix)
      end.map do |blk|
        CompletionItem.new(
          label: blk,
          kind: CompletionItemKind::Struct,
          detail: "block",
          documentation: "Override this block from parent template",
          sort_text: blk
        )
      end
    end

    # Get macro completions based on inference
    private def macro_completions(uri : String, prefix : String) : Array(CompletionItem)
      macros = @inference.macros_for(uri)
      macros.select do |mac|
        mac.name.starts_with?(prefix)
      end.map do |mac|
        CompletionItem.new(
          label: mac.name,
          kind: CompletionItemKind::Function,
          detail: mac.signature,
          documentation: "Macro defined in template",
          insert_text: mac.name,
          sort_text: mac.name
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

      # Check for property context: {{ variable.prop█
      if match = before_cursor.match(/(\w+)\.(\w*)$/)
        return CompletionContext.new(CompletionContextType::Property, match[2], match[1])
      end

      # Check for block context: {% block nam█
      if match = before_cursor.match(/\{%\s*block\s+(\w*)$/)
        return CompletionContext.new(CompletionContextType::Block, match[1])
      end

      # Check for macro call context: {% call mac█
      if match = before_cursor.match(/\{%\s*call\s+(\w*)$/)
        return CompletionContext.new(CompletionContextType::Macro, match[1])
      end

      # Check for variable context in output: {{ var█
      # Must be after {{ and not a filter/property/etc
      if match = before_cursor.match(/\{\{\s*(\w*)$/)
        prefix = match[1]
        # If there's a prefix, it could be a variable or function
        # We'll provide both variable and function completions
        return CompletionContext.new(CompletionContextType::Variable, prefix)
      end

      # Check for variable context after keywords: {% for item in var█
      # or {% if var█ or {% set x = var█
      if match = before_cursor.match(/\{%\s*(?:for\s+\w+\s+in|if|elif|set\s+\w+\s*=|print)\s+(\w*)$/)
        return CompletionContext.new(CompletionContextType::Variable, match[1])
      end

      # Check for function context: {{ func█ (when there's already a word)
      # This catches cases like {{ range( where we want function completions
      if match = before_cursor.match(/[{][{%]\s*(\w+)$/)
        return CompletionContext.new(CompletionContextType::Function, match[1])
      end

      CompletionContext.new(CompletionContextType::None, "")
    end
  end
end
