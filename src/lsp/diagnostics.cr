# Diagnostic conversion utilities for LSP.
# Converts Crinkle linter issues to LSP diagnostic format.

module Crinkle::LSP
  # Converts linter issues to LSP diagnostics.
  module Diagnostics
    # Convert a single linter issue to an LSP diagnostic.
    def self.convert(issue : Linter::Issue) : Diagnostic
      Diagnostic.new(
        range: span_to_range(issue.span),
        message: issue.message,
        severity: map_severity(issue.severity),
        code: issue.id,
        source: "crinkle"
      )
    end

    # Convert a collection of linter issues to LSP diagnostics.
    def self.convert_all(issues : Array(Linter::Issue)) : Array(Diagnostic)
      issues.map { |issue| convert(issue) }
    end

    # Convert a Crinkle span to an LSP range.
    # Crinkle uses 1-based lines/columns, LSP uses 0-based.
    private def self.span_to_range(span : Span) : Range
      start_pos = Position.new(
        line: span.start_pos.line - 1,
        character: span.start_pos.column - 1
      )
      end_pos = Position.new(
        line: span.end_pos.line - 1,
        character: span.end_pos.column - 1
      )
      Range.new(start: start_pos, end_pos: end_pos)
    end

    # Map Crinkle severity to LSP severity.
    private def self.map_severity(severity : Severity) : DiagnosticSeverity
      case severity
      when .error?   then DiagnosticSeverity::Error
      when .warning? then DiagnosticSeverity::Warning
      else                DiagnosticSeverity::Information
      end
    end
  end

  # Analyzer runs the full analysis pipeline: lex → parse → lint.
  class Analyzer
    getter linter : Linter::Runner
    @inference : InferenceEngine?

    def initialize(schema : Schema::Registry? = nil, @inference : InferenceEngine? = nil) : Nil
      ruleset = Linter.default_ruleset(schema)
      @linter = Linter::Runner.new(ruleset, schema)
    end

    # Analyze a template and return linter issues.
    def analyze(text : String, uri : String? = nil) : Array(Linter::Issue)
      # Lex the template
      lexer = Lexer.new(text)
      tokens = lexer.lex_all
      lex_diagnostics = lexer.diagnostics

      # Parse the template
      parser = Parser.new(tokens)
      ast = parser.parse
      parse_diagnostics = parser.diagnostics

      # Combine lexer and parser diagnostics
      all_diagnostics = lex_diagnostics + parse_diagnostics

      # Run linter (includes mapped diagnostics + lint rules)
      issues = @linter.lint(ast, text, all_diagnostics)

      # Run typo detection if inference engine is available
      if inference = @inference
        if uri
          typo_issues = detect_typos(ast, uri, inference)
          issues.concat(typo_issues)
        end
      end

      issues
    end

    # Analyze a template and return LSP diagnostics.
    def analyze_to_lsp(text : String, uri : String? = nil) : Array(Diagnostic)
      issues = analyze(text, uri)
      Diagnostics.convert_all(issues)
    end

    # Detect potential typos in property access using inference data
    private def detect_typos(ast : AST::Template, uri : String, inference : InferenceEngine) : Array(Linter::Issue)
      issues = Array(Linter::Issue).new
      collect_getattr_nodes(ast.body) do |node|
        if var_name = extract_variable_name(node.target)
          known_props = inference.properties_for(uri, var_name)
          # Only check if there are known properties and this one isn't in the list
          if !known_props.empty? && !known_props.includes?(node.name)
            similar = inference.similar_properties(uri, var_name, node.name, threshold: 2)
            if !similar.empty?
              suggestion = similar.first
              issues << Linter::Issue.new(
                id: "Inference/PossibleTypo",
                severity: Severity::Warning,
                message: "Unknown property '#{node.name}' on '#{var_name}'. Did you mean '#{suggestion}'?",
                span: node.span
              )
            end
          end
        end
      end
      issues
    end

    # Recursively collect all GetAttr nodes from AST
    private def collect_getattr_nodes(nodes : Array(AST::Node), &block : AST::GetAttr ->) : Nil
      nodes.each { |node| collect_from_node(node, &block) }
    end

    private def collect_from_node(node : AST::Node, &block : AST::GetAttr ->) : Nil
      case node
      when AST::Output
        collect_from_expr(node.expr, &block)
      when AST::If
        collect_from_expr(node.test, &block)
        collect_getattr_nodes(node.body, &block)
        collect_getattr_nodes(node.else_body, &block)
      when AST::For
        collect_from_expr(node.iter, &block) if node.iter
        collect_getattr_nodes(node.body, &block)
      when AST::Set
        collect_from_expr(node.value, &block) if node.value
      when AST::SetBlock
        collect_getattr_nodes(node.body, &block)
      when AST::Block
        collect_getattr_nodes(node.body, &block)
      when AST::Macro
        collect_getattr_nodes(node.body, &block)
      when AST::CallBlock
        collect_from_expr(node.callee, &block)
        collect_getattr_nodes(node.body, &block)
      end
    end

    private def collect_from_expr(expr : AST::Expr, &block : AST::GetAttr ->) : Nil
      case expr
      when AST::GetAttr
        block.call(expr)
        collect_from_expr(expr.target, &block)
      when AST::Binary
        collect_from_expr(expr.left, &block)
        collect_from_expr(expr.right, &block)
      when AST::Unary
        collect_from_expr(expr.expr, &block)
      when AST::Filter
        collect_from_expr(expr.expr, &block)
        expr.args.each { |arg| collect_from_expr(arg, &block) }
      when AST::Test
        collect_from_expr(expr.expr, &block)
        expr.args.each { |arg| collect_from_expr(arg, &block) }
      when AST::Call
        collect_from_expr(expr.callee, &block)
        expr.args.each { |arg| collect_from_expr(arg, &block) }
      when AST::GetItem
        collect_from_expr(expr.target, &block)
        collect_from_expr(expr.index, &block)
      when AST::ListLiteral
        expr.items.each { |item| collect_from_expr(item, &block) }
      when AST::DictLiteral
        expr.pairs.each do |pair|
          collect_from_expr(pair.key, &block)
          collect_from_expr(pair.value, &block)
        end
      when AST::TupleLiteral
        expr.items.each { |item| collect_from_expr(item, &block) }
      when AST::Group
        collect_from_expr(expr.expr, &block)
      end
    end

    # Extract the base variable name from an expression
    private def extract_variable_name(expr : AST::Expr) : String?
      case expr
      when AST::Name
        expr.value
      when AST::GetAttr
        extract_variable_name(expr.target)
      end
    end
  end
end
