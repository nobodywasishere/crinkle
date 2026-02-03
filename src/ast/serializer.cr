module Crinkle
  module AST
    module Serializer
      def self.to_pretty_json(template : Template) : String
        JSON.build(indent: 2) do |json|
          write_template(json, template)
        end
      end

      private def self.write_template(json : JSON::Builder, template : Template) : Nil
        json.object do
          json.field "type", "Template"
          json.field "body" do
            json.array do
              template.body.each do |node|
                write_node(json, node)
              end
            end
          end
        end
      end

      private def self.write_node(json : JSON::Builder, node : Node) : Nil
        case node
        when Text
          json.object do
            json.field "type", "Text"
            json.field "value", node.value
          end
        when Comment
          json.object do
            json.field "type", "Comment"
            json.field "text", node.text
          end
        when Output
          json.object do
            json.field "type", "Output"
            json.field "expr" do
              write_expr(json, node.expr)
            end
          end
        when If
          json.object do
            json.field "type", "If"
            json.field "test" do
              write_expr(json, node.test)
            end
            json.field "body" do
              json.array do
                node.body.each do |child|
                  write_node(json, child)
                end
              end
            end
            json.field "else" do
              json.array do
                node.else_body.each do |child|
                  write_node(json, child)
                end
              end
            end
          end
        when For
          json.object do
            json.field "type", "For"
            json.field "target" do
              write_expr(json, node.target)
            end
            json.field "iter" do
              write_expr(json, node.iter)
            end
            json.field "body" do
              json.array do
                node.body.each do |child|
                  write_node(json, child)
                end
              end
            end
            json.field "else" do
              json.array do
                node.else_body.each do |child|
                  write_node(json, child)
                end
              end
            end
          end
        when Set
          json.object do
            json.field "type", "Set"
            json.field "target" do
              write_expr(json, node.target)
            end
            json.field "value" do
              write_expr(json, node.value)
            end
          end
        when SetBlock
          json.object do
            json.field "type", "SetBlock"
            json.field "target" do
              write_expr(json, node.target)
            end
            json.field "body" do
              json.array do
                node.body.each do |child|
                  write_node(json, child)
                end
              end
            end
          end
        when Block
          json.object do
            json.field "type", "Block"
            json.field "name", node.name
            json.field "body" do
              json.array do
                node.body.each do |child|
                  write_node(json, child)
                end
              end
            end
          end
        when Extends
          json.object do
            json.field "type", "Extends"
            json.field "template" do
              write_expr(json, node.template)
            end
          end
        when Include
          json.object do
            json.field "type", "Include"
            json.field "template" do
              write_expr(json, node.template)
            end
            json.field "with_context", node.with_context?
            json.field "ignore_missing", node.ignore_missing?
          end
        when Import
          json.object do
            json.field "type", "Import"
            json.field "template" do
              write_expr(json, node.template)
            end
            json.field "alias", node.alias
          end
        when FromImport
          json.object do
            json.field "type", "FromImport"
            json.field "template" do
              write_expr(json, node.template)
            end
            json.field "names" do
              json.array do
                node.names.each do |name|
                  json.object do
                    json.field "name", name.name
                    json.field "alias", name.alias
                  end
                end
              end
            end
            json.field "with_context", node.with_context?
          end
        when Macro
          json.object do
            json.field "type", "Macro"
            json.field "name", node.name
            json.field "params" do
              json.array do
                node.params.each do |param|
                  json.object do
                    json.field "name", param.name
                    json.field "default" do
                      if default_value = param.default_value
                        write_expr(json, default_value)
                      else
                        json.null
                      end
                    end
                  end
                end
              end
            end
            json.field "body" do
              json.array do
                node.body.each do |child|
                  write_node(json, child)
                end
              end
            end
          end
        when CallBlock
          json.object do
            json.field "type", "CallBlock"
            if call_args = node.call_args
              json.field "call_args" do
                write_expr_array(json, call_args)
              end
            end
            if call_kwargs = node.call_kwargs
              json.field "call_kwargs" do
                write_kwargs(json, call_kwargs)
              end
            end
            json.field "callee" do
              write_expr(json, node.callee)
            end
            json.field "args" do
              write_expr_array(json, node.args)
            end
            json.field "kwargs" do
              write_kwargs(json, node.kwargs)
            end
            json.field "body" do
              json.array do
                node.body.each do |child|
                  write_node(json, child)
                end
              end
            end
          end
        when Raw
          json.object do
            json.field "type", "Raw"
            json.field "text", node.text
          end
        when CustomTag
          json.object do
            json.field "type", "CustomTag"
            json.field "name", node.name
            json.field "args" do
              write_expr_array(json, node.args)
            end
            json.field "kwargs" do
              write_kwargs(json, node.kwargs)
            end
            json.field "body" do
              json.array do
                node.body.each do |child|
                  write_node(json, child)
                end
              end
            end
          end
        end
      end

      private def self.write_expr(json : JSON::Builder, expr : Expr) : Nil
        case expr
        when Name
          json.object do
            json.field "type", "Name"
            json.field "value", expr.value
          end
        when Literal
          json.object do
            json.field "type", "Literal"
            json.field "value", literal_value(expr.value)
          end
        when Binary
          json.object do
            json.field "type", "Binary"
            json.field "op", expr.op
            json.field "left" do
              write_expr(json, expr.left)
            end
            json.field "right" do
              write_expr(json, expr.right)
            end
          end
        when Unary
          json.object do
            json.field "type", "Unary"
            json.field "op", expr.op
            json.field "expr" do
              write_expr(json, expr.expr)
            end
          end
        when Group
          json.object do
            json.field "type", "Group"
            json.field "expr" do
              write_expr(json, expr.expr)
            end
          end
        when Call
          json.object do
            json.field "type", "Call"
            json.field "callee" do
              write_expr(json, expr.callee)
            end
            json.field "args" do
              write_expr_array(json, expr.args)
            end
            json.field "kwargs" do
              write_kwargs(json, expr.kwargs)
            end
          end
        when Filter
          json.object do
            json.field "type", "Filter"
            json.field "expr" do
              write_expr(json, expr.expr)
            end
            json.field "name", expr.name
            json.field "args" do
              write_expr_array(json, expr.args)
            end
            json.field "kwargs" do
              write_kwargs(json, expr.kwargs)
            end
          end
        when Test
          json.object do
            json.field "type", "Test"
            json.field "expr" do
              write_expr(json, expr.expr)
            end
            json.field "name", expr.name
            json.field "negated", expr.negated?
            json.field "args" do
              write_expr_array(json, expr.args)
            end
            json.field "kwargs" do
              write_kwargs(json, expr.kwargs)
            end
          end
        when GetAttr
          json.object do
            json.field "type", "GetAttr"
            json.field "target" do
              write_expr(json, expr.target)
            end
            json.field "name", expr.name
          end
        when GetItem
          json.object do
            json.field "type", "GetItem"
            json.field "target" do
              write_expr(json, expr.target)
            end
            json.field "index" do
              write_expr(json, expr.index)
            end
          end
        when ListLiteral
          json.object do
            json.field "type", "ListLiteral"
            json.field "items" do
              write_expr_array(json, expr.items)
            end
          end
        when DictLiteral
          json.object do
            json.field "type", "DictLiteral"
            json.field "pairs" do
              json.array do
                expr.pairs.each do |pair|
                  json.object do
                    json.field "key" do
                      write_expr(json, pair.key)
                    end
                    json.field "value" do
                      write_expr(json, pair.value)
                    end
                  end
                end
              end
            end
          end
        when TupleLiteral
          json.object do
            json.field "type", "TupleLiteral"
            json.field "items" do
              write_expr_array(json, expr.items)
            end
          end
        end
      end

      private def self.write_expr_array(json : JSON::Builder, items : Array(Expr)) : Nil
        json.array do
          items.each do |item|
            write_expr(json, item)
          end
        end
      end

      private def self.write_kwargs(json : JSON::Builder, kwargs : Array(KeywordArg)) : Nil
        json.array do
          kwargs.each do |keyword|
            json.object do
              json.field "name", keyword.name
              json.field "value" do
                write_expr(json, keyword.value)
              end
            end
          end
        end
      end

      private def self.literal_value(value : (String | Int64 | Float64 | Bool)?) : (String | Int64 | Float64 | Bool)?
        case value
        when String
          value
        when Int64
          value
        when Float64
          value
        when Bool
          value
        when Nil
          nil
        end
      end
    end
  end
end
