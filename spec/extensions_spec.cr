require "spec"
require "./spec_helper"
require "json"

private def build_environment : Jinja::Environment
  env = Jinja::Environment.new

  env.register_tag("note", ["endnote"]) do |parser, start_span|
    parser.skip_whitespace_for_extension
    args = Array(Jinja::AST::Expr).new

    unless parser.current_token_for_extension.type == Jinja::TokenType::BlockEnd
      args << parser.parse_expression_for_extension([Jinja::TokenType::BlockEnd])
      parser.skip_whitespace_for_extension
    end

    end_span = parser.expect_block_end_for_extension("Expected '%}' to close note tag.")
    body, body_end = parser.parse_until_end_tag_for_extension("endnote", allow_end_name: true)
    body_end ||= end_span

    Jinja::AST::CustomTag.new(
      "note",
      args,
      Array(Jinja::AST::KeywordArg).new,
      body,
      parser.span_between_for_extension(start_span, body_end)
    )
  end

  env.register_tag("shout") do |parser, start_span|
    parser.skip_whitespace_for_extension
    args = Array(Jinja::AST::Expr).new

    unless parser.current_token_for_extension.type == Jinja::TokenType::BlockEnd
      args << parser.parse_expression_for_extension([Jinja::TokenType::BlockEnd])
      parser.skip_whitespace_for_extension
    end

    end_span = parser.expect_block_end_for_extension("Expected '%}' to close shout tag.")

    Jinja::AST::CustomTag.new(
      "shout",
      args,
      Array(Jinja::AST::KeywordArg).new,
      Array(Jinja::AST::Node).new,
      parser.span_between_for_extension(start_span, end_span)
    )
  end

  env
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

private def assert_snapshot(path : String, actual : JSON::Any) : Nil
  if File.exists?(path)
    expected = JSON.parse(File.read(path))
    if actual != expected
      File.write(path, actual.to_pretty_json)
      raise "Snapshot mismatch for #{path}. Updated snapshot."
    end
  else
    File.write(path, actual.to_pretty_json)
    raise "Snapshot missing for #{path}. Created snapshot."
  end
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
