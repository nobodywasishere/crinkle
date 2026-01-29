module Jinja
  class Renderer
    getter diagnostics : Array(Diagnostic)

    def initialize(@environment : Environment = Environment.new) : Nil
      @diagnostics = Array(Diagnostic).new
      @scopes = Array(Hash(String, Value)).new
      @macros = Hash(String, AST::Macro).new
      @macro_namespaces = Hash(String, Hash(String, AST::Macro)).new
      @caller_stack = Array(String).new
      @block_overrides = Hash(String, Array(AST::Node)).new
    end

    def render(
      template : AST::Template,
      context : Hash(String, Value) = Hash(String, Value).new,
    ) : String
      @diagnostics.clear
      @scopes.clear
      @macros.clear
      @macro_namespaces.clear
      @caller_stack.clear
      @block_overrides.clear
      @scopes << context.dup

      register_macros(template.body)
      extends = find_extends(template.body)
      if extends
        @block_overrides = collect_blocks(template.body)
        parent = load_template_from_expr(extends.template, extends.span)
        return "" unless parent
        register_macros(parent.body)
        return render_nodes(parent.body)
      end

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
      when AST::Block
        if override = @block_overrides[node.name]?
          render_nodes(override)
        else
          render_nodes(node.body)
        end
      when AST::Extends
        ""
      when AST::Include
        render_include(node)
      when AST::Import
        render_import(node)
        ""
      when AST::FromImport
        render_from_import(node)
        ""
      when AST::Macro
        @macros[node.name] = node
        ""
      when AST::CallBlock
        render_call_block(node)
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

    private def render_include(node : AST::Include) : String
      template = load_template_from_expr(node.template, node.span, node.ignore_missing?)
      return "" unless template

      if node.with_context?
        push_scope
        output = render_nodes(template.body)
        pop_scope
        output
      else
        with_isolated_context(Hash(String, Value).new) do
          render_nodes(template.body)
        end
      end
    end

    private def render_import(node : AST::Import) : Nil
      template = load_template_from_expr(node.template, node.span)
      return unless template

      macros = collect_macros(template.body)
      @macro_namespaces[node.alias] = macros
    end

    private def render_from_import(node : AST::FromImport) : Nil
      template = load_template_from_expr(node.template, node.span)
      return unless template

      macros = collect_macros(template.body)
      node.names.each do |import_name|
        name = import_name.name
        alias_name = import_name.alias || name
        if macro_def = macros[name]?
          @macros[alias_name] = macro_def
        else
          emit_diagnostic(
            DiagnosticType::UnknownMacro,
            "Unknown macro '#{name}'.",
            import_name.span
          )
        end
      end
    end

    private def render_call_block(node : AST::CallBlock) : String
      caller_body = render_nodes(node.body)
      args, kwargs = eval_args(node.args, node.kwargs)

      if macro_def = resolve_macro(node.callee)
        return render_macro(macro_def, args, kwargs, caller_body)
      end

      if fn = resolve_function(node.callee)
        result = fn.call(args, kwargs)
        return value_to_s(result) + caller_body
      end

      emit_diagnostic(
        DiagnosticType::UnknownFunction,
        "Unknown function for call block.",
        node.callee.span
      )
      caller_body
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
      callee = expr.callee
      if macro_def = resolve_macro(callee)
        return render_macro(macro_def, args, kwargs, nil)
      end

      if callee.is_a?(AST::Name) && callee.value == "caller" && !@caller_stack.empty?
        return @caller_stack.last
      end

      if fn = resolve_function(callee)
        return fn.call(args, kwargs)
      end

      emit_diagnostic(
        DiagnosticType::UnknownFunction,
        "Unknown function '#{callee_name(callee)}'.",
        callee.span
      )
      nil
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

    private def register_macros(nodes : Array(AST::Node)) : Nil
      collect_macros(nodes).each do |name, macro_def|
        @macros[name] = macro_def
      end
    end

    private def collect_macros(nodes : Array(AST::Node)) : Hash(String, AST::Macro)
      macros = Hash(String, AST::Macro).new
      nodes.each do |node|
        case node
        when AST::Macro
          macros[node.name] = node
        when AST::If
          macros.merge!(collect_macros(node.body))
          macros.merge!(collect_macros(node.else_body))
        when AST::For
          macros.merge!(collect_macros(node.body))
          macros.merge!(collect_macros(node.else_body))
        when AST::SetBlock
          macros.merge!(collect_macros(node.body))
        when AST::Block
          macros.merge!(collect_macros(node.body))
        when AST::CallBlock
          macros.merge!(collect_macros(node.body))
        when AST::CustomTag
          macros.merge!(collect_macros(node.body))
        end
      end
      macros
    end

    private def collect_blocks(nodes : Array(AST::Node)) : Hash(String, Array(AST::Node))
      blocks = Hash(String, Array(AST::Node)).new
      nodes.each do |node|
        case node
        when AST::Block
          blocks[node.name] = node.body
        when AST::If
          blocks.merge!(collect_blocks(node.body))
          blocks.merge!(collect_blocks(node.else_body))
        when AST::For
          blocks.merge!(collect_blocks(node.body))
          blocks.merge!(collect_blocks(node.else_body))
        when AST::SetBlock
          blocks.merge!(collect_blocks(node.body))
        when AST::CallBlock
          blocks.merge!(collect_blocks(node.body))
        when AST::CustomTag
          blocks.merge!(collect_blocks(node.body))
        end
      end
      blocks
    end

    private def find_extends(nodes : Array(AST::Node)) : AST::Extends?
      nodes.each do |node|
        return node if node.is_a?(AST::Extends)
      end
      nil
    end

    private def load_template_from_expr(
      expr : AST::Expr,
      span : Span,
      ignore_missing : Bool = false,
    ) : AST::Template?
      value = eval_expr(expr)
      name = value_to_template_name(value, span)
      return load_template(name, span, ignore_missing) if name
      nil
    end

    private def load_template(
      name : String,
      span : Span,
      ignore_missing : Bool = false,
    ) : AST::Template?
      loader = @environment.template_loader
      unless loader
        return if ignore_missing
        emit_diagnostic(
          DiagnosticType::TemplateNotFound,
          "No template loader configured.",
          span
        )
        return
      end

      source = loader.call(name)
      unless source
        return if ignore_missing
        emit_diagnostic(
          DiagnosticType::TemplateNotFound,
          "Template '#{name}' not found.",
          span
        )
        return
      end

      parse_template(source)
    end

    private def parse_template(source : String) : AST::Template
      lexer = Lexer.new(source)
      tokens = lexer.lex_all
      parser = Parser.new(tokens, @environment)
      template = parser.parse
      @diagnostics.concat(lexer.diagnostics)
      @diagnostics.concat(parser.diagnostics)
      template
    end

    private def render_macro(
      macro_def : AST::Macro,
      args : Array(Value),
      kwargs : Hash(String, Value),
      caller : String?,
    ) : String
      push_scope
      @caller_stack << caller if caller

      bind_macro_params(macro_def, args, kwargs)
      output = render_nodes(macro_def.body)

      @caller_stack.pop if caller
      pop_scope
      output
    end

    private def bind_macro_params(
      macro_def : AST::Macro,
      args : Array(Value),
      kwargs : Hash(String, Value),
    ) : Nil
      macro_def.params.each_with_index do |param, index|
        if index < args.size
          assign(param.name, args[index])
          next
        end

        if kwargs.has_key?(param.name)
          assign(param.name, kwargs[param.name])
          next
        end

        if default_value = param.default_value
          assign(param.name, eval_expr(default_value))
        else
          assign(param.name, nil)
        end
      end
    end

    private def resolve_macro(callee : AST::Expr) : AST::Macro?
      case callee
      when AST::Name
        @macros[callee.value]?
      when AST::GetAttr
        target = callee.target
        return unless target.is_a?(AST::Name)
        namespace = @macro_namespaces[target.value]?
        return namespace[callee.name]? if namespace
        return
      else
        return
      end
    end

    private def resolve_function(callee : AST::Expr) : FunctionProc?
      return unless callee.is_a?(AST::Name)
      @environment.functions[callee.value]?
    end

    private def callee_name(callee : AST::Expr) : String
      case callee
      when AST::Name
        callee.value
      when AST::GetAttr
        target = callee.target
        if target.is_a?(AST::Name)
          "#{target.value}.#{callee.name}"
        else
          callee.name
        end
      else
        "callable"
      end
    end

    private def value_to_template_name(value : Value, span : Span) : String?
      return value if value.is_a?(String)
      emit_diagnostic(
        DiagnosticType::InvalidOperand,
        "Expected template name string.",
        span
      )
      nil
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

    private def with_isolated_context(context : Hash(String, Value), & : -> String) : String
      previous_scopes = @scopes
      @scopes = [context]
      result = yield
      @scopes = previous_scopes
      result
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
