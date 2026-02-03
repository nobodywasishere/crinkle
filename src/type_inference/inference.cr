module Crinkle
  module TypeInference
    struct TypeRef
      getter name : String
      getter args : Array(TypeRef)

      def initialize(@name : String, @args : Array(TypeRef) = Array(TypeRef).new) : Nil
      end

      def to_s : String
        return name if args.empty?
        "#{name}[#{args.map(&.to_s).join(", ")}]"
      end
    end

    module TypeRules
      def self.compatible?(expected : TypeRef, actual : TypeRef) : Bool
        return true if expected.name == "Any" || actual.name == "Any"
        return true if expected.name == "Value" || actual.name == "Value"
        return true if expected.name == actual.name

        if expected.name == "Number"
          return %w[Int64 Float64 Number].includes?(actual.name)
        end

        false
      end
    end

    class Environment
      @scopes : Array(Hash(String, TypeRef))

      def initialize : Nil
        @scopes = [Hash(String, TypeRef).new]
      end

      def push : Nil
        @scopes << Hash(String, TypeRef).new
      end

      def pop : Nil
        @scopes.pop
      end

      def set(name : String, type : TypeRef) : Nil
        @scopes.last[name] = type
      end

      def get(name : String) : TypeRef?
        @scopes.reverse_each do |scope|
          if type = scope[name]?
            return type
          end
        end
        nil
      end
    end

    class Inferer
      def initialize(@schema : Schema::Registry) : Nil
      end

      def infer_variable_type(template : AST::Template, name : String, span : Span) : TypeRef?
        if expr = find_set_definition(template, name, span)
          return infer_expr_type(expr)
        end

        if param_default = find_macro_param_default(template, name, span)
          return infer_expr_type(param_default)
        end

        nil
      rescue
        nil
      end

      def infer_expr_type(expr : AST::Expr, env : Environment? = nil) : TypeRef?
        case expr
        when AST::Literal
          infer_literal_type(expr.value)
        when AST::ListLiteral
          TypeRef.new("Array")
        when AST::DictLiteral
          TypeRef.new("Hash")
        when AST::TupleLiteral
          TypeRef.new("Tuple")
        when AST::Group
          infer_expr_type(expr.expr, env)
        when AST::Unary
          infer_expr_type(expr.expr, env)
        when AST::Binary
          left = infer_expr_type(expr.left, env)
          right = infer_expr_type(expr.right, env)
          infer_binary_type(expr.op, left, right)
        when AST::Filter
          @schema.filters[expr.name]?.try { |filter| parse_type(filter.returns) }
        when AST::Test
          TypeRef.new("Bool")
        when AST::Call
          if callee_name = extract_callee_name(expr.callee)
            if func = @schema.functions[callee_name]?
              return parse_type(func.returns)
            end
          end
          # Method calls or unknown functions default to Any for now.
          TypeRef.new("Any")
        when AST::Name
          env.try(&.get(expr.value)) || TypeRef.new("Any")
        when AST::GetAttr, AST::GetItem
          TypeRef.new("Any")
        end
      end

      def parse_type(type_str : String) : TypeRef
        return TypeRef.new("Any") if type_str.empty?
        TypeRef.new(type_str)
      end

      def numeric?(type : TypeRef) : Bool
        %w[Int64 Float64 Number].includes?(type.name)
      end

      private def infer_literal_type(value : (String | Int64 | Float64 | Bool)?) : TypeRef?
        case value
        when String
          TypeRef.new("String")
        when Int64
          TypeRef.new("Int64")
        when Float64
          TypeRef.new("Float64")
        when Bool
          TypeRef.new("Bool")
        when Nil
          TypeRef.new("Nil")
        end
      end

      private def infer_binary_type(op : String, left : TypeRef?, right : TypeRef?) : TypeRef?
        return unless left && right

        case op
        when "and", "or", "==", "!=", "<", ">", "<=", ">=", "in", "not in", "is", "is not"
          TypeRef.new("Bool")
        when "+", "-", "*", "%", "/", "//", "**"
          infer_numeric_type(op, left, right)
        when "~"
          if left.name == "String" || right.name == "String"
            TypeRef.new("String")
          end
        end
      end

      private def infer_numeric_type(op : String, left : TypeRef, right : TypeRef) : TypeRef?
        return unless numeric?(left) && numeric?(right)

        if op == "/"
          return TypeRef.new("Float64") if left.name == "Float64" || right.name == "Float64"
          return TypeRef.new("Number") if left.name == "Number" || right.name == "Number"
          return TypeRef.new("Float64")
        end

        return TypeRef.new("Float64") if left.name == "Float64" || right.name == "Float64"
        return TypeRef.new("Number") if left.name == "Number" || right.name == "Number"
        TypeRef.new("Int64")
      end

      private def extract_callee_name(expr : AST::Expr) : String?
        case expr
        when AST::Name
          expr.value
        when AST::GetAttr
          expr.name
        end
      end

      private def find_set_definition(template : AST::Template, name : String, span : Span) : AST::Expr?
        found : AST::Expr? = nil
        AST::Walker.walk_nodes(template.body) do |node|
          next if found
          next unless node.is_a?(AST::Set)
          next unless spans_equal?(node.span, span)

          case target = node.target
          when AST::Name
            found = node.value if target.value == name
          when AST::TupleLiteral
            if node.value.is_a?(AST::TupleLiteral)
              values = node.value.as(AST::TupleLiteral).items
              target.items.each_with_index do |item, idx|
                next unless item.is_a?(AST::Name)
                next unless item.value == name
                found = values[idx]? if idx < values.size
              end
            end
          end
        end
        found
      end

      private def find_macro_param_default(template : AST::Template, name : String, span : Span) : AST::Expr?
        found : AST::Expr? = nil
        AST::Walker.walk_nodes(template.body) do |node|
          next if found
          next unless node.is_a?(AST::Macro)
          node.params.each do |param|
            next unless param.name == name
            next unless spans_equal?(param.span, span)
            found = param.default_value
          end
        end
        found
      end

      private def spans_equal?(left : Span, right : Span) : Bool
        left.start_pos.line == right.start_pos.line &&
          left.start_pos.column == right.start_pos.column &&
          left.end_pos.line == right.end_pos.line &&
          left.end_pos.column == right.end_pos.column
      end
    end
  end
end
