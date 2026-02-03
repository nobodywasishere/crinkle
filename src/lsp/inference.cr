require "../ast/nodes"
require "../parser/parser"

module Crinkle::LSP
  # Source of a variable definition
  enum VariableSource
    Context    # Context variable (from template usage)
    ForLoop    # For loop variable
    Set        # Set statement
    SetBlock   # Set block
    MacroParam # Macro parameter
  end

  # Information about a variable
  struct VariableInfo
    property name : String
    property source : VariableSource
    property detail : String? # Extra info (e.g., "from for loop", iterator name)

    def initialize(@name : String, @source : VariableSource, @detail : String? = nil) : Nil
    end
  end

  # Information about a macro definition
  struct MacroInfo
    property name : String
    property params : Array(String)
    property defaults : Hash(String, String) # param name -> default value representation

    def initialize(@name : String, @params : Array(String), @defaults : Hash(String, String) = Hash(String, String).new) : Nil
    end

    def signature : String
      param_strs = params.map do |param|
        if default = defaults[param]?
          "#{param}=#{default}"
        else
          param
        end
      end
      "#{name}(#{param_strs.join(", ")})"
    end
  end

  # Inference engine for zero-config property completions
  # Tracks property usage across templates and provides suggestions
  class InferenceEngine
    # Maps URI -> variable name -> set of properties
    @usage : Hash(String, Hash(String, Set(String)))
    # Maps URI -> template paths it extends/includes (for cross-template inference)
    @relationships : Hash(String, Set(String))
    # Maps template path -> URI (reverse lookup)
    @path_to_uri : Hash(String, String)
    # Maps URI -> variable info (name -> info)
    @variables : Hash(String, Hash(String, VariableInfo))
    # Maps URI -> block names defined in template
    @blocks : Hash(String, Set(String))
    # Maps URI -> macro definitions
    @macros : Hash(String, Hash(String, MacroInfo))
    @config : Config

    def initialize(@config : Config) : Nil
      @usage = Hash(String, Hash(String, Set(String))).new
      @relationships = Hash(String, Set(String)).new
      @path_to_uri = Hash(String, String).new
      @variables = Hash(String, Hash(String, VariableInfo)).new
      @blocks = Hash(String, Set(String)).new
      @macros = Hash(String, Hash(String, MacroInfo)).new
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

        # Extract variables from various sources
        vars = Hash(String, VariableInfo).new
        extract_variables(ast.body, vars)
        @variables[uri] = vars

        # Extract block names
        blks = Set(String).new
        extract_blocks(ast.body, blks)
        @blocks[uri] = blks

        # Extract macro definitions
        macs = Hash(String, MacroInfo).new
        extract_macros(ast.body, macs)
        @macros[uri] = macs

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

    # Extract variables from AST nodes (for loops, set statements, macro params)
    private def extract_variables(nodes : Array(AST::Node), vars : Hash(String, VariableInfo), scope_prefix : String? = nil) : Nil
      nodes.each do |node|
        case node
        when AST::For
          # Extract for loop variable(s)
          extract_target_variables(node.target, vars, VariableSource::ForLoop, "loop variable")
          extract_variables(node.body, vars, scope_prefix)
        when AST::Set
          # Extract set variable(s)
          extract_target_variables(node.target, vars, VariableSource::Set, "assigned")
        when AST::SetBlock
          # Extract set block variable(s)
          extract_target_variables(node.target, vars, VariableSource::SetBlock, "block assigned")
          extract_variables(node.body, vars, scope_prefix)
        when AST::Macro
          # Extract macro parameters as variables (scoped to macro body)
          node.params.each do |param|
            vars[param.name] = VariableInfo.new(param.name, VariableSource::MacroParam, "macro #{node.name}")
          end
          extract_variables(node.body, vars, scope_prefix)
        when AST::If
          extract_variables(node.body, vars, scope_prefix)
          extract_variables(node.else_body, vars, scope_prefix)
        when AST::Block
          extract_variables(node.body, vars, scope_prefix)
        when AST::CallBlock
          extract_variables(node.body, vars, scope_prefix)
        end
      end

      # Also extract context variables from property access (e.g., user.name implies "user" exists)
      extract_context_variables(nodes, vars)
    end

    # Extract variable names from a target (handles tuples for unpacking)
    private def extract_target_variables(target : AST::Target, vars : Hash(String, VariableInfo), source : VariableSource, detail : String) : Nil
      case target
      when AST::Name
        vars[target.value] = VariableInfo.new(target.value, source, detail)
      when AST::TupleLiteral
        target.items.each do |item|
          if item.is_a?(AST::Name)
            vars[item.value] = VariableInfo.new(item.value, source, detail)
          end
        end
      end
    end

    # Extract context variables from expression usage (variables accessed but not defined locally)
    private def extract_context_variables(nodes : Array(AST::Node), vars : Hash(String, VariableInfo)) : Nil
      nodes.each do |node|
        case node
        when AST::Output
          extract_context_from_expr(node.expr, vars)
        when AST::If
          extract_context_from_expr(node.test, vars)
          extract_context_variables(node.body, vars)
          extract_context_variables(node.else_body, vars)
        when AST::For
          extract_context_from_expr(node.iter, vars) if node.iter
          extract_context_variables(node.body, vars)
        when AST::Set
          extract_context_from_expr(node.value, vars) if node.value
        when AST::SetBlock
          extract_context_variables(node.body, vars)
        when AST::Block
          extract_context_variables(node.body, vars)
        when AST::Macro
          extract_context_variables(node.body, vars)
        when AST::CallBlock
          extract_context_from_expr(node.callee, vars)
          extract_context_variables(node.body, vars)
        end
      end
    end

    # Extract context variables from an expression
    private def extract_context_from_expr(expr : AST::Expr, vars : Hash(String, VariableInfo)) : Nil
      case expr
      when AST::Name
        # Add as context variable if not already defined
        vars[expr.value] ||= VariableInfo.new(expr.value, VariableSource::Context, "context")
      when AST::GetAttr
        extract_context_from_expr(expr.target, vars)
      when AST::Binary
        extract_context_from_expr(expr.left, vars)
        extract_context_from_expr(expr.right, vars)
      when AST::Unary
        extract_context_from_expr(expr.expr, vars)
      when AST::Filter
        extract_context_from_expr(expr.expr, vars)
        expr.args.each { |arg| extract_context_from_expr(arg, vars) }
      when AST::Test
        extract_context_from_expr(expr.expr, vars)
        expr.args.each { |arg| extract_context_from_expr(arg, vars) }
      when AST::Call
        extract_context_from_expr(expr.callee, vars)
        expr.args.each { |arg| extract_context_from_expr(arg, vars) }
      when AST::GetItem
        extract_context_from_expr(expr.target, vars)
        extract_context_from_expr(expr.index, vars)
      when AST::ListLiteral
        expr.items.each { |item| extract_context_from_expr(item, vars) }
      when AST::DictLiteral
        expr.pairs.each do |pair|
          extract_context_from_expr(pair.key, vars)
          extract_context_from_expr(pair.value, vars)
        end
      when AST::TupleLiteral
        expr.items.each { |item| extract_context_from_expr(item, vars) }
      when AST::Group
        extract_context_from_expr(expr.expr, vars)
      end
    end

    # Extract block names from AST nodes
    private def extract_blocks(nodes : Array(AST::Node), blks : Set(String)) : Nil
      nodes.each do |node|
        case node
        when AST::Block
          blks << node.name
          extract_blocks(node.body, blks)
        when AST::If
          extract_blocks(node.body, blks)
          extract_blocks(node.else_body, blks)
        when AST::For
          extract_blocks(node.body, blks)
        when AST::Macro
          extract_blocks(node.body, blks)
        end
      end
    end

    # Extract macro definitions from AST nodes
    private def extract_macros(nodes : Array(AST::Node), macs : Hash(String, MacroInfo)) : Nil
      nodes.each do |node|
        case node
        when AST::Macro
          params = node.params.map(&.name)
          defaults = Hash(String, String).new
          node.params.each do |param|
            if default = param.default_value
              defaults[param.name] = expr_to_string(default)
            end
          end
          macs[node.name] = MacroInfo.new(node.name, params, defaults)
          extract_macros(node.body, macs)
        when AST::If
          extract_macros(node.body, macs)
          extract_macros(node.else_body, macs)
        when AST::For
          extract_macros(node.body, macs)
        when AST::Block
          extract_macros(node.body, macs)
        end
      end
    end

    # Convert an expression to a string representation (for default values)
    private def expr_to_string(expr : AST::Expr) : String
      case expr
      when AST::Literal
        value = expr.value
        case value
        when String
          %("#{value}")
        when nil
          "none"
        else
          value.to_s
        end
      when AST::Name
        expr.value
      when AST::ListLiteral
        "[...]"
      when AST::DictLiteral
        "{...}"
      else
        "..."
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

    # Get all variables tracked for a template (includes cross-template variables)
    def variables_for(uri : String) : Array(VariableInfo)
      vars = Hash(String, VariableInfo).new

      # Add variables from this template
      if local_vars = @variables[uri]?
        local_vars.each { |name, info| vars[name] = info }
      end

      # Add variables from related templates (extends/includes)
      if @config.inference.cross_template?
        collect_related_variables(uri, vars, visited: Set(String).new)
      end

      vars.values.to_a
    end

    # Get variable names only (backward compatible)
    def variable_names_for(uri : String) : Array(String)
      variables_for(uri).map(&.name)
    end

    # Recursively collect variables from related templates
    private def collect_related_variables(uri : String, vars : Hash(String, VariableInfo), visited : Set(String)) : Nil
      return if visited.includes?(uri)
      visited << uri

      relationships = @relationships[uri]?
      return unless relationships

      relationships.each do |template_path|
        related_uri = resolve_template_uri(uri, template_path)
        next unless related_uri

        if related_vars = @variables[related_uri]?
          related_vars.each { |name, info| vars[name] ||= info }
        end

        collect_related_variables(related_uri, vars, visited)
      end
    end

    # Get block names for a template (includes blocks from extended templates)
    def blocks_for(uri : String) : Array(String)
      blks = Set(String).new

      # Add blocks from this template
      if local_blks = @blocks[uri]?
        blks.concat(local_blks)
      end

      # Add blocks from extended templates (for block override suggestions)
      if @config.inference.cross_template?
        collect_related_blocks(uri, blks, visited: Set(String).new)
      end

      blks.to_a
    end

    # Recursively collect blocks from extended templates
    private def collect_related_blocks(uri : String, blks : Set(String), visited : Set(String)) : Nil
      return if visited.includes?(uri)
      visited << uri

      relationships = @relationships[uri]?
      return unless relationships

      relationships.each do |template_path|
        related_uri = resolve_template_uri(uri, template_path)
        next unless related_uri

        if related_blks = @blocks[related_uri]?
          blks.concat(related_blks)
        end

        collect_related_blocks(related_uri, blks, visited)
      end
    end

    # Get macro definitions for a template (includes imported macros)
    def macros_for(uri : String) : Array(MacroInfo)
      macs = Hash(String, MacroInfo).new

      # Add macros from this template
      if local_macs = @macros[uri]?
        local_macs.each { |name, info| macs[name] = info }
      end

      # Add macros from related templates (imports)
      if @config.inference.cross_template?
        collect_related_macros(uri, macs, visited: Set(String).new)
      end

      macs.values.to_a
    end

    # Recursively collect macros from related templates
    private def collect_related_macros(uri : String, macs : Hash(String, MacroInfo), visited : Set(String)) : Nil
      return if visited.includes?(uri)
      visited << uri

      relationships = @relationships[uri]?
      return unless relationships

      relationships.each do |template_path|
        related_uri = resolve_template_uri(uri, template_path)
        next unless related_uri

        if related_macs = @macros[related_uri]?
          related_macs.each { |name, info| macs[name] ||= info }
        end

        collect_related_macros(related_uri, macs, visited)
      end
    end

    # Get the template path that a URI extends (if any)
    def extends_path(uri : String) : String?
      @relationships[uri]?.try do |rels|
        # Return the first relationship (extends is typically first)
        rels.first?
      end
    end

    # Clear analysis for a template
    def clear(uri : String) : Nil
      @usage.delete(uri)
      @relationships.delete(uri)
      @variables.delete(uri)
      @blocks.delete(uri)
      @macros.delete(uri)
      # Note: we don't clear @path_to_uri as other templates may still reference it
    end

    # Clear all analysis
    def clear_all : Nil
      @usage.clear
      @relationships.clear
      @path_to_uri.clear
      @variables.clear
      @blocks.clear
      @macros.clear
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
