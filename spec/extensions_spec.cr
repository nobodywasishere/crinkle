require "./spec_helper"

describe "Jinja custom tags" do
  it "parses custom tags with extensions enabled" do
    env = build_extensions_environment
    source = File.read("fixtures/extensions/note_block.html.j2")
    lexer = Jinja::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Jinja::Parser.new(tokens, env)
    parser.parse
    parser.diagnostics.should be_empty
  end
end
