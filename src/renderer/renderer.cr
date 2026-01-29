module Jinja
  class Renderer
    getter diagnostics : Array(Diagnostic)

    def initialize(@environment : Environment = Environment.new) : Nil
      @diagnostics = Array(Diagnostic).new
      @scopes = Array(Hash(String, Value)).new
    end

    def render(
      template : AST::Template,
      context : Hash(String, Value) = Hash(String, Value).new,
    ) : String
      @diagnostics.clear
      @scopes.clear
      @scopes << context.dup
      render_nodes(template.body)
    end

    private def render_nodes(nodes : Array(AST::Node)) : String
      String.build do |io|
        nodes.each do |node|
          io << render_node(node)
        end
      end
    end

    private def render_node(node : AST::Node) : String
      case node
      when AST::Text
        node.value
      when AST::Raw
        node.text
      when AST::Output
        value = eval_expr(node.expr)
        value_to_s(value)
      when AST::If
        if truthy?(eval_expr(node.test))
          render_nodes(node.body)
        else
          render_nodes(node.else_body)
        end
      when AST::For
        render_for(node)
      when AST::Set
        assign(node.target.value, eval_expr(node.value))
        ""
      when AST::SetBlock
        assign(node.target.value, render_nodes(node.body))
        ""
      when AST::CustomTag
        emit_diagnostic(
          DiagnosticType::UnknownTagRenderer,
          "No renderer registered for custom tag '#{node.name}'.",
          node.span
        )
        render_nodes(node.body)
      when AST::Template
        render_nodes(node.body)
      else
        emit_diagnostic(
          DiagnosticType::UnsupportedNode,
          "Renderer does not support #{node.class.name}.",
          node.span
        )
        ""
      end
    end

    private def render_for(node : AST::For) : String
      iterable = eval_expr(node.iter)
      items = to_iterable(iterable)

      unless items
        emit_diagnostic(
          DiagnosticType::NotIterable,
          "Expected iterable in for loop.",
          node.iter.span
        )
        return render_nodes(node.else_body)
      end

      return render_nodes(node.else_body) if items.empty?

      String.build do |io|
        items.each do |item|
          push_scope
          assign(node.target.value, item)
          io << render_nodes(node.body)
          pop_scope
        end
      end
    end

    private def eval_expr(expr : AST::Expr) : Value
      case expr
      when AST::Literal
        expr.value
      when AST::Name
        lookup(expr)
      when AST::Group
        eval_expr(expr.expr)
      when AST::Unary
        eval_unary(expr)
      when AST::Binary
        eval_binary(expr)
      when AST::Call
        eval_call(expr)
      when AST::Filter
        eval_filter(expr)
      when AST::Test
        eval_test(expr)
      when AST::GetAttr
        eval_get_attr(expr)
      when AST::GetItem
        eval_get_item(expr)
      when AST::ListLiteral
        expr.items.map { |item| eval_expr(item) }
      when AST::TupleLiteral
        expr.items.map { |item| eval_expr(item) }
      when AST::DictLiteral
        eval_dict(expr)
      else
        emit_diagnostic(
          DiagnosticType::UnsupportedNode,
          "Renderer does not support #{expr.class.name}.",
          expr.span
        )
        nil
      end
    end

    private def eval_unary(expr : AST::Unary) : Value
      value = eval_expr(expr.expr)
      case expr.op
      when "not"
        !truthy?(value)
      when "+"
        number = to_number(value, expr.span)
        number
      when "-"
        number = to_number(value, expr.span)
        number.nil? ? nil : -number
      else
        emit_invalid_operand(expr.op, expr.span)
        nil
      end
    end

    private def eval_binary(expr : AST::Binary) : Value
      case expr.op
      when "and"
        left = eval_expr(expr.left)
        return left unless truthy?(left)
        eval_expr(expr.right)
      when "or"
        left = eval_expr(expr.left)
        return left if truthy?(left)
        eval_expr(expr.right)
      when "in", "not in"
        left = eval_expr(expr.left)
        right = eval_expr(expr.right)
        result = value_in?(left, right)
        expr.op == "not in" ? !result : result
      when "=="
        eval_expr(expr.left) == eval_expr(expr.right)
      when "!="
        eval_expr(expr.left) != eval_expr(expr.right)
      when "<", "<=", ">", ">="
        compare(expr.op, eval_expr(expr.left), eval_expr(expr.right), expr.span)
      when "+", "-", "*", "/", "//", "%", "**"
        math(expr.op, eval_expr(expr.left), eval_expr(expr.right), expr.span)
      when "~"
        left = eval_expr(expr.left)
        right = eval_expr(expr.right)
        value_to_s(left) + value_to_s(right)
      else
        emit_invalid_operand(expr.op, expr.span)
        nil
      end
    end

    private def eval_call(expr : AST::Call) : Value
      args, kwargs = eval_args(expr.args, expr.kwargs)
      case callee = expr.callee
      when AST::Name
        name = callee.value
        if fn = @environment.functions[name]?
          return fn.call(args, kwargs)
        end
        emit_diagnostic(
          DiagnosticType::UnknownFunction,
          "Unknown function '#{name}'.",
          callee.span
        )
        nil
      else
        emit_diagnostic(
          DiagnosticType::UnsupportedNode,
          "Renderer only supports calling named functions.",
          callee.span
        )
        nil
      end
    end

    private def eval_filter(expr : AST::Filter) : Value
      value = eval_expr(expr.expr)
      args, kwargs = eval_args(expr.args, expr.kwargs)
      if filter = @environment.filters[expr.name]?
        return filter.call(value, args, kwargs)
      end
      emit_diagnostic(
        DiagnosticType::UnknownFilter,
        "Unknown filter '#{expr.name}'.",
        expr.span
      )
      value
    end

    private def eval_test(expr : AST::Test) : Value
      value = eval_expr(expr.expr)
      args, kwargs = eval_args(expr.args, expr.kwargs)
      if test = @environment.tests[expr.name]?
        result = test.call(value, args, kwargs)
        return expr.negated? ? !result : result
      end
      emit_diagnostic(
        DiagnosticType::UnknownTest,
        "Unknown test '#{expr.name}'.",
        expr.span
      )
      expr.negated? ? true : false
    end

    private def eval_get_attr(expr : AST::GetAttr) : Value
      target = eval_expr(expr.target)
      return target[expr.name]? if target.is_a?(Hash(String, Value))
      nil
    end

    private def eval_get_item(expr : AST::GetItem) : Value
      target = eval_expr(expr.target)
      index = eval_expr(expr.index)
      case target
      when Array(Value)
        return unless index.is_a?(Int64)
        target[index]?
      when Hash(String, Value)
        target[index.to_s]?
      end
      nil
    end

    private def eval_dict(expr : AST::DictLiteral) : Hash(String, Value)
      pairs = Hash(String, Value).new
      expr.pairs.each do |pair|
        key = eval_expr(pair.key)
        value = eval_expr(pair.value)
        pairs[key.to_s] = value
      end
      pairs
    end

    private def eval_args(
      args : Array(AST::Expr),
      kwargs : Array(AST::KeywordArg),
    ) : {Array(Value), Hash(String, Value)}
      eval_args = args.map { |arg| eval_expr(arg) }
      eval_kwargs = Hash(String, Value).new
      kwargs.each do |keyword|
        eval_kwargs[keyword.name] = eval_expr(keyword.value)
      end
      {eval_args, eval_kwargs}
    end

    private def lookup(expr : AST::Name) : Value
      @scopes.reverse_each do |scope|
        if scope.has_key?(expr.value)
          return scope[expr.value]
        end
      end
      emit_diagnostic(
        DiagnosticType::UnknownVariable,
        "Unknown variable '#{expr.value}'.",
        expr.span
      )
      nil
    end

    private def assign(name : String, value : Value) : Nil
      @scopes.last[name] = value
    end

    private def push_scope : Nil
      @scopes << Hash(String, Value).new
    end

    private def pop_scope : Nil
      @scopes.pop
    end

    private def truthy?(value : Value) : Bool
      case value
      when Nil
        false
      when Bool
        value
      when Int64
        value != 0
      when Float64
        value != 0.0
      when String
        !value.empty?
      when Array(Value)
        !value.empty?
      when Hash(String, Value)
        !value.empty?
      else
        true
      end
    end

    private def value_to_s(value : Value) : String
      case value
      when Nil
        ""
      when Bool
        value ? "true" : "false"
      else
        value.to_s
      end
    end

    private def to_number(value : Value, span : Span) : Float64?
      case value
      when Int64
        value.to_f
      when Float64
        value
      else
        emit_diagnostic(
          DiagnosticType::InvalidOperand,
          "Expected a number.",
          span
        )
        nil
      end
    end

    private def compare(op : String, left : Value, right : Value, span : Span) : Value
      if left.is_a?(Int64) || left.is_a?(Float64) || right.is_a?(Int64) || right.is_a?(Float64)
        left_num = to_number(left, span)
        right_num = to_number(right, span)
        return unless left_num && right_num
        case op
        when "<"  then left_num < right_num
        when "<=" then left_num <= right_num
        when ">"  then left_num > right_num
        when ">=" then left_num >= right_num
        else
          emit_invalid_operand(op, span)
          nil
        end
      elsif left.is_a?(String) && right.is_a?(String)
        case op
        when "<"  then left < right
        when "<=" then left <= right
        when ">"  then left > right
        when ">=" then left >= right
        else
          emit_invalid_operand(op, span)
          nil
        end
      else
        emit_invalid_operand(op, span)
        nil
      end
    end

    private def math(op : String, left : Value, right : Value, span : Span) : Value
      left_num = to_number(left, span)
      right_num = to_number(right, span)
      return unless left_num && right_num

      case op
      when "+"
        left_num + right_num
      when "-"
        left_num - right_num
      when "*"
        left_num * right_num
      when "/"
        return if right_num == 0
        left_num / right_num
      when "//"
        return if right_num == 0
        (left_num / right_num).floor
      when "%"
        return if right_num == 0
        left_num % right_num
      when "**"
        left_num ** right_num
      else
        emit_invalid_operand(op, span)
        nil
      end
    end

    private def value_in?(left : Value, right : Value) : Bool
      case right
      when Array(Value)
        right.includes?(left)
      when Hash(String, Value)
        right.has_key?(left.to_s)
      when String
        right.includes?(left.to_s)
      else
        false
      end
    end

    private def emit_invalid_operand(op : String, span : Span) : Nil
      emit_diagnostic(
        DiagnosticType::InvalidOperand,
        "Invalid operand for '#{op}'.",
        span
      )
    end

    private def emit_diagnostic(type : DiagnosticType, message : String, span : Span) : Nil
      @diagnostics << Diagnostic.new(type, Severity::Error, message, span)
    end

    private def to_iterable(value : Value) : Array(Value)?
      return value if value.is_a?(Array(Value))
      if value.is_a?(Hash(String, Value))
        items = Array(Value).new
        value.each_value do |item|
          items << item
        end
        return items
      end
      nil
    end
  end
end
