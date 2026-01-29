require "spec"
require "./spec_helper"
require "json"

private def diagnostics_to_json(diags : Array(Jinja::Diagnostic)) : JSON::Any
  payload = diags.map do |diag|
    {
      "id"       => diag.id,
      "severity" => diag.severity.to_s.downcase,
      "message"  => diag.message,
      "span"     => {
        "start" => {
          "offset" => diag.span.start_pos.offset,
          "line"   => diag.span.start_pos.line,
          "column" => diag.span.start_pos.column,
        },
        "end" => {
          "offset" => diag.span.end_pos.offset,
          "line"   => diag.span.end_pos.line,
          "column" => diag.span.end_pos.column,
        },
      },
    }
  end

  JSON.parse(payload.to_json)
end

private def assert_snapshot(path : String, actual : JSON::Any) : Nil
  if File.exists?(path)
    expected = JSON.parse(File.read(path))
    if actual != expected
      File.write(path, actual.to_pretty_json)
      raise "Snapshot mismatch for #{path}. Updated snapshot."
    end
  else
    File.write(path, actual.to_pretty_json)
    raise "Snapshot missing for #{path}. Created snapshot."
  end
end

describe Jinja::Parser do
  Dir.glob("fixtures/templates/*.j2").each do |path|
    name = File.basename(path, ".j2")

    it "parses #{name} and matches snapshots" do
      source = File.read(path)
      lexer = Jinja::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Jinja::Parser.new(tokens)
      template = parser.parse

      ast_json = JSON.parse(Jinja::AST::Serializer.to_pretty_json(template))
      all_diags = lexer.diagnostics + parser.diagnostics
      diag_json = diagnostics_to_json(all_diags)

      assert_snapshot("fixtures/parser_ast/#{name}.json", ast_json)
      assert_snapshot("fixtures/parser_diagnostics/#{name}.json", diag_json)
    end
  end
end
