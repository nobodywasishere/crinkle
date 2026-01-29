require "./types"

module Jinja
  module LSP
    struct AnalysisResult
      getter diagnostics : Array(Jinja::Diagnostic)
      getter template : AST::Template
      getter symbols : SymbolIndex

      def initialize(
        @diagnostics : Array(Jinja::Diagnostic),
        @template : AST::Template,
        @symbols : SymbolIndex,
      ) : Nil
      end
    end

    class Analyzer
      def analyze(text : String) : AnalysisResult
        lexer = Lexer.new(text)
        tokens = lexer.lex_all
        diagnostics = Array(Jinja::Diagnostic).new
        diagnostics.concat(lexer.diagnostics)
        parser = Parser.new(tokens)
        template = parser.parse
        diagnostics.concat(parser.diagnostics)
        symbols = SymbolIndex.new
        build_index(symbols, template)
        AnalysisResult.new(diagnostics, template, symbols)
      end

      private def build_index(index : SymbolIndex, template : AST::Template) : Nil
        template.body.each do |node|
          visit_node(index, node)
        end
      end

      private def visit_node(index : SymbolIndex, node : AST::Node) : Nil
        case node
        when AST::Output
          visit_expr(index, node.expr)
        when AST::If
          visit_expr(index, node.test)
          node.body.each { |child| visit_node(index, child) }
          node.else_body.each { |child| visit_node(index, child) }
          index.foldable_spans << node.span
        when AST::For
          collect_target_definitions(index, node.target, node.span)
          visit_expr(index, node.iter)
          node.body.each { |child| visit_node(index, child) }
          node.else_body.each { |child| visit_node(index, child) }
          index.foldable_spans << node.span
        when AST::Set
          collect_target_definitions(index, node.target, node.span)
          visit_expr(index, node.value)
        when AST::SetBlock
          collect_target_definitions(index, node.target, node.span)
          node.body.each { |child| visit_node(index, child) }
          index.foldable_spans << node.span
        when AST::Block
          add_definition(index, node.name, LSProtocol::SymbolKind::Class, node.span, "block #{node.name}")
          node.body.each { |child| visit_node(index, child) }
          index.foldable_spans << node.span
        when AST::Macro
          params = node.params.map(&.name).join(", ")
          detail = "macro #{node.name}(#{params})"
          add_definition(index, node.name, LSProtocol::SymbolKind::Function, node.span, detail)
          node.params.each do |param|
            add_definition(index, param.name, LSProtocol::SymbolKind::Variable, param.span, "param #{param.name}")
          end
          node.body.each { |child| visit_node(index, child) }
          index.foldable_spans << node.span
        when AST::CallBlock
          visit_expr(index, node.callee)
          node.args.each { |arg| visit_expr(index, arg) }
          node.kwargs.each { |arg| visit_expr(index, arg.value) }
          node.body.each { |child| visit_node(index, child) }
          index.foldable_spans << node.span
        when AST::Include
          visit_expr(index, node.template)
        when AST::Import
          add_definition(index, node.alias, LSProtocol::SymbolKind::Variable, node.span, "import #{node.alias}")
          visit_expr(index, node.template)
        when AST::FromImport
          node.names.each do |name|
            add_definition(index, name.alias || name.name, LSProtocol::SymbolKind::Variable, name.span, "import #{name.name}")
          end
          visit_expr(index, node.template)
        when AST::CustomTag
          node.args.each { |arg| visit_expr(index, arg) }
          node.kwargs.each { |arg| visit_expr(index, arg.value) }
          node.body.each { |child| visit_node(index, child) }
          index.foldable_spans << node.span
        when AST::Raw
          index.foldable_spans << node.span
        end
      end

      private def collect_target_definitions(index : SymbolIndex, target : AST::Target, span : Jinja::Span) : Nil
        case target
        when AST::Name
          add_definition(index, target.value, LSProtocol::SymbolKind::Variable, span, "set #{target.value}")
        when AST::TupleLiteral
          target.items.each do |item|
            next unless item.is_a?(AST::Name)
            add_definition(index, item.value, LSProtocol::SymbolKind::Variable, item.span, "set #{item.value}")
          end
        when AST::GetAttr
          visit_expr(index, target.target)
        when AST::GetItem
          visit_expr(index, target.target)
          visit_expr(index, target.index)
        end
      end

      private def add_definition(
        index : SymbolIndex,
        name : String,
        kind : LSProtocol::SymbolKind,
        span : Jinja::Span,
        detail : String,
      ) : Nil
        index.definitions[name] << SymbolDefinition.new(name, kind, span, detail)
      end

      private def visit_expr(index : SymbolIndex, expr : AST::Expr) : Nil
        case expr
        when AST::Name
          index.references << SymbolReference.new(expr.value, expr.span)
        when AST::Binary
          visit_expr(index, expr.left)
          visit_expr(index, expr.right)
        when AST::Unary
          visit_expr(index, expr.expr)
        when AST::Group
          visit_expr(index, expr.expr)
        when AST::Call
          visit_expr(index, expr.callee)
          expr.args.each { |arg| visit_expr(index, arg) }
          expr.kwargs.each { |arg| visit_expr(index, arg.value) }
        when AST::Filter
          visit_expr(index, expr.expr)
          expr.args.each { |arg| visit_expr(index, arg) }
          expr.kwargs.each { |arg| visit_expr(index, arg.value) }
        when AST::Test
          visit_expr(index, expr.expr)
          expr.args.each { |arg| visit_expr(index, arg) }
          expr.kwargs.each { |arg| visit_expr(index, arg.value) }
        when AST::GetAttr
          visit_expr(index, expr.target)
        when AST::GetItem
          visit_expr(index, expr.target)
          visit_expr(index, expr.index)
        when AST::ListLiteral
          expr.items.each { |item| visit_expr(index, item) }
        when AST::DictLiteral
          expr.pairs.each do |pair|
            visit_expr(index, pair.key)
            visit_expr(index, pair.value)
          end
        when AST::TupleLiteral
          expr.items.each { |item| visit_expr(index, item) }
        end
      end
    end
  end
end
