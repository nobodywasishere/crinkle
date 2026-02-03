module Crinkle
  module AST
    # Generic AST visitor with optional cancellation support.
    # Defaults to pre-order traversal of nodes and expressions.
    abstract class Visitor
      @cancelled : Proc(Bool)?

      def initialize(@cancelled : Proc(Bool)? = nil) : Nil
      end

      def cancelled? : Bool
        @cancelled.try(&.call) || false
      end

      def visit(node : Node) : Nil
        return if cancelled?
        enter_node(node)
        visit_node_children(node)
        exit_node(node)
      end

      def visit_expr(expr : Expr) : Nil
        return if cancelled?
        enter_expr(expr)
        visit_expr_children(expr)
        exit_expr(expr)
      end

      def visit_nodes(nodes : Array(Node)) : Nil
        nodes.each do |node|
          break if cancelled?
          visit(node)
        end
      end

      def visit_exprs(exprs : Array(Expr)) : Nil
        exprs.each do |expr|
          break if cancelled?
          visit_expr(expr)
        end
      end

      def visit_target(target : Target) : Nil
        visit_expr(target.as(Expr))
      end

      protected def enter_node(node : Node) : Nil
      end

      protected def exit_node(node : Node) : Nil
      end

      protected def enter_expr(expr : Expr) : Nil
      end

      protected def exit_expr(expr : Expr) : Nil
      end

      protected def visit_node_children(node : Node) : Nil
        case node
        when Output
          visit_expr(node.expr)
        when If
          visit_expr(node.test)
          visit_nodes(node.body)
          visit_nodes(node.else_body)
        when For
          visit_target(node.target)
          visit_expr(node.iter)
          visit_nodes(node.body)
          visit_nodes(node.else_body)
        when Set
          visit_target(node.target)
          visit_expr(node.value)
        when SetBlock
          visit_target(node.target)
          visit_nodes(node.body)
        when Block
          visit_nodes(node.body)
        when Extends
          visit_expr(node.template)
        when Include
          visit_expr(node.template)
        when Import
          visit_expr(node.template)
        when FromImport
          visit_expr(node.template)
        when Macro
          node.params.each do |param|
            if default = param.default_value
              visit_expr(default)
            end
          end
          visit_nodes(node.body)
        when CallBlock
          visit_expr(node.callee)
          visit_exprs(node.args)
          node.kwargs.each { |kwarg| visit_expr(kwarg.value) }
          if call_args = node.call_args
            visit_exprs(call_args)
          end
          if call_kwargs = node.call_kwargs
            call_kwargs.each { |kwarg| visit_expr(kwarg.value) }
          end
          visit_nodes(node.body)
        when CustomTag
          visit_exprs(node.args)
          node.kwargs.each { |kwarg| visit_expr(kwarg.value) }
          visit_nodes(node.body)
        end
      end

      protected def visit_expr_children(expr : Expr) : Nil
        case expr
        when Binary
          visit_expr(expr.left)
          visit_expr(expr.right)
        when Unary
          visit_expr(expr.expr)
        when Group
          visit_expr(expr.expr)
        when Call
          visit_expr(expr.callee)
          visit_exprs(expr.args)
          expr.kwargs.each { |kwarg| visit_expr(kwarg.value) }
        when Filter
          visit_expr(expr.expr)
          visit_exprs(expr.args)
          expr.kwargs.each { |kwarg| visit_expr(kwarg.value) }
        when Test
          visit_expr(expr.expr)
          visit_exprs(expr.args)
          expr.kwargs.each { |kwarg| visit_expr(kwarg.value) }
        when GetAttr
          visit_expr(expr.target)
        when GetItem
          visit_expr(expr.target)
          visit_expr(expr.index)
        when ListLiteral
          visit_exprs(expr.items)
        when TupleLiteral
          visit_exprs(expr.items)
        when DictLiteral
          expr.pairs.each do |pair|
            visit_expr(pair.key)
            visit_expr(pair.value)
          end
        end
      end
    end

    # Convenience walkers built on the visitor.
    module Walker
      class NodeWalker < Visitor
        @block : Proc(AST::Node, Nil)

        def initialize(@block : Proc(AST::Node, Nil), cancelled : Proc(Bool)? = nil) : Nil
          super(cancelled)
        end

        protected def enter_node(node : AST::Node) : Nil
          @block.call(node)
        end

        protected def visit_node_children(node : AST::Node) : Nil
          case node
          when AST::If
            visit_nodes(node.body)
            visit_nodes(node.else_body)
          when AST::For
            visit_nodes(node.body)
            visit_nodes(node.else_body)
          when AST::SetBlock
            visit_nodes(node.body)
          when AST::Block
            visit_nodes(node.body)
          when AST::Macro
            visit_nodes(node.body)
          when AST::CallBlock
            visit_nodes(node.body)
          when AST::CustomTag
            visit_nodes(node.body)
          end
        end

        def visit_expr(expr : AST::Expr) : Nil
          # Skip expression traversal for node-only walks.
        end
      end

      class ExprWalker < Visitor
        @block : Proc(AST::Expr, Nil)

        def initialize(@block : Proc(AST::Expr, Nil), cancelled : Proc(Bool)? = nil) : Nil
          super(cancelled)
        end

        protected def enter_expr(expr : AST::Expr) : Nil
          @block.call(expr)
        end

        def visit(node : AST::Node) : Nil
          # Skip node traversal for expression-only walks.
        end
      end

      def self.walk_nodes(nodes : Array(AST::Node), cancelled : Proc(Bool)? = nil, &block : AST::Node ->) : Nil
        NodeWalker.new(block, cancelled).visit_nodes(nodes)
      end

      def self.walk_expr(expr : AST::Expr, cancelled : Proc(Bool)? = nil, &block : AST::Expr ->) : Nil
        ExprWalker.new(block, cancelled).visit_expr(expr)
      end
    end
  end
end
