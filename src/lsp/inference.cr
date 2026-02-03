require "../ast/nodes"
require "../parser/parser"

module Crinkle::LSP
  # Inference engine for zero-config property completions
  # Tracks property usage across templates and provides suggestions
  class InferenceEngine
    # Maps URI -> variable name -> set of properties
    @usage : Hash(String, Hash(String, Set(String)))
    # Maps URI -> template paths it extends/includes (for cross-template inference)
    @relationships : Hash(String, Set(String))
    # Maps template path -> URI (reverse lookup)
    @path_to_uri : Hash(String, String)
    @config : Config

    def initialize(@config : Config) : Nil
      @usage = Hash(String, Hash(String, Set(String))).new
      @relationships = Hash(String, Set(String)).new
      @path_to_uri = Hash(String, String).new
    end

    # Analyze a template and extract property usage
    def analyze(uri : String, text : String) : Nil
      return unless @config.inference.enabled?

      begin
        lexer = Lexer.new(text)
        tokens = lexer.lex_all
        parser = Parser.new(tokens)
        ast = parser.parse

        properties = Hash(String, Set(String)).new
        extract_properties(ast.body, properties)
        @usage[uri] = properties

        # Extract and track template relationships
        if @config.inference.cross_template?
          relationships = Set(String).new
          extract_relationships(ast.body, relationships)
          @relationships[uri] = relationships

          # Register this URI by its template path for reverse lookup
          register_uri_path(uri)
        end
      rescue
        # Ignore parse errors - we're doing best-effort inference
      end
    end

    # Register a URI by extracting its template path component
    private def register_uri_path(uri : String) : Nil
      # Extract filename from URI (e.g., "file:///path/to/templates/base.html.j2" -> "base.html.j2")
      if path = uri_to_template_path(uri)
        @path_to_uri[path] = uri
      end
    end

    # Convert a URI to a relative template path
    private def uri_to_template_path(uri : String) : String?
      # Remove file:// prefix and get the path
      path = uri.sub(/^file:\/\//, "")
      # Return just the filename for simple matching
      File.basename(path)
    end

    # Extract extends/include/import relationships from nodes
    private def extract_relationships(nodes : Array(AST::Node), relationships : Set(String)) : Nil
      nodes.each do |node|
        case node
        when AST::Extends
          if path = extract_template_path(node.template)
            relationships << path
          end
        when AST::Include
          if path = extract_template_path(node.template)
            relationships << path
          end
        when AST::Import
          if path = extract_template_path(node.template)
            relationships << path
          end
        when AST::FromImport
          if path = extract_template_path(node.template)
            relationships << path
          end
        when AST::If
          extract_relationships(node.body, relationships)
          extract_relationships(node.else_body, relationships)
        when AST::For
          extract_relationships(node.body, relationships)
        when AST::Block
          extract_relationships(node.body, relationships)
        when AST::Macro
          extract_relationships(node.body, relationships)
        end
      end
    end

    # Extract template path from an expression (usually a string literal)
    private def extract_template_path(expr : AST::Expr) : String?
      case expr
      when AST::Literal
        value = expr.value
        value.is_a?(String) ? value : nil
      end
    end

    # Extract properties from AST nodes recursively
    private def extract_properties(nodes : Array(AST::Node), properties : Hash(String, Set(String))) : Nil
      nodes.each do |node|
        extract_from_node(node, properties)
      end
    end

    # Extract properties from a single node
    private def extract_from_node(node : AST::Node, properties : Hash(String, Set(String))) : Nil
      case node
      when AST::Output
        extract_from_expr(node.expr, properties)
      when AST::If
        extract_from_expr(node.test, properties)
        extract_properties(node.body, properties)
        extract_properties(node.else_body, properties)
      when AST::For
        extract_from_expr(node.iter, properties) if node.iter
        extract_properties(node.body, properties)
      when AST::Set
        extract_from_expr(node.value, properties) if node.value
      when AST::SetBlock
        extract_properties(node.body, properties)
      when AST::Block
        extract_properties(node.body, properties)
      when AST::Macro
        extract_properties(node.body, properties)
      when AST::CallBlock
        extract_from_expr(node.callee, properties)
        extract_properties(node.body, properties)
      end
    end

    # Extract properties from an expression
    private def extract_from_expr(expr : AST::Expr, properties : Hash(String, Set(String))) : Nil
      case expr
      when AST::GetAttr
        # Track variable.property access
        if var_name = extract_variable_name(expr.target)
          properties[var_name] ||= Set(String).new
          properties[var_name] << expr.name
        end
        extract_from_expr(expr.target, properties)
      when AST::Binary
        extract_from_expr(expr.left, properties)
        extract_from_expr(expr.right, properties)
      when AST::Unary
        extract_from_expr(expr.expr, properties)
      when AST::Filter
        extract_from_expr(expr.expr, properties)
        expr.args.each { |arg| extract_from_expr(arg, properties) }
      when AST::Test
        extract_from_expr(expr.expr, properties)
        expr.args.each { |arg| extract_from_expr(arg, properties) }
      when AST::Call
        extract_from_expr(expr.callee, properties)
        expr.args.each { |arg| extract_from_expr(arg, properties) }
      when AST::GetItem
        extract_from_expr(expr.target, properties)
        extract_from_expr(expr.index, properties)
      when AST::ListLiteral
        expr.items.each { |item| extract_from_expr(item, properties) }
      when AST::DictLiteral
        expr.pairs.each do |pair|
          extract_from_expr(pair.key, properties)
          extract_from_expr(pair.value, properties)
        end
      when AST::TupleLiteral
        expr.items.each { |item| extract_from_expr(item, properties) }
      when AST::Group
        extract_from_expr(expr.expr, properties)
      end
    end

    # Extract the base variable name from an expression
    # e.g., user.profile.name -> "user"
    private def extract_variable_name(expr : AST::Expr) : String?
      case expr
      when AST::Name
        expr.value
      when AST::GetAttr
        extract_variable_name(expr.target)
      end
    end

    # Get properties for a variable in a specific template (includes cross-template inference)
    def properties_for(uri : String, variable : String) : Array(String)
      props = Set(String).new

      # Add properties from this template
      if local_props = @usage[uri]?.try(&.[variable]?)
        props.concat(local_props)
      end

      # Add properties from related templates (extends/includes)
      if @config.inference.cross_template?
        collect_related_properties(uri, variable, props, visited: Set(String).new)
      end

      props.to_a
    end

    # Recursively collect properties from related templates
    private def collect_related_properties(
      uri : String,
      variable : String,
      props : Set(String),
      visited : Set(String),
    ) : Nil
      return if visited.includes?(uri)
      visited << uri

      # Get relationships for this template
      relationships = @relationships[uri]?
      return unless relationships

      relationships.each do |template_path|
        # Find the URI for this template path
        related_uri = resolve_template_uri(uri, template_path)
        next unless related_uri

        # Add properties from the related template
        if related_props = @usage[related_uri]?.try(&.[variable]?)
          props.concat(related_props)
        end

        # Recursively check relationships (one level deep by default)
        # This handles extends chains like child -> parent -> grandparent
        collect_related_properties(related_uri, variable, props, visited)
      end
    end

    # Resolve a template path to a URI
    private def resolve_template_uri(current_uri : String, template_path : String) : String?
      # First try direct lookup by filename
      if uri = @path_to_uri[template_path]?
        return uri
      end

      # Try to resolve relative to current template's directory
      if current_uri.starts_with?("file://")
        current_path = current_uri.sub(/^file:\/\//, "")
        current_dir = File.dirname(current_path)
        resolved_path = File.join(current_dir, template_path)

        # Check if we have this path registered
        resolved_basename = File.basename(resolved_path)
        if uri = @path_to_uri[resolved_basename]?
          return uri
        end

        # Build a file:// URI for the resolved path
        return "file://#{resolved_path}"
      end

      nil
    end

    # Get all variables tracked for a template
    def variables_for(uri : String) : Array(String)
      @usage[uri]?.try(&.keys) || Array(String).new
    end

    # Clear analysis for a template
    def clear(uri : String) : Nil
      @usage.delete(uri)
      @relationships.delete(uri)
      # Note: we don't clear @path_to_uri as other templates may still reference it
    end

    # Clear all analysis
    def clear_all : Nil
      @usage.clear
      @relationships.clear
      @path_to_uri.clear
    end

    # Find similar property names (for typo detection)
    # Uses Levenshtein distance
    def similar_properties(uri : String, variable : String, property : String, threshold : Int32 = 2) : Array(String)
      properties = properties_for(uri, variable)
      properties.select do |prop|
        distance = levenshtein_distance(property, prop)
        distance > 0 && distance <= threshold
      end.sort_by! { |prop| levenshtein_distance(property, prop) }
    end

    # Calculate Levenshtein distance between two strings
    private def levenshtein_distance(s1 : String, s2 : String) : Int32
      return s2.size if s1.empty?
      return s1.size if s2.empty?

      # Create distance matrix
      d = Array.new(s1.size + 1) { Array.new(s2.size + 1, 0) }

      (0..s1.size).each { |i| d[i][0] = i }
      (0..s2.size).each { |j| d[0][j] = j }

      (1..s1.size).each do |i|
        (1..s2.size).each do |j|
          cost = s1[i - 1] == s2[j - 1] ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,        # deletion
            d[i][j - 1] + 1,        # insertion
            d[i - 1][j - 1] + cost, # substitution
          ].min
        end
      end

      d[s1.size][s2.size]
    end
  end
end
