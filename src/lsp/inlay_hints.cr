module Crinkle::LSP
  # Provides inlay hints (parameter names for macro calls, filters, tests,
  # and inferred types for set variables)
  class InlayHintProvider
    @inference : InferenceEngine
    @schema_provider : SchemaProvider

    def initialize(@inference : InferenceEngine, @schema_provider : SchemaProvider) : Nil
    end

    # Get inlay hints for the given range
    def inlay_hints(uri : String, text : String, range : Range) : Array(InlayHint)
      hints = Array(InlayHint).new

      begin
        lexer = Lexer.new(text)
        tokens = lexer.lex_all
        parser = Parser.new(tokens)
        ast = parser.parse

        visitor = HintVisitor.new(
          ->(node : AST::Set) : Nil { collect_set_type_hints(node, uri, range, hints) },
          ->(node : AST::CallBlock) : Nil { collect_call_block_hints(node, uri, range, hints) },
          ->(expr : AST::Call) : Nil { collect_call_hints(expr, uri, range, hints) },
          ->(expr : AST::Filter) : Nil { collect_filter_hints(expr, uri, range, hints) },
          ->(expr : AST::Test) : Nil { collect_test_hints(expr, uri, range, hints) }
        )
        visitor.visit_nodes(ast.body)
      rescue
        # Parse error - return empty
      end

      hints
    end

    private class HintVisitor < AST::Visitor
      def initialize(
        @set_hint : Proc(AST::Set, Nil),
        @call_block_hint : Proc(AST::CallBlock, Nil),
        @call_hint : Proc(AST::Call, Nil),
        @filter_hint : Proc(AST::Filter, Nil),
        @test_hint : Proc(AST::Test, Nil),
      ) : Nil
      end

      protected def enter_node(node : AST::Node) : Nil
        case node
        when AST::Set
          @set_hint.call(node)
        when AST::CallBlock
          @call_block_hint.call(node)
        end
      end

      protected def enter_expr(expr : AST::Expr) : Nil
        case expr
        when AST::Call
          @call_hint.call(expr)
        when AST::Filter
          @filter_hint.call(expr)
        when AST::Test
          @test_hint.call(expr)
        end
      end
    end

    # Collect parameter hints for a call expression
    private def collect_call_hints(call : AST::Call, uri : String, range : Range, hints : Array(InlayHint)) : Nil
      # Check if call is within the requested range
      call_range = span_to_range(call.span)
      return unless ranges_overlap?(call_range, range)

      # Get the macro name
      macro_name = extract_callee_name(call.callee)
      return unless macro_name

      # Look up macro info for parameter names
      macro_info = @inference.macro_info(uri, macro_name)
      return unless macro_info

      # Only add hints if there are positional arguments
      return if call.args.empty?

      # Add hint for each positional argument
      call.args.each_with_index do |arg, idx|
        # Skip if we've run out of parameter names
        break if idx >= macro_info.params.size

        param_name = macro_info.params[idx]

        # Skip if this is a simple name that matches the parameter
        # (no need for hint like `text: text`)
        if arg.is_a?(AST::Name) && arg.value == param_name
          next
        end

        # Position hint at the start of the argument
        arg_pos = Position.new(
          line: arg.span.start_pos.line - 1,
          character: arg.span.start_pos.column - 1
        )

        hints << InlayHint.new(
          position: arg_pos,
          label: "#{param_name}:",
          kind: InlayHintKind::Parameter,
          padding_right: true
        )
      end
    end

    # Collect parameter hints for a call block
    private def collect_call_block_hints(call_block : AST::CallBlock, uri : String, range : Range, hints : Array(InlayHint)) : Nil
      # Check if call is within the requested range
      call_range = span_to_range(call_block.span)
      return unless ranges_overlap?(call_range, range)

      # Get the macro name
      macro_name = extract_callee_name(call_block.callee)
      return unless macro_name

      # Look up macro info for parameter names
      macro_info = @inference.macro_info(uri, macro_name)
      return unless macro_info

      # Only add hints if there are positional arguments
      return if call_block.args.empty?

      # Add hint for each positional argument
      call_block.args.each_with_index do |arg, idx|
        break if idx >= macro_info.params.size

        param_name = macro_info.params[idx]

        if arg.is_a?(AST::Name) && arg.value == param_name
          next
        end

        arg_pos = Position.new(
          line: arg.span.start_pos.line - 1,
          character: arg.span.start_pos.column - 1
        )

        hints << InlayHint.new(
          position: arg_pos,
          label: "#{param_name}:",
          kind: InlayHintKind::Parameter,
          padding_right: true
        )
      end
    end

    # Collect parameter hints for a filter expression
    private def collect_filter_hints(filter : AST::Filter, uri : String, range : Range, hints : Array(InlayHint)) : Nil
      # Check if filter is within the requested range
      filter_range = span_to_range(filter.span)
      return unless ranges_overlap?(filter_range, range)

      # Only add hints if there are positional arguments
      return if filter.args.empty?

      # Look up filter schema for parameter names
      schema = @schema_provider.custom_schema || Schema.registry
      filter_schema = schema.filters[filter.name]?
      return unless filter_schema

      # Add hint for each positional argument
      # Note: Skip first parameter (always 'value' for filters)
      filter.args.each_with_index do |arg, idx|
        # Map argument index to parameter index (skip first param which is the input value)
        param_idx = idx + 1
        break if param_idx >= filter_schema.params.size

        param = filter_schema.params[param_idx]

        # Skip if this is a simple name that matches the parameter
        if arg.is_a?(AST::Name) && arg.value == param.name
          next
        end

        # Position hint at the start of the argument
        arg_pos = Position.new(
          line: arg.span.start_pos.line - 1,
          character: arg.span.start_pos.column - 1
        )

        label = "#{"*" if param.variadic?}#{param.name}:"

        hints << InlayHint.new(
          position: arg_pos,
          label: label,
          kind: InlayHintKind::Parameter,
          padding_right: true
        )
      end
    end

    # Collect parameter hints for a test expression
    private def collect_test_hints(test : AST::Test, uri : String, range : Range, hints : Array(InlayHint)) : Nil
      # Check if test is within the requested range
      test_range = span_to_range(test.span)
      return unless ranges_overlap?(test_range, range)

      # Only add hints if there are positional arguments
      return if test.args.empty?

      # Look up test schema for parameter names
      schema = @schema_provider.custom_schema || Schema.registry
      test_schema = schema.tests[test.name]?
      return unless test_schema

      # Add hint for each positional argument
      # Note: Skip first parameter (always 'value' for tests)
      test.args.each_with_index do |arg, idx|
        # Map argument index to parameter index (skip first param which is the input value)
        param_idx = idx + 1
        break if param_idx >= test_schema.params.size

        param = test_schema.params[param_idx]

        # Skip if this is a simple name that matches the parameter
        if arg.is_a?(AST::Name) && arg.value == param.name
          next
        end

        # Position hint at the start of the argument
        arg_pos = Position.new(
          line: arg.span.start_pos.line - 1,
          character: arg.span.start_pos.column - 1
        )

        label = "#{"*" if param.variadic?}#{param.name}:"

        hints << InlayHint.new(
          position: arg_pos,
          label: label,
          kind: InlayHintKind::Parameter,
          padding_right: true
        )
      end
    end

    # Collect type hints for set variables
    private def collect_set_type_hints(node : AST::Set, uri : String, range : Range, hints : Array(InlayHint)) : Nil
      set_range = span_to_range(node.span)
      return unless ranges_overlap?(set_range, range)

      inferred_type = infer_expr_type(node.value, uri)
      return unless inferred_type

      case target = node.target
      when AST::Name
        add_type_hint(target, inferred_type, hints)
      when AST::TupleLiteral
        if node.value.is_a?(AST::TupleLiteral)
          values = node.value.as(AST::TupleLiteral).items
          target.items.each_with_index do |item, idx|
            next unless item.is_a?(AST::Name)
            next unless idx < values.size

            item_type = infer_expr_type(values[idx], uri)
            next unless item_type

            add_type_hint(item, item_type, hints)
          end
        end
      end
    end

    private def add_type_hint(target : AST::Name, inferred_type : String, hints : Array(InlayHint)) : Nil
      pos = Position.new(
        line: target.span.end_pos.line - 1,
        character: target.span.end_pos.column - 1
      )

      hints << InlayHint.new(
        position: pos,
        label: ": #{inferred_type}",
        kind: InlayHintKind::Type,
        padding_left: true,
        padding_right: true
      )
    end

    private def infer_expr_type(expr : AST::Expr, uri : String) : String?
      case expr
      when AST::Literal
        value = expr.value
        case value
        when String
          "String"
        when Int64
          "Int64"
        when Float64
          "Float64"
        when Bool
          "Bool"
        when Nil
          "Nil"
        end
      when AST::ListLiteral
        "Array"
      when AST::DictLiteral
        "Hash"
      when AST::TupleLiteral
        "Tuple"
      when AST::Group
        infer_expr_type(expr.expr, uri)
      when AST::Unary
        infer_expr_type(expr.expr, uri)
      when AST::Binary
        left = infer_expr_type(expr.left, uri)
        right = infer_expr_type(expr.right, uri)
        infer_binary_type(expr.op, left, right)
      when AST::Filter
        schema = @schema_provider.custom_schema || Schema.registry
        filter_schema = schema.filters[expr.name]?
        filter_schema.try(&.returns)
      when AST::Test
        "Bool"
      when AST::Call
        if callee_name = extract_callee_name(expr.callee)
          schema = @schema_provider.custom_schema || Schema.registry
          if func = schema.functions[callee_name]?
            return func.returns
          end
        end
        nil
      end
    end

    private def infer_binary_type(op : String, left : String?, right : String?) : String?
      return unless left && right

      case op
      when "and", "or", "==", "!=", "<", ">", "<=", ">=", "in", "not in", "is", "is not"
        "Bool"
      when "+", "-", "*", "%", "/", "//", "**"
        infer_numeric_type(op, left, right)
      when "~"
        if left == "String" || right == "String"
          "String"
        end
      end
    end

    private def infer_numeric_type(op : String, left : String, right : String) : String?
      numeric = ["Int64", "Float64", "Number"]
      return unless numeric.includes?(left) && numeric.includes?(right)

      if op == "/"
        return "Float64" if left == "Float64" || right == "Float64"
        return "Number" if left == "Number" || right == "Number"
        return "Float64"
      end

      return "Float64" if left == "Float64" || right == "Float64"
      return "Number" if left == "Number" || right == "Number"
      "Int64"
    end

    # Extract callee name from expression
    private def extract_callee_name(expr : AST::Expr) : String?
      case expr
      when AST::Name
        expr.value
      when AST::GetAttr
        expr.name
      end
    end

    # Check if two ranges overlap
    private def ranges_overlap?(range1 : Range, range2 : Range) : Bool
      # range1 starts before range2 ends AND range1 ends after range2 starts
      !(range1.end_pos.line < range2.start.line ||
        (range1.end_pos.line == range2.start.line && range1.end_pos.character < range2.start.character) ||
        range1.start.line > range2.end_pos.line ||
        (range1.start.line == range2.end_pos.line && range1.start.character > range2.end_pos.character))
    end

    # Convert a Span (1-based lines from lexer) to an LSP Range (0-based lines)
    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column - 1),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column - 1)
      )
    end
  end
end
