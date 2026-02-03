require "./protocol"
require "./inference"

module Crinkle::LSP
  # Provides go-to-definition for template references
  class DefinitionProvider
    @inference : InferenceEngine
    @root_path : String?

    def initialize(@inference : InferenceEngine, @root_path : String?) : Nil
    end

    # Find the definition location for the token at the given position
    def definition(uri : String, text : String, position : Position) : Location?
      lines = text.split('\n')
      return if position.line >= lines.size

      line = lines[position.line]
      return if position.character > line.size

      # Check if cursor is on a template reference
      if template_ref = find_template_reference(line, position.character)
        resolve_template_location(uri, template_ref)
      end
    end

    # Find a template reference at the given character position in the line
    private def find_template_reference(line : String, char_pos : Int32) : TemplateReference?
      # Match extends/include/import/from patterns with quoted strings
      patterns = [
        # {% extends "path" %}
        /\{%\s*extends\s+["']([^"']+)["']/,
        # {% include "path" %}
        /\{%\s*include\s+["']([^"']+)["']/,
        # {% import "path" %}
        /\{%\s*import\s+["']([^"']+)["']/,
        # {% from "path" import ... %}
        /\{%\s*from\s+["']([^"']+)["']\s+import/,
      ]

      patterns.each do |pattern|
        if match = line.match(pattern)
          # Get the full match and the captured path
          full_match = match[0]
          path = match[1]

          # Find the position of the path in the line
          match_start = line.index(full_match)
          next unless match_start

          # Find where the quoted string starts within the match
          quote_start = full_match.index('"') || full_match.index('\'')
          next unless quote_start

          path_start = match_start + quote_start + 1
          path_end = path_start + path.size

          # Check if cursor is within the path
          if char_pos >= path_start && char_pos <= path_end
            return TemplateReference.new(path, path_start, path_end)
          end
        end
      end

      nil
    end

    # Resolve a template path to a file location
    private def resolve_template_location(current_uri : String, ref : TemplateReference) : Location?
      # Try to resolve the template path
      resolved_path = resolve_template_path(current_uri, ref.path)
      return unless resolved_path

      # Check if file exists
      return unless File.exists?(resolved_path)

      # Create location pointing to the start of the file
      Location.new(
        uri: path_to_uri(resolved_path),
        range: Range.new(
          start: Position.new(line: 0, character: 0),
          end_pos: Position.new(line: 0, character: 0)
        )
      )
    end

    # Resolve a template path relative to the current template or root
    private def resolve_template_path(current_uri : String, template_path : String) : String?
      # First try relative to current template's directory
      if current_uri.starts_with?("file://")
        current_path = current_uri.sub(/^file:\/\//, "")
        current_dir = File.dirname(current_path)
        relative_path = File.join(current_dir, template_path)
        return relative_path if File.exists?(relative_path)
      end

      # Try relative to root path
      if root = @root_path
        root_relative = File.join(root, template_path)
        return root_relative if File.exists?(root_relative)

        # Try in common template directories
        ["templates", "views", ""].each do |subdir|
          candidate = File.join(root, subdir, template_path)
          return candidate if File.exists?(candidate)
        end
      end

      nil
    end

    # Convert a file path to a file:// URI
    private def path_to_uri(path : String) : String
      # Ensure absolute path
      abs_path = File.expand_path(path)
      "file://#{abs_path}"
    end
  end

  # Represents a template reference found in the source
  private struct TemplateReference
    property path : String
    property start_pos : Int32
    property end_pos : Int32

    def initialize(@path : String, @start_pos : Int32, @end_pos : Int32) : Nil
    end
  end
end
