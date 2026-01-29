require "./spec_helper"

describe Crinkle::Parser do
  it "parses a basic template" do
    source = File.read("fixtures/var_only.html.j2")
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens)
    parser.parse
    parser.diagnostics.should be_empty
  end
end
