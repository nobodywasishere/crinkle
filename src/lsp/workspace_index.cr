require "../lexer/lexer"
require "../parser/parser"
require "../ast/nodes"
require "../ast/visitor"
require "./inference"
require "./config"

module Crinkle::LSP
  # Workspace-wide index of template symbols for unopened files.
  class WorkspaceIndex
    struct Entry
      getter uri : String
      getter macros : Array(MacroInfo)
      getter blocks : Array(BlockInfo)
      getter variables : Array(VariableInfo)
      getter relationships : Array(String)

      def initialize(
        @uri : String,
        @macros : Array(MacroInfo),
        @blocks : Array(BlockInfo),
        @variables : Array(VariableInfo),
        @relationships : Array(String),
      ) : Nil
      end
    end

    getter entries : Hash(String, Entry)

    def initialize(@config : Config, @root_path : String) : Nil
      @entries = Hash(String, Entry).new
    end

    def rebuild : Nil
      @entries.clear
      discover_template_paths.each do |path|
        index_path(path)
      end
    end

    def update_path(path : String) : Nil
      if File.exists?(path)
        index_path(path)
      else
        uri = path_to_uri(path)
        @entries.delete(uri)
      end
    end

    def entry_for(uri : String) : Entry?
      @entries[uri]?
    end

    def all_macros : Hash(String, Array(MacroInfo))
      result = Hash(String, Array(MacroInfo)).new
      @entries.each do |uri, entry|
        result[uri] = entry.macros
      end
      result
    end

    def all_blocks : Hash(String, Array(BlockInfo))
      result = Hash(String, Array(BlockInfo)).new
      @entries.each do |uri, entry|
        result[uri] = entry.blocks
      end
      result
    end

    def all_variables : Hash(String, Array(VariableInfo))
      result = Hash(String, Array(VariableInfo)).new
      @entries.each do |uri, entry|
        result[uri] = entry.variables
      end
      result
    end

    private def discover_template_paths : Array(String)
      paths = Array(String).new
      @config.template_paths.each do |template_root|
        root = if template_root.starts_with?("/")
                 template_root
               else
                 File.join(@root_path, template_root)
               end
        next unless Dir.exists?(root)
        Dir.glob(File.join(root, "**", "*")) do |path|
          next unless File.file?(path)
          next unless template_file?(path)
          paths << path
        end
      end
      paths
    end

    private def template_file?(path : String) : Bool
      path.ends_with?(".j2") || path.ends_with?(".jinja") || path.ends_with?(".jinja2")
    end

    private def index_path(path : String) : Nil
      source = File.read(path)
      lexer = Lexer.new(source)
      tokens = lexer.lex_all
      parser = Parser.new(tokens)
      ast = parser.parse

      macros = Array(MacroInfo).new
      blocks = Array(BlockInfo).new
      variables = Array(VariableInfo).new
      relationships = Array(String).new

      extract_macros(ast.body, macros)
      extract_blocks(ast.body, blocks, path_to_uri(path))
      extract_variables(ast.body, variables)
      extract_relationships(ast.body, relationships)

      uri = path_to_uri(path)
      @entries[uri] = Entry.new(uri, macros, blocks, variables, relationships)
    rescue
      # Ignore parse errors for indexing
    end

    private def extract_macros(nodes : Array(AST::Node), macros : Array(MacroInfo)) : Nil
      AST::Walker.walk_nodes(nodes) do |node|
        next unless node.is_a?(AST::Macro)

        params = node.params.map(&.name)
        defaults = Hash(String, String).new
        node.params.each do |param|
          if default = param.default_value
            defaults[param.name] = expr_to_string(default)
          end
        end
        macros << MacroInfo.new(node.name, params, defaults, node.span)
      end
    end

    private def extract_blocks(nodes : Array(AST::Node), blocks : Array(BlockInfo), uri : String) : Nil
      AST::Walker.walk_nodes(nodes) do |node|
        next unless node.is_a?(AST::Block)
        blocks << BlockInfo.new(node.name, node.span, uri)
      end
    end

    private def extract_variables(nodes : Array(AST::Node), vars : Array(VariableInfo)) : Nil
      AST::Walker.walk_nodes(nodes) do |node|
        case node
        when AST::For
          collect_target_variables(node.target, VariableSource::ForLoop, "loop variable", node.span, vars)
        when AST::Set
          collect_target_variables(node.target, VariableSource::Set, "assigned", node.span, vars)
        when AST::SetBlock
          collect_target_variables(node.target, VariableSource::SetBlock, "block assigned", node.span, vars)
        when AST::Macro
          node.params.each do |param|
            vars << VariableInfo.new(param.name, VariableSource::MacroParam, "macro #{node.name}", param.span)
          end
        end
      end
    end

    private def collect_target_variables(target : AST::Target, source : VariableSource, detail : String, span : Span, vars : Array(VariableInfo)) : Nil
      case target
      when AST::Name
        vars << VariableInfo.new(target.value, source, detail, span)
      when AST::TupleLiteral
        target.items.each do |item|
          if item.is_a?(AST::Name)
            vars << VariableInfo.new(item.value, source, detail, span)
          end
        end
      end
    end

    private def extract_relationships(nodes : Array(AST::Node), relationships : Array(String)) : Nil
      AST::Walker.walk_nodes(nodes) do |node|
        case node
        when AST::Extends, AST::Include, AST::Import, AST::FromImport
          if path = extract_template_path(node.template)
            relationships << path
          end
        end
      end
    end

    private def extract_template_path(expr : AST::Expr) : String?
      case expr
      when AST::Literal
        value = expr.value
        value.is_a?(String) ? value : nil
      end
    end

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

    private def path_to_uri(path : String) : String
      "file://#{File.expand_path(path)}"
    end
  end
end
