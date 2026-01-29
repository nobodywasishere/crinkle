require "./spec_helper"

private def lex_file(path : String) : {Array(Jinja::Token), Array(Jinja::Diagnostic)}
  source = File.read(path)
  lexer = Jinja::Lexer.new(source)
  tokens = lexer.lex_all
  {tokens, lexer.diagnostics}
end

describe Jinja::Lexer do
  it "lexes a simple variable expression" do
    tokens, diagnostics = lex_file("fixtures/templates/var_only.j2")
    diagnostics.should be_empty

    types = tokens.map(&.type)
    types.should contain(Jinja::TokenType::VarStart)
    types.should contain(Jinja::TokenType::Identifier)
    types.should contain(Jinja::TokenType::VarEnd)
    types.last.should eq(Jinja::TokenType::EOF)
  end

  it "emits diagnostics for unterminated expressions" do
    tokens, diagnostics = lex_file("fixtures/templates/bad_delimiter.j2")
    tokens.last.type.should eq(Jinja::TokenType::EOF)
    diagnostics.any?(&.type.unterminated_expression?).should be_true
  end

  Dir.glob("fixtures/templates/*.j2").each do |path|
    name = File.basename(path, ".j2")
    it "matches lexer snapshots for #{name}" do
      source = File.read(path)
      lexer = Jinja::Lexer.new(source)
      tokens = lexer.lex_all
      assert_snapshot("fixtures/lexer_tokens/#{name}.json", tokens_to_json(tokens))
      assert_snapshot("fixtures/lexer_diagnostics/#{name}.json", diagnostics_to_json(lexer.diagnostics))
    end
  end
end
