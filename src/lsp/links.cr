module Crinkle::LSP
  # Template reference found in the source
  private struct TemplateRef
    property path : String
    property range : Range

    def initialize(@path : String, @range : Range) : Nil
    end
  end

  # Provides document links for template references (extends, include, import, from)
  class DocumentLinkProvider
    @root_path : String

    def initialize(@root_path : String) : Nil
    end

    # Find all document links in the text
    def links(uri : String, text : String) : Array(DocumentLink)
      links = Array(DocumentLink).new
      refs = find_template_references(text)

      refs.each do |ref|
        resolved = resolve_template_path(uri, ref.path)
        next unless resolved && File.exists?(resolved)

        links << DocumentLink.new(
          range: ref.range,
          target: "file://#{resolved}",
          tooltip: "Open #{ref.path}"
        )
      end

      links
    end

    # Find all template references in the text using the AST
    private def find_template_references(text : String) : Array(TemplateRef)
      refs = Array(TemplateRef).new

      begin
        lexer = Lexer.new(text)
        tokens = lexer.lex_all
        parser = Parser.new(tokens)
        ast = parser.parse

        find_refs_in_nodes(ast.body, refs)
      rescue
        # Parse error - return empty
      end

      refs
    end

    # Recursively find template references in nodes
    private def find_refs_in_nodes(nodes : Array(AST::Node), refs : Array(TemplateRef)) : Nil
      nodes.each do |node|
        case node
        when AST::Extends
          if path = extract_string_value(node.template)
            refs << TemplateRef.new(
              path: path,
              range: expr_to_range(node.template)
            )
          end
        when AST::Include
          if path = extract_string_value(node.template)
            refs << TemplateRef.new(
              path: path,
              range: expr_to_range(node.template)
            )
          end
        when AST::Import
          if path = extract_string_value(node.template)
            refs << TemplateRef.new(
              path: path,
              range: expr_to_range(node.template)
            )
          end
        when AST::FromImport
          if path = extract_string_value(node.template)
            refs << TemplateRef.new(
              path: path,
              range: expr_to_range(node.template)
            )
          end
        when AST::If
          find_refs_in_nodes(node.body, refs)
          find_refs_in_nodes(node.else_body, refs)
        when AST::For
          find_refs_in_nodes(node.body, refs)
          find_refs_in_nodes(node.else_body, refs)
        when AST::Block
          find_refs_in_nodes(node.body, refs)
        when AST::Macro
          find_refs_in_nodes(node.body, refs)
        when AST::SetBlock
          find_refs_in_nodes(node.body, refs)
        when AST::CallBlock
          find_refs_in_nodes(node.body, refs)
        end
      end
    end

    # Extract string value from an expression (handles String literals)
    private def extract_string_value(expr : AST::Expr) : String?
      case expr
      when AST::Literal
        value = expr.value
        value.is_a?(String) ? value : nil
      end
    end

    # Convert an expression's span to an LSP range
    private def expr_to_range(expr : AST::Expr) : Range
      span_to_range(expr.span)
    end

    # Resolve a template path to an absolute file path
    private def resolve_template_path(current_uri : String, template_path : String) : String?
      current_path = uri_to_path(current_uri)
      current_dir = File.dirname(current_path)

      # Try several resolution strategies
      candidates = [
        # Relative to current file
        File.join(current_dir, template_path),
        # Relative to root
        File.join(@root_path, template_path),
        # Common template directories
        File.join(@root_path, "templates", template_path),
        File.join(@root_path, "views", template_path),
        File.join(@root_path, "src", "templates", template_path),
      ]

      # Also try walking up from current directory
      dir = current_dir
      while dir.starts_with?(@root_path) && dir != @root_path
        candidates << File.join(dir, template_path)
        dir = File.dirname(dir)
      end

      candidates.each do |candidate|
        expanded = File.expand_path(candidate)
        return expanded if File.exists?(expanded)
      end

      nil
    end

    # Convert file:// URI to path
    private def uri_to_path(uri : String) : String
      uri.sub(/^file:\/\//, "")
    end

    # Convert a Span (1-based lines from lexer) to an LSP Range (0-based lines)
    private def span_to_range(span : Span) : Range
      Range.new(
        start: Position.new(line: span.start_pos.line - 1, character: span.start_pos.column - 1),
        end_pos: Position.new(line: span.end_pos.line - 1, character: span.end_pos.column - 1)
      )
    end
  end
end
