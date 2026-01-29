require "spec"
require "./spec_helper"
require "json"

private def lex_file(path : String)
  source = File.read(path)
  lexer = Jinja::Lexer.new(source)
  tokens = lexer.lex_all
  {tokens, lexer.diagnostics}
end

private def tokens_to_json(tokens : Array(Jinja::Token)) : JSON::Any
  payload = tokens.map do |token|
    {
      "type"   => token.type.to_s,
      "lexeme" => token.lexeme,
      "span"   => {
        "start" => {
          "offset" => token.span.start_pos.offset,
          "line"   => token.span.start_pos.line,
          "column" => token.span.start_pos.column,
        },
        "end" => {
          "offset" => token.span.end_pos.offset,
          "line"   => token.span.end_pos.line,
          "column" => token.span.end_pos.column,
        },
      },
    }
  end

  JSON.parse(payload.to_json)
end

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

      expected_tokens = JSON.parse(File.read("fixtures/lexer_tokens/#{name}.json"))
      expected_diags = JSON.parse(File.read("fixtures/lexer_diagnostics/#{name}.json"))

      tokens_to_json(tokens).should eq(expected_tokens)
      diagnostics_to_json(lexer.diagnostics).should eq(expected_diags)
    end
  end
end
