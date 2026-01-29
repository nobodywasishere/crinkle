require "./spec_helper"

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

      assert_snapshot("fixtures/parser_ast/#{name}.json", ast_json)
      assert_diagnostics_snapshot("fixtures/parser_diagnostics/#{name}.json", all_diags)
    end
  end
end
