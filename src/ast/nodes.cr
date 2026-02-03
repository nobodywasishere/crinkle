module Crinkle
  module AST
    alias Node = Text |
                 Comment |
                 Output |
                 If |
                 For |
                 Set |
                 SetBlock |
                 Block |
                 Extends |
                 Include |
                 Import |
                 FromImport |
                 Macro |
                 CallBlock |
                 Raw |
                 CustomTag
    alias Expr = Name |
                 Literal |
                 Unary |
                 Binary |
                 Group |
                 Call |
                 Filter |
                 Test |
                 GetAttr |
                 GetItem |
                 ListLiteral |
                 DictLiteral |
                 TupleLiteral

    alias Target = Name |
                   GetAttr |
                   GetItem |
                   TupleLiteral

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

    class Comment
      getter text : String
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(@text : String, @span : Span, @trim_left : Bool = false, @trim_right : Bool = false) : Nil
      end
    end

    class Output
      getter expr : Expr
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(@expr : Expr, @span : Span, @trim_left : Bool = false, @trim_right : Bool = false) : Nil
      end
    end

    class If
      getter test : Expr
      getter body : Array(Node)
      getter else_body : Array(Node)
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool
      getter? else_trim_left : Bool
      getter? else_trim_right : Bool
      getter? end_trim_left : Bool
      getter? end_trim_right : Bool
      getter? is_elif : Bool

      def initialize(
        @test : Expr,
        @body : Array(Node),
        @else_body : Array(Node),
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
        @else_trim_left : Bool = false,
        @else_trim_right : Bool = false,
        @end_trim_left : Bool = false,
        @end_trim_right : Bool = false,
        @is_elif : Bool = false,
      ) : Nil
      end
    end

    class For
      getter target : Target
      getter iter : Expr
      getter body : Array(Node)
      getter else_body : Array(Node)
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool
      getter? else_trim_left : Bool
      getter? else_trim_right : Bool
      getter? end_trim_left : Bool
      getter? end_trim_right : Bool

      def initialize(
        @target : Target,
        @iter : Expr,
        @body : Array(Node),
        @else_body : Array(Node),
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
        @else_trim_left : Bool = false,
        @else_trim_right : Bool = false,
        @end_trim_left : Bool = false,
        @end_trim_right : Bool = false,
      ) : Nil
      end
    end

    class Set
      getter target : Target
      getter value : Expr
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(@target : Target, @value : Expr, @span : Span, @trim_left : Bool = false, @trim_right : Bool = false) : Nil
      end
    end

    class SetBlock
      getter target : Target
      getter body : Array(Node)
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool
      getter? end_trim_left : Bool
      getter? end_trim_right : Bool

      def initialize(
        @target : Target,
        @body : Array(Node),
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
        @end_trim_left : Bool = false,
        @end_trim_right : Bool = false,
      ) : Nil
      end
    end

    class Block
      getter name : String
      getter body : Array(Node)
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool
      getter? end_trim_left : Bool
      getter? end_trim_right : Bool

      def initialize(
        @name : String,
        @body : Array(Node),
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
        @end_trim_left : Bool = false,
        @end_trim_right : Bool = false,
      ) : Nil
      end
    end

    class Extends
      getter template : Expr
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(@template : Expr, @span : Span, @trim_left : Bool = false, @trim_right : Bool = false) : Nil
      end
    end

    class Include
      getter template : Expr
      getter? with_context : Bool
      getter? ignore_missing : Bool
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(
        @template : Expr,
        @with_context : Bool,
        @ignore_missing : Bool,
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
      ) : Nil
      end
    end

    class Import
      getter template : Expr
      getter alias : String?
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(
        @template : Expr,
        @alias : String?,
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
      ) : Nil
      end
    end

    class ImportName
      getter name : String
      getter alias : String?
      getter span : Span

      def initialize(@name : String, @alias : String?, @span : Span) : Nil
      end
    end

    class FromImport
      getter template : Expr
      getter names : Array(ImportName)
      getter? with_context : Bool
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(
        @template : Expr,
        @names : Array(ImportName),
        @with_context : Bool,
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
      ) : Nil
      end
    end

    class MacroParam
      getter name : String
      getter default_value : Expr?
      getter span : Span

      def initialize(@name : String, @default_value : Expr?, @span : Span) : Nil
      end
    end

    class Macro
      getter name : String
      getter params : Array(MacroParam)
      getter body : Array(Node)
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool
      getter? end_trim_left : Bool
      getter? end_trim_right : Bool

      def initialize(
        @name : String,
        @params : Array(MacroParam),
        @body : Array(Node),
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
        @end_trim_left : Bool = false,
        @end_trim_right : Bool = false,
      ) : Nil
      end
    end

    class CallBlock
      getter callee : Expr
      getter args : Array(Expr)
      getter kwargs : Array(KeywordArg)
      getter call_args : Array(Expr)?
      getter call_kwargs : Array(KeywordArg)?
      getter body : Array(Node)
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool
      getter? end_trim_left : Bool
      getter? end_trim_right : Bool

      def initialize(
        @callee : Expr,
        @args : Array(Expr),
        @kwargs : Array(KeywordArg),
        @body : Array(Node),
        @span : Span,
        @call_args : Array(Expr)? = nil,
        @call_kwargs : Array(KeywordArg)? = nil,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
        @end_trim_left : Bool = false,
        @end_trim_right : Bool = false,
      ) : Nil
      end
    end

    class Raw
      getter text : String
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool
      getter? end_trim_left : Bool
      getter? end_trim_right : Bool

      def initialize(
        @text : String,
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
        @end_trim_left : Bool = false,
        @end_trim_right : Bool = false,
      ) : Nil
      end
    end

    class CustomTag
      getter name : String
      getter args : Array(Expr)
      getter kwargs : Array(KeywordArg)
      getter body : Array(Node)
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool
      getter? end_trim_left : Bool
      getter? end_trim_right : Bool

      def initialize(
        @name : String,
        @args : Array(Expr),
        @kwargs : Array(KeywordArg),
        @body : Array(Node),
        @span : Span,
        @trim_left : Bool = false,
        @trim_right : Bool = false,
        @end_trim_left : Bool = false,
        @end_trim_right : Bool = false,
      ) : Nil
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

    class Unary
      getter op : String
      getter expr : Expr
      getter span : Span

      def initialize(@op : String, @expr : Expr, @span : Span) : Nil
      end
    end

    class Group
      getter expr : Expr
      getter span : Span

      def initialize(@expr : Expr, @span : Span) : Nil
      end
    end

    class Call
      getter callee : Expr
      getter args : Array(Expr)
      getter kwargs : Array(KeywordArg)
      getter span : Span

      def initialize(@callee : Expr, @args : Array(Expr), @kwargs : Array(KeywordArg), @span : Span) : Nil
      end
    end

    class KeywordArg
      getter name : String
      getter value : Expr
      getter span : Span

      def initialize(@name : String, @value : Expr, @span : Span) : Nil
      end
    end

    class Filter
      getter expr : Expr
      getter name : String
      getter args : Array(Expr)
      getter kwargs : Array(KeywordArg)
      getter span : Span

      def initialize(@expr : Expr, @name : String, @args : Array(Expr), @kwargs : Array(KeywordArg), @span : Span) : Nil
      end
    end

    class Test
      getter expr : Expr
      getter name : String
      getter args : Array(Expr)
      getter kwargs : Array(KeywordArg)
      getter? negated : Bool
      getter span : Span

      def initialize(@expr : Expr, @name : String, @args : Array(Expr), @kwargs : Array(KeywordArg), @negated : Bool, @span : Span) : Nil
      end
    end

    class GetAttr
      getter target : Expr
      getter name : String
      getter span : Span

      def initialize(@target : Expr, @name : String, @span : Span) : Nil
      end
    end

    class GetItem
      getter target : Expr
      getter index : Expr
      getter span : Span

      def initialize(@target : Expr, @index : Expr, @span : Span) : Nil
      end
    end

    class ListLiteral
      getter items : Array(Expr)
      getter span : Span

      def initialize(@items : Array(Expr), @span : Span) : Nil
      end
    end

    class DictEntry
      getter key : Expr
      getter value : Expr
      getter span : Span

      def initialize(@key : Expr, @value : Expr, @span : Span) : Nil
      end
    end

    class DictLiteral
      getter pairs : Array(DictEntry)
      getter span : Span

      def initialize(@pairs : Array(DictEntry), @span : Span) : Nil
      end
    end

    class TupleLiteral
      getter items : Array(Expr)
      getter span : Span

      def initialize(@items : Array(Expr), @span : Span) : Nil
      end
    end
  end
end
