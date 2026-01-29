require "./types"

module Jinja
  module LSP
    module Mapper
      def self.to_lsp_diagnostics(diags : Array(Jinja::Diagnostic)) : Array(LSProtocol::Diagnostic)
        diags.map do |diag|
          LSProtocol::Diagnostic.new(
            diag.message,
            to_lsp_range(diag.span),
            diag.id,
            severity: to_lsp_severity(diag.severity),
            source: "jinja-cr",
          )
        end
      end

      def self.to_lsp_severity(severity : Jinja::Severity) : LSProtocol::DiagnosticSeverity
        case severity
        when Jinja::Severity::Error
          LSProtocol::DiagnosticSeverity::Error
        when Jinja::Severity::Warning
          LSProtocol::DiagnosticSeverity::Warning
        when Jinja::Severity::Info
          LSProtocol::DiagnosticSeverity::Information
        else
          LSProtocol::DiagnosticSeverity::Information
        end
      end

      def self.to_lsp_range(span : Jinja::Span) : LSProtocol::Range
        lsp_start = to_lsp_position(span.start_pos)
        lsp_end = to_lsp_position(span.end_pos)
        LSProtocol::Range.new(lsp_end, lsp_start)
      end

      def self.to_lsp_position(position : Jinja::Position) : LSProtocol::Position
        line = position.line - 1
        column = position.column - 1
        LSProtocol::Position.new(
          character: column < 0 ? 0_u32 : column.to_u32,
          line: line < 0 ? 0_u32 : line.to_u32,
        )
      end

      def self.foldable_range(span : Jinja::Span) : LSProtocol::FoldingRange?
        start_line = span.start_pos.line - 1
        end_line = span.end_pos.line - 1
        return if end_line <= start_line
        LSProtocol::FoldingRange.new(
          end_line < 0 ? 0_u32 : end_line.to_u32,
          start_line < 0 ? 0_u32 : start_line.to_u32,
        )
      end
    end
  end
end
