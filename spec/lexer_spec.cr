require "./spec_helper"

private def lex_file(path : String) : {Array(Crinkle::Token), Array(Crinkle::Diagnostic)}
  source = File.read(path)
  lexer = Crinkle::Lexer.new(source)
  tokens = lexer.lex_all
  {tokens, lexer.diagnostics}
end

describe Crinkle::Lexer do
  it "lexes a simple variable expression" do
    tokens, diagnostics = lex_file("fixtures/lexer/var_only.html.j2")
    diagnostics.should be_empty

    types = tokens.map(&.type)
    types.should contain(Crinkle::TokenType::VarStart)
    types.should contain(Crinkle::TokenType::Identifier)
    types.should contain(Crinkle::TokenType::VarEnd)
    types.last.should eq(Crinkle::TokenType::EOF)
  end

  it "emits diagnostics for unterminated expressions" do
    tokens, diagnostics = lex_file("fixtures/lexer/bad_delimiter.html.j2")
    tokens.last.type.should eq(Crinkle::TokenType::EOF)
    diagnostics.any?(&.type.unterminated_expression?).should be_true
  end
end
