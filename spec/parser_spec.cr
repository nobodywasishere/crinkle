require "./spec_helper"

describe Crinkle::Parser do
  it "parses a basic template" do
    source = File.read("fixtures/lexer/var_only.html.j2")
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens)
    parser.parse
    parser.diagnostics.should be_empty
  end

  it "emits unknown-tag diagnostic in strict unknown tag mode" do
    source = "{% frobnicate 1 %}"
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    env = Crinkle::Environment.new(strict_unknown_tags: true)
    parser = Crinkle::Parser.new(tokens, env)
    ast = parser.parse

    ast.body.should be_empty
    parser.diagnostics.size.should eq(1)
    parser.diagnostics.first.type.should eq(Crinkle::DiagnosticType::UnknownTag)
    parser.diagnostics.first.message.should eq("Unknown tag 'frobnicate'.")
  end

  it "emits Crinja-style end-tag diagnostics in strict tag structure mode" do
    source = "{% endblock %}\n{% if true %}"
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    env = Crinkle::Environment.new(strict_tag_structure: true)
    parser = Crinkle::Parser.new(tokens, env)
    parser.parse

    parser.diagnostics.size.should eq(2)
    parser.diagnostics[0].type.should eq(Crinkle::DiagnosticType::UnexpectedEndTag)
    parser.diagnostics[0].message.should eq("End tag without start: endblock")
    parser.diagnostics[1].type.should eq(Crinkle::DiagnosticType::MissingEndTag)
    parser.diagnostics[1].message.should eq("Unclosed tag, missing: endif")
  end
end
