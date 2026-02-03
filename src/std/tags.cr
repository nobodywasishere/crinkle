module Crinkle::Std
  # Built-in tag definitions for completions and documentation.
  # These are parsed by the parser (see Parser#tag_handlers) - this module
  # provides metadata for LSP completions and documentation.
  module Tags
    # Tag metadata for completions
    struct TagDef
      getter name : String
      getter doc : String
      getter? has_body : Bool
      getter end_tag : String?

      def initialize(@name : String, @doc : String, @has_body : Bool = false, @end_tag : String? = nil) : Nil
      end
    end

    # All built-in Jinja2/Crinkle tags
    BUILTINS = [
      TagDef.new("if", "Conditional statement", has_body: true, end_tag: "endif"),
      TagDef.new("for", "Iteration over sequences", has_body: true, end_tag: "endfor"),
      TagDef.new("set", "Assign values to variables", has_body: true, end_tag: "endset"),
      TagDef.new("block", "Define overridable template blocks", has_body: true, end_tag: "endblock"),
      TagDef.new("macro", "Define reusable template macros", has_body: true, end_tag: "endmacro"),
      TagDef.new("call", "Call a macro with a body", has_body: true, end_tag: "endcall"),
      TagDef.new("raw", "Output raw template syntax without processing", has_body: true, end_tag: "endraw"),
      TagDef.new("extends", "Inherit from a parent template"),
      TagDef.new("include", "Include another template"),
      TagDef.new("import", "Import macros from another template"),
      TagDef.new("from", "Import specific macros from another template"),
      TagDef.new("elif", "Else-if branch in conditional"),
      TagDef.new("else", "Else branch in conditional or for loop"),
    ]

    # Tags that have a body (and thus need an end tag)
    BLOCK_TAGS = BUILTINS.select(&.has_body?).map(&.name).to_set
  end
end
