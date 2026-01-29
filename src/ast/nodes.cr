module Jinja
  module AST
    alias Node = Text | Output | If | For
    alias Expr = Name | Literal | Binary | Group

    class Template
      getter body : Array(Node)
      getter span : Span

      def initialize(@body : Array(Node), @span : Span) : Nil
      end
    end

    class Text
      getter value : String
      getter span : Span

      def initialize(@value : String, @span : Span) : Nil
      end
    end

    class Output
      getter expr : Expr
      getter span : Span

      def initialize(@expr : Expr, @span : Span) : Nil
      end
    end

    class If
      getter test : Expr
      getter body : Array(Node)
      getter else_body : Array(Node)
      getter span : Span

      def initialize(@test : Expr, @body : Array(Node), @else_body : Array(Node), @span : Span) : Nil
      end
    end

    class For
      getter target : Name
      getter iter : Expr
      getter body : Array(Node)
      getter else_body : Array(Node)
      getter span : Span

      def initialize(@target : Name, @iter : Expr, @body : Array(Node), @else_body : Array(Node), @span : Span) : Nil
      end
    end

    class Name
      getter value : String
      getter span : Span

      def initialize(@value : String, @span : Span) : Nil
      end
    end

    class Literal
      getter value : (String | Int64 | Float64 | Bool)?
      getter span : Span

      def initialize(@value : (String | Int64 | Float64 | Bool)?, @span : Span) : Nil
      end
    end

    class Binary
      getter op : String
      getter left : Expr
      getter right : Expr
      getter span : Span

      def initialize(@op : String, @left : Expr, @right : Expr, @span : Span) : Nil
      end
    end

    class Group
      getter expr : Expr
      getter span : Span

      def initialize(@expr : Expr, @span : Span) : Nil
      end
    end
  end
end
