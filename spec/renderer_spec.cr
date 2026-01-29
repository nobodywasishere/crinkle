require "./spec_helper"

private def build_environment : Jinja::Environment
  env = Jinja::Environment.new

  env.register_filter("upper") do |value, _args, _kwargs|
    value.to_s.upcase
  end

  env.register_test("lower") do |value, _args, _kwargs|
    str = value.to_s
    !str.empty? && str == str.downcase
  end

  env.register_function("greet") do |args, _kwargs|
    name = args.first?.to_s
    "Hello #{name}"
  end

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

  env.set_loader do |name|
    path = File.join("fixtures", "templates", name)
    File.read(path) if File.exists?(path)
  end

  env
end

private def render_context : Hash(String, Jinja::Value)
  context = Hash(String, Jinja::Value).new
  context["name"] = "Ada"
  context["flag_true"] = true
  context["flag_false"] = false
  context["items"] = [1_i64, 2_i64] of Jinja::Value
  context["empty_items"] = Array(Jinja::Value).new
  context["count"] = 1_i64
  context["lower_name"] = "ada"
  context["pairs"] = [[1_i64, 2_i64] of Jinja::Value, [3_i64, 4_i64] of Jinja::Value] of Jinja::Value
  context["user"] = {"name" => "Ada"} of String => Jinja::Value
  context
end

describe "Jinja renderer" do
  env = build_environment
  context = render_context

  Dir.glob("fixtures/templates/*.j2").each do |path|
    name = File.basename(path, ".j2")

    it "renders #{name}" do
      source = File.read(path)
      lexer = Jinja::Lexer.new(source)
      tokens = lexer.lex_all

      parser = Jinja::Parser.new(tokens, env)
      template = parser.parse

      renderer = Jinja::Renderer.new(env)
      renderer.register_tag_renderer("note") do |render, tag|
        label_value = tag.args.first? ? render.evaluate(tag.args.first) : "note"
        label = label_value.to_s
        "[#{label}]#{render.render_fragment(tag.body)}[/#{label}]"
      end
      output = renderer.render(template, context)

      assert_text_snapshot("fixtures/render_output/#{name}.html", output)
      assert_diagnostics_snapshot(
        "fixtures/render_diagnostics/#{name}.json",
        renderer.diagnostics
      )
    end
  end
end
