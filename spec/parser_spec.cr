require "./spec_helper"

describe Jinja::Parser do
  it "parses a basic template" do
    source = File.read("fixtures/var_only.html.j2")
    lexer = Jinja::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Jinja::Parser.new(tokens)
    parser.parse
    parser.diagnostics.should be_empty
  end
end
