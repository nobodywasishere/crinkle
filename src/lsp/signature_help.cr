require "./protocol"
require "./schema_provider"

module Crinkle::LSP
  # Signature context types
  enum SignatureContextType
    None
    Filter
    Function
  end

  # Signature context information
  struct SignatureContext
    property type : SignatureContextType
    property name : String
    property arg_index : Int32

    def initialize(@type : SignatureContextType, @name : String, @arg_index : Int32) : Nil
    end
  end

  # Provides signature help for filter and function calls
  class SignatureHelpProvider
    @schema_provider : SchemaProvider

    def initialize(@schema_provider : SchemaProvider) : Nil
    end

    # Get signature help for the given position
    def signature_help(text : String, position : Position) : SignatureHelp?
      context = analyze_signature_context(text, position)

      case context.type
      when .filter?
        filter_signature_help(context.name, context.arg_index)
      when .function?
        function_signature_help(context.name, context.arg_index)
      end
    end

    # Get signature help for a filter
    private def filter_signature_help(name : String, arg_index : Int32) : SignatureHelp?
      filter = @schema_provider.filter(name)
      return unless filter

      # Build parameter information
      params = filter.params.map do |param|
        label = "#{param.name}: #{param.type}"
        label += " = #{param.default}" if param.default

        doc = param.required? ? "Required" : "Optional"
        doc += " (default: #{param.default})" if param.default

        ParameterInformation.new(label: label, documentation: doc)
      end

      signature = SignatureInformation.new(
        label: @schema_provider.filter_signature(filter),
        documentation: filter.doc,
        parameters: params
      )

      SignatureHelp.new(
        signatures: [signature],
        active_signature: 0,
        active_parameter: arg_index
      )
    end

    # Get signature help for a function
    private def function_signature_help(name : String, arg_index : Int32) : SignatureHelp?
      func = @schema_provider.function(name)
      return unless func

      # Build parameter information
      params = func.params.map do |param|
        label = "#{param.name}: #{param.type}"
        label += " = #{param.default}" if param.default

        doc = param.required? ? "Required" : "Optional"
        doc += " (default: #{param.default})" if param.default

        ParameterInformation.new(label: label, documentation: doc)
      end

      signature = SignatureInformation.new(
        label: @schema_provider.function_signature(func),
        documentation: func.doc,
        parameters: params
      )

      SignatureHelp.new(
        signatures: [signature],
        active_signature: 0,
        active_parameter: arg_index
      )
    end

    # Analyze context to determine which signature to show and which parameter is active
    private def analyze_signature_context(text : String, position : Position) : SignatureContext
      lines = text.split('\n')
      return SignatureContext.new(SignatureContextType::None, "", 0) if position.line >= lines.size

      line = lines[position.line]
      return SignatureContext.new(SignatureContextType::None, "", 0) if position.character > line.size

      # Get text before cursor
      before_cursor = line[0...position.character]

      # Find the most recent opening parenthesis
      paren_pos = before_cursor.rindex('(')
      return SignatureContext.new(SignatureContextType::None, "", 0) unless paren_pos

      # Count commas between the opening paren and cursor to find arg index
      arg_section = before_cursor[(paren_pos + 1)..-1]
      arg_index = arg_section.count(',')

      # Find the function/filter name before the parenthesis
      name_section = before_cursor[0...paren_pos]

      # Check for filter: | name(
      if match = name_section.match(/\|\s*(\w+)\s*$/)
        return SignatureContext.new(SignatureContextType::Filter, match[1], arg_index)
      end

      # Check for function: name(
      if match = name_section.match(/(\w+)\s*$/)
        return SignatureContext.new(SignatureContextType::Function, match[1], arg_index)
      end

      SignatureContext.new(SignatureContextType::None, "", 0)
    end
  end
end
