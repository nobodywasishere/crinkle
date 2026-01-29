require "json"
require "../src/jinja"

TEMPLATE_DIR = "fixtures/templates"
TOKENS_DIR   = "fixtures/lexer_tokens"
DIAGS_DIR    = "fixtures/lexer_diagnostics"

Dir.mkdir(TOKENS_DIR) unless Dir.exists?(TOKENS_DIR)
Dir.mkdir(DIAGS_DIR) unless Dir.exists?(DIAGS_DIR)

Dir.glob(File.join(TEMPLATE_DIR, "*.j2")).each do |path|
  name = File.basename(path, ".j2")
  source = File.read(path)
  lexer = Jinja::Lexer.new(source)
  tokens = lexer.lex_all

  tokens_json = JSON.build(indent: 2) do |json|
    json.array do
      tokens.each do |token|
        json.object do
          json.field "type", token.type.to_s
          json.field "lexeme", token.lexeme
          json.field "span" do
            json.object do
              json.field "start" do
                json.object do
                  json.field "offset", token.span.start_pos.offset
                  json.field "line", token.span.start_pos.line
                  json.field "column", token.span.start_pos.column
                end
              end
              json.field "end" do
                json.object do
                  json.field "offset", token.span.end_pos.offset
                  json.field "line", token.span.end_pos.line
                  json.field "column", token.span.end_pos.column
                end
              end
            end
          end
        end
      end
    end
  end

  diagnostics_json = JSON.build(indent: 2) do |json|
    json.array do
      lexer.diagnostics.each do |diag|
        json.object do
          json.field "id", diag.id
          json.field "severity", diag.severity.to_s.downcase
          json.field "message", diag.message
          json.field "span" do
            json.object do
              json.field "start" do
                json.object do
                  json.field "offset", diag.span.start_pos.offset
                  json.field "line", diag.span.start_pos.line
                  json.field "column", diag.span.start_pos.column
                end
              end
              json.field "end" do
                json.object do
                  json.field "offset", diag.span.end_pos.offset
                  json.field "line", diag.span.end_pos.line
                  json.field "column", diag.span.end_pos.column
                end
              end
            end
          end
        end
      end
    end
  end

  File.write(File.join(TOKENS_DIR, "#{name}.json"), tokens_json)
  File.write(File.join(DIAGS_DIR, "#{name}.json"), diagnostics_json)
end
