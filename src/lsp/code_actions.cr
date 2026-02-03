require "./protocol"
require "./inference"

module Crinkle::LSP
  # Provides code actions (quick fixes) for diagnostics
  class CodeActionProvider
    @inference : InferenceEngine

    def initialize(@inference : InferenceEngine) : Nil
    end

    # Get code actions for the given range and diagnostics
    def code_actions(uri : String, range : Range, context : CodeActionContext) : Array(CodeAction)
      actions = Array(CodeAction).new

      context.diagnostics.each do |diagnostic|
        # Track if we've handled this diagnostic via code
        handled = false

        # Extract diagnostic code if present
        code = diagnostic.code

        case code
        when String
          case code
          when "Inference/PossibleTypo"
            if action = typo_fix_action(uri, diagnostic)
              actions << action
              handled = true
            end
          end
        end

        # Only try to match by message patterns if not already handled by code
        next if handled

        message = diagnostic.message

        # Typo suggestions: "Did you mean 'X'?"
        if message.includes?("Did you mean")
          if action = typo_fix_from_message(uri, diagnostic)
            actions << action
          end
        end

        # Unclosed tag: "Expected '%}' to close..."
        if message.includes?("Expected '%}'") || message.includes?("unclosed")
          if action = close_tag_action(uri, diagnostic)
            actions << action
          end
        end
      end

      actions
    end

    # Create a code action to fix a typo
    private def typo_fix_action(uri : String, diagnostic : Diagnostic) : CodeAction?
      suggestion = extract_suggestion(diagnostic.message)
      return unless suggestion

      CodeAction.new(
        title: "Change to '#{suggestion}'",
        kind: CodeActionKind::QuickFix,
        diagnostics: [diagnostic],
        edit: WorkspaceEdit.new(
          changes: {uri => [TextEdit.new(range: diagnostic.range, new_text: suggestion)]}
        )
      )
    end

    # Create a code action from a "Did you mean" message
    private def typo_fix_from_message(uri : String, diagnostic : Diagnostic) : CodeAction?
      suggestion = extract_suggestion(diagnostic.message)
      return unless suggestion

      CodeAction.new(
        title: "Change to '#{suggestion}'",
        kind: CodeActionKind::QuickFix,
        diagnostics: [diagnostic],
        edit: WorkspaceEdit.new(
          changes: {uri => [TextEdit.new(range: diagnostic.range, new_text: suggestion)]}
        )
      )
    end

    # Create a code action to close an unclosed tag
    private def close_tag_action(uri : String, diagnostic : Diagnostic) : CodeAction?
      # The fix is to add "%}" at the end of the range
      # This is a simple heuristic - for more complex cases we'd need AST analysis
      fix_position = diagnostic.range.end_pos
      fix_range = Range.new(start: fix_position, end_pos: fix_position)

      CodeAction.new(
        title: "Add missing '%}'",
        kind: CodeActionKind::QuickFix,
        diagnostics: [diagnostic],
        edit: WorkspaceEdit.new(
          changes: {uri => [TextEdit.new(range: fix_range, new_text: " %}")]}
        )
      )
    end

    # Extract suggestion from "Did you mean 'X'?" message
    private def extract_suggestion(message : String) : String?
      # Match patterns like "Did you mean 'suggestion'?" or "did you mean `suggestion`?"
      if match = message.match(/[Dd]id you mean ['`]([^'`]+)['`]/)
        return match[1]
      end

      # Match patterns like "Perhaps you meant 'suggestion'"
      if match = message.match(/[Pp]erhaps you meant ['`]([^'`]+)['`]/)
        return match[1]
      end

      nil
    end
  end
end
