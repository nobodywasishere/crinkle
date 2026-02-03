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
    property detail : String?        # Extra info (e.g., "from for loop", iterator name)
    property definition_span : Span? # Where the variable is defined

    def initialize(@name : String, @source : VariableSource, @detail : String? = nil, @definition_span : Span? = nil) : Nil
    end
  end

  # Information about a macro definition
  struct MacroInfo
    property name : String
    property params : Array(String)
    property defaults : Hash(String, String) # param name -> default value representation
    property definition_span : Span?         # Where the macro is defined

    def initialize(@name : String, @params : Array(String), @defaults : Hash(String, String) = Hash(String, String).new, @definition_span : Span? = nil) : Nil
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

  # Information about a block definition
  struct BlockInfo
    property name : String
    property definition_span : Span? # Where the block is defined
    property source_uri : String?    # Which template the block is defined in

    def initialize(@name : String, @definition_span : Span? = nil, @source_uri : String? = nil) : Nil
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
    # Maps URI -> block definitions (name -> info)
    @blocks : Hash(String, Hash(String, BlockInfo))
    # Maps URI -> macro definitions
    @macros : Hash(String, Hash(String, MacroInfo))
    @config : Config
    @root_path : String?

    def initialize(@config : Config, @root_path : String? = nil) : Nil
      @usage = Hash(String, Hash(String, Set(String))).new
      @relationships = Hash(String, Set(String)).new
      @path_to_uri = Hash(String, String).new
      @variables = Hash(String, Hash(String, VariableInfo)).new
      @blocks = Hash(String, Hash(String, BlockInfo)).new
      @macros = Hash(String, Hash(String, MacroInfo)).new
    end

    # Set the root path for resolving template imports
    def root_path=(path : String?) : Nil
      @root_path = path
    end

    # Enable debug logging
    class_property? debug : Bool = false

    private def debug(msg : String) : Nil
      STDERR.puts "[InferenceEngine] #{msg}" if self.class.debug?
    end

    # Analyze a template and extract property usage
    def analyze(uri : String, text : String) : Nil
      debug "analyze(#{uri})"
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

        # Extract block definitions with spans
        blks = Hash(String, BlockInfo).new
        extract_blocks(ast.body, blks, uri)
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
          debug "  relationships for #{uri}: #{relationships.to_a}"

          # Register this URI by its template path for reverse lookup
          register_uri_path(uri)
          debug "  path_to_uri after registration: #{@path_to_uri}"

          # Automatically analyze imported templates
          analyze_related_templates(uri, relationships)
        else
          debug "  cross_template disabled"
        end
      rescue
        # Ignore parse errors - we're doing best-effort inference
      end
    end

    # Automatically analyze templates that are imported/extended/included
    private def analyze_related_templates(current_uri : String, relationships : Set(String)) : Nil
      debug "analyze_related_templates(#{current_uri})"
      debug "  root_path: #{@root_path.inspect}"
      relationships.each do |template_path|
        debug "  checking relationship: #{template_path}"
        # Skip if already analyzed
        if @path_to_uri[template_path]?
          debug "    already analyzed (in path_to_uri)"
          next
        end

        # Try to resolve and analyze the template
        resolved_path = resolve_template_file(current_uri, template_path)
        debug "    resolved_path: #{resolved_path.inspect}"
        if resolved_path
          exists = File.exists?(resolved_path)
          debug "    file exists: #{exists}"
          if exists
            begin
              content = File.read(resolved_path)
              resolved_uri = "file://#{File.expand_path(resolved_path)}"
              debug "    analyzing resolved_uri: #{resolved_uri}"
              analyze(resolved_uri, content)
            rescue ex
              debug "    read error: #{ex.message}"
            end
          end
        end
      end
    end

    # Resolve a template path to an actual file path
    private def resolve_template_file(current_uri : String, template_path : String) : String?
      debug "resolve_template_file(#{current_uri}, #{template_path})"

      # First try relative to current template's directory
      if current_uri.starts_with?("file://")
        current_path = current_uri.sub(/^file:\/\//, "")
        current_dir = File.dirname(current_path)
        relative_path = File.join(current_dir, template_path)
        debug "  trying relative: #{relative_path} (exists: #{File.exists?(relative_path)})"
        return relative_path if File.exists?(relative_path)

        # Walk up the directory tree to find a templates root
        # This handles cases like src2/templates/settings/ai.html.j2 looking for layouts/foo.html.j2
        dir = current_dir
        while dir != "/" && dir != "."
          candidate = File.join(dir, template_path)
          debug "  trying ancestor: #{candidate} (exists: #{File.exists?(candidate)})"
          return candidate if File.exists?(candidate)
          dir = File.dirname(dir)
        end
      end

      # Try relative to root path
      if root = @root_path
        root_relative = File.join(root, template_path)
        debug "  trying root_relative: #{root_relative} (exists: #{File.exists?(root_relative)})"
        return root_relative if File.exists?(root_relative)

        # Try in common template directories (including src2/templates for kagi-style projects)
        ["templates", "views", "src/templates", "src2/templates", ""].each do |subdir|
          candidate = File.join(root, subdir, template_path)
          debug "  trying candidate: #{candidate} (exists: #{File.exists?(candidate)})"
          return candidate if File.exists?(candidate)
        end
      else
        debug "  no root_path set"
      end

      debug "  failed to resolve"
      nil
    end

    # Register a URI by extracting its template path component
    # Registers multiple path variants for flexible matching
    private def register_uri_path(uri : String) : Nil
      paths = uri_to_template_paths(uri)
      paths.each do |path|
        @path_to_uri[path] = uri
      end
    end

    # Convert a URI to multiple relative template path variants
    # Returns paths from most specific to least (e.g., "a/b/c.j2", "b/c.j2", "c.j2")
    private def uri_to_template_paths(uri : String) : Array(String)
      paths = Array(String).new
      # Remove file:// prefix and get the path
      full_path = uri.sub(/^file:\/\//, "")
      parts = full_path.split("/").reject(&.empty?)

      # Generate progressively shorter paths (last N components)
      # e.g., for /a/b/c/d.j2: ["d.j2", "c/d.j2", "b/c/d.j2", "a/b/c/d.j2"]
      (1..Math.min(parts.size, 5)).each do |depth|
        paths << parts.last(depth).join("/")
      end

      paths
    end

    # Extract extends/include/import relationships from nodes
    private def extract_relationships(nodes : Array(AST::Node), relationships : Set(String)) : Nil
      AST::Walker.walk_nodes(nodes) do |node|
        case node
        when AST::Extends, AST::Include, AST::Import, AST::FromImport
          if path = extract_template_path(node.template)
            relationships << path
          end
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
      AST::Walker.walk_nodes(nodes) do |node|
        case node
        when AST::For
          # Extract for loop variable(s) with the for statement span
          extract_target_variables(node.target, vars, VariableSource::ForLoop, "loop variable", node.span)
        when AST::Set
          # Extract set variable(s) with the set statement span
          extract_target_variables(node.target, vars, VariableSource::Set, "assigned", node.span)
        when AST::SetBlock
          # Extract set block variable(s) with the setblock span
          extract_target_variables(node.target, vars, VariableSource::SetBlock, "block assigned", node.span)
        when AST::Macro
          # Extract macro parameters as variables (scoped to macro body)
          node.params.each do |param|
            vars[param.name] = VariableInfo.new(param.name, VariableSource::MacroParam, "macro #{node.name}", param.span)
          end
        end
      end

      # Also extract context variables from property access (e.g., user.name implies "user" exists)
      extract_context_variables(nodes, vars)
    end

    # Extract variable names from a target (handles tuples for unpacking)
    private def extract_target_variables(target : AST::Target, vars : Hash(String, VariableInfo), source : VariableSource, detail : String, definition_span : Span? = nil) : Nil
      case target
      when AST::Name
        vars[target.value] = VariableInfo.new(target.value, source, detail, definition_span || target.span)
      when AST::TupleLiteral
        target.items.each do |item|
          if item.is_a?(AST::Name)
            vars[item.value] = VariableInfo.new(item.value, source, detail, definition_span || item.span)
          end
        end
      end
    end

    # Extract context variables from expression usage (variables accessed but not defined locally)
    private def extract_context_variables(nodes : Array(AST::Node), vars : Hash(String, VariableInfo)) : Nil
      AST::Walker.walk_nodes(nodes) do |node|
        case node
        when AST::Output
          extract_context_from_expr(node.expr, vars)
        when AST::If
          extract_context_from_expr(node.test, vars)
        when AST::For
          extract_context_from_expr(node.iter, vars)
        when AST::Set
          extract_context_from_expr(node.value, vars)
        when AST::CallBlock
          extract_context_from_expr(node.callee, vars)
        end
      end
    end

    # Extract context variables from an expression
    private def extract_context_from_expr(expr : AST::Expr, vars : Hash(String, VariableInfo)) : Nil
      AST::Walker.walk_expr(expr) do |inner|
        next unless inner.is_a?(AST::Name)
        # Add as context variable if not already defined
        vars[inner.value] ||= VariableInfo.new(inner.value, VariableSource::Context, "context")
      end
    end

    # Extract block definitions from AST nodes (with spans)
    private def extract_blocks(nodes : Array(AST::Node), blks : Hash(String, BlockInfo), uri : String) : Nil
      AST::Walker.walk_nodes(nodes) do |node|
        next unless node.is_a?(AST::Block)
        blks[node.name] = BlockInfo.new(node.name, node.span, uri)
      end
    end

    # Extract macro definitions from AST nodes
    private def extract_macros(nodes : Array(AST::Node), macs : Hash(String, MacroInfo)) : Nil
      AST::Walker.walk_nodes(nodes) do |node|
        next unless node.is_a?(AST::Macro)
        params = node.params.map(&.name)
        defaults = Hash(String, String).new
        node.params.each do |param|
          if default = param.default_value
            defaults[param.name] = expr_to_string(default)
          end
        end
        macs[node.name] = MacroInfo.new(node.name, params, defaults, node.span)
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
      AST::Walker.walk_nodes(nodes) do |node|
        case node
        when AST::Output
          extract_from_expr(node.expr, properties)
        when AST::If
          extract_from_expr(node.test, properties)
        when AST::For
          extract_from_expr(node.iter, properties)
        when AST::Set
          extract_from_expr(node.value, properties)
        when AST::CallBlock
          extract_from_expr(node.callee, properties)
        end
      end
    end

    # Extract properties from an expression
    private def extract_from_expr(expr : AST::Expr, properties : Hash(String, Set(String))) : Nil
      AST::Walker.walk_expr(expr) do |inner|
        next unless inner.is_a?(AST::GetAttr)
        if var_name = extract_variable_name(inner.target)
          properties[var_name] ||= Set(String).new
          properties[var_name] << inner.name
        end
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

    # Get variable info by name
    def variable_info(uri : String, name : String) : VariableInfo?
      # Check this template first
      if local_vars = @variables[uri]?
        if info = local_vars[name]?
          return info
        end
      end

      # Check extended templates
      if @config.inference.cross_template?
        return find_variable_in_related(uri, name, visited: Set(String).new)
      end

      nil
    end

    # Find a variable in related templates
    private def find_variable_in_related(uri : String, name : String, visited : Set(String)) : VariableInfo?
      return if visited.includes?(uri)
      visited << uri

      relationships = @relationships[uri]?
      return unless relationships

      relationships.each do |template_path|
        related_uri = resolve_template_uri(uri, template_path)
        next unless related_uri

        if related_vars = @variables[related_uri]?
          if info = related_vars[name]?
            return info
          end
        end

        if result = find_variable_in_related(related_uri, name, visited)
          return result
        end
      end

      nil
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
    # Returns just names for backward compatibility with completions
    def blocks_for(uri : String) : Array(String)
      blocks_info_for(uri).map(&.name)
    end

    # Get block info for a template (includes blocks from extended templates)
    def blocks_info_for(uri : String) : Array(BlockInfo)
      blks = Hash(String, BlockInfo).new

      # Add blocks from this template
      if local_blks = @blocks[uri]?
        local_blks.each { |name, info| blks[name] = info }
      end

      # Add blocks from extended templates (for block override suggestions)
      if @config.inference.cross_template?
        collect_related_blocks(uri, blks, visited: Set(String).new)
      end

      blks.values.to_a
    end

    # Get block info by name (searches this template and extended templates)
    def block_info(uri : String, name : String) : BlockInfo?
      # Check this template first
      if local_blks = @blocks[uri]?
        if info = local_blks[name]?
          return info
        end
      end

      # Check extended templates
      if @config.inference.cross_template?
        return find_block_in_related(uri, name, visited: Set(String).new)
      end

      nil
    end

    # Find a block in related templates
    private def find_block_in_related(uri : String, name : String, visited : Set(String)) : BlockInfo?
      return if visited.includes?(uri)
      visited << uri

      relationships = @relationships[uri]?
      return unless relationships

      relationships.each do |template_path|
        related_uri = resolve_template_uri(uri, template_path)
        next unless related_uri

        if related_blks = @blocks[related_uri]?
          if info = related_blks[name]?
            return info
          end
        end

        if result = find_block_in_related(related_uri, name, visited)
          return result
        end
      end

      nil
    end

    # Recursively collect blocks from extended templates
    private def collect_related_blocks(uri : String, blks : Hash(String, BlockInfo), visited : Set(String)) : Nil
      return if visited.includes?(uri)
      visited << uri

      relationships = @relationships[uri]?
      return unless relationships

      relationships.each do |template_path|
        related_uri = resolve_template_uri(uri, template_path)
        next unless related_uri

        if related_blks = @blocks[related_uri]?
          related_blks.each { |name, info| blks[name] ||= info }
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

    # Get only local macro definitions for a template (excludes imported macros)
    def local_macros_for(uri : String) : Array(MacroInfo)
      if local_macs = @macros[uri]?
        local_macs.values.to_a
      else
        Array(MacroInfo).new
      end
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

    # Get macro info by name
    def macro_info(uri : String, name : String) : MacroInfo?
      # Check this template first
      if local_macs = @macros[uri]?
        if info = local_macs[name]?
          return info
        end
      end

      # Check extended templates
      if @config.inference.cross_template?
        return find_macro_in_related(uri, name, visited: Set(String).new)
      end

      nil
    end

    # Find a macro in related templates
    private def find_macro_in_related(uri : String, name : String, visited : Set(String)) : MacroInfo?
      return if visited.includes?(uri)
      visited << uri

      relationships = @relationships[uri]?
      return unless relationships

      relationships.each do |template_path|
        related_uri = resolve_template_uri(uri, template_path)
        next unless related_uri

        if related_macs = @macros[related_uri]?
          if info = related_macs[name]?
            return info
          end
        end

        if result = find_macro_in_related(related_uri, name, visited)
          return result
        end
      end

      nil
    end

    # Get the template path that a URI extends (if any)
    def extends_path(uri : String) : String?
      @relationships[uri]?.try do |rels|
        # Return the first relationship (extends is typically first)
        rels.first?
      end
    end

    # Get all macros across all analyzed templates (for workspace symbol search)
    def all_macros : Hash(String, Array(MacroInfo))
      result = Hash(String, Array(MacroInfo)).new
      @macros.each do |uri, macs|
        result[uri] = macs.values.to_a
      end
      result
    end

    # Get all blocks across all analyzed templates (for workspace symbol search)
    def all_blocks : Hash(String, Array(BlockInfo))
      result = Hash(String, Array(BlockInfo)).new
      @blocks.each do |uri, blks|
        result[uri] = blks.values.to_a
      end
      result
    end

    # Get all variables across all analyzed templates (for workspace symbol search)
    def all_variables : Hash(String, Array(VariableInfo))
      result = Hash(String, Array(VariableInfo)).new
      @variables.each do |uri, vars|
        result[uri] = vars.values.to_a
      end
      result
    end

    # Get all template relationships for a URI (imports, extends, includes)
    def relationships_for(uri : String) : Array(String)
      @relationships[uri]?.try(&.to_a) || Array(String).new
    end

    # Resolve a template path to a URI (public interface for cross-template lookups)
    # This uses the internal @path_to_uri mapping populated during analysis
    def resolve_uri(current_uri : String, template_path : String) : String?
      resolve_template_uri(current_uri, template_path)
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
