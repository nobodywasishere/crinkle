require "./spec_helper"

describe "Crinkle custom tags" do
  it "parses custom tags with extensions enabled" do
    env = build_extensions_environment
    source = File.read("fixtures/extensions/note_block.html.j2")
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens, env)
    parser.parse
    parser.diagnostics.should be_empty
  end
end
