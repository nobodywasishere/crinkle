require "json"

module Jinja
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
        when Group
          json.object do
            json.field "type", "Group"
            json.field "expr" do
              write_expr(json, expr.expr)
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
