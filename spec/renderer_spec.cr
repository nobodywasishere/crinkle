require "./spec_helper"

describe "Jinja renderer" do
  it "renders a simple template" do
    env = build_render_environment
    context = render_context
    source = "Hello {{ name }}"
    lexer = Jinja::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Jinja::Parser.new(tokens, env)
    template = parser.parse

    renderer = Jinja::Renderer.new(env)
    output = renderer.render(template, context)
    output.should eq("Hello Ada")
  end
end
