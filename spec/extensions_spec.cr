require "./spec_helper"

private def build_environment : Jinja::Environment
  env = Jinja::Environment.new

  env.register_tag("note", ["endnote"]) do |parser, start_span|
    parser.skip_whitespace
    args = Array(Jinja::AST::Expr).new

    unless parser.current.type == Jinja::TokenType::BlockEnd
      args << parser.parse_expression([Jinja::TokenType::BlockEnd])
      parser.skip_whitespace
    end

    end_span = parser.expect_block_end("Expected '%}' to close note tag.")
    body, body_end, _end_tag = parser.parse_until_any_end_tag(["endnote"], allow_end_name: true)
    body_end ||= end_span

    Jinja::AST::CustomTag.new(
      "note",
      args,
      Array(Jinja::AST::KeywordArg).new,
      body,
      parser.span_between(start_span, body_end)
    )
  end

  env.register_tag("shout") do |parser, start_span|
    parser.skip_whitespace
    args = Array(Jinja::AST::Expr).new

    unless parser.current.type == Jinja::TokenType::BlockEnd
      args << parser.parse_expression([Jinja::TokenType::BlockEnd])
      parser.skip_whitespace
    end

    end_span = parser.expect_block_end("Expected '%}' to close shout tag.")

    Jinja::AST::CustomTag.new(
      "shout",
      args,
      Array(Jinja::AST::KeywordArg).new,
      Array(Jinja::AST::Node).new,
      parser.span_between(start_span, end_span)
    )
  end

  env.register_tag("recover", ["endrecover"]) do |parser, _start_span|
    parser.skip_whitespace
    parser.expect_block_end("Expected '%}' to close recover tag.")
    nil
  end

  env
end

describe "Jinja custom tags" do
  env = build_environment

  Dir.glob("fixtures/extensions/templates/*.j2").each do |path|
    name = File.basename(path, ".j2")

    it "lexes and parses #{name} with extensions" do
      source = File.read(path)
      lexer = Jinja::Lexer.new(source)
      tokens = lexer.lex_all

      parser = Jinja::Parser.new(tokens, env)
      template = parser.parse

      ast_json = JSON.parse(Jinja::AST::Serializer.to_pretty_json(template))
      all_diags = lexer.diagnostics + parser.diagnostics
      diag_json = diagnostics_to_json(all_diags)

      assert_snapshot("fixtures/extensions/lexer_tokens/#{name}.json", tokens_to_json(tokens))
      assert_snapshot("fixtures/extensions/lexer_diagnostics/#{name}.json", diagnostics_to_json(lexer.diagnostics))
      assert_snapshot("fixtures/extensions/parser_ast/#{name}.json", ast_json)
      assert_snapshot("fixtures/extensions/parser_diagnostics/#{name}.json", diag_json)
    end
  end
end
