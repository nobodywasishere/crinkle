require "./spec_helper"

describe "Crinkle renderer" do
  it "renders a simple template" do
    env = build_render_environment
    context = render_context
    source = "Hello {{ name }}"
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens, env)
    template = parser.parse

    renderer = Crinkle::Renderer.new(env)
    output = renderer.render(template, context)
    output.should eq("Hello Ada")
  end
end
