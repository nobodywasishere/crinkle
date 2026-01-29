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
      output = renderer.render(template, context)

      assert_text_snapshot("fixtures/render_output/#{name}.html", output)
      assert_snapshot(
        "fixtures/render_diagnostics/#{name}.json",
        diagnostics_to_json(renderer.diagnostics)
      )
    end
  end
end
