require "./spec_helper"

describe "Crinkle callable objects" do
  it "calls methods with basic arguments" do
    env = Crinkle::Environment.new
    context = Hash(String, Crinkle::Value).new
    context["ctx"] = TestContext.new

    source = "{{ ctx.localize(\"settings.title\") }}"
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens, env)
    template = parser.parse

    renderer = Crinkle::Renderer.new(env)
    output = renderer.render(template, context)
    output.should eq("Localized: settings.title")
  end

  it "calls methods with keyword arguments" do
    env = Crinkle::Environment.new
    context = Hash(String, Crinkle::Value).new
    context["ctx"] = TestContext.new

    source = "{{ ctx.translate(\"hello\", locale=\"es\") }}"
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens, env)
    template = parser.parse

    renderer = Crinkle::Renderer.new(env)
    output = renderer.render(template, context)
    output.should eq("[es] hello")
  end

  it "calls multiple methods on the same object" do
    env = Crinkle::Environment.new
    context = Hash(String, Crinkle::Value).new
    context["ctx"] = TestContext.new

    source = "{{ ctx.localize(\"app.title\") }}\n{{ ctx.flag(\"dark_mode\") }}"
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens, env)
    template = parser.parse

    renderer = Crinkle::Renderer.new(env)
    output = renderer.render(template, context)
    output.should eq("Localized: app.title\ntrue")
  end

  it "falls back to attribute access when method is not callable" do
    env = Crinkle::Environment.new
    context = Hash(String, Crinkle::Value).new
    context["ctx"] = TestContext.new

    source = "{{ ctx.name }}"
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens, env)
    template = parser.parse

    renderer = Crinkle::Renderer.new(env)
    output = renderer.render(template, context)
    output.should eq("TestApp")
  end

  it "handles callable with complex arguments" do
    env = Crinkle::Environment.new
    context = Hash(String, Crinkle::Value).new
    context["ctx"] = TestContext.new

    source = "{{ ctx.redirected(\"/home\", {\"status\": \"302\"}) }}"
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens, env)
    template = parser.parse

    renderer = Crinkle::Renderer.new(env)
    output = renderer.render(template, context)
    output.should eq("Redirect to /home (status: 302)")
  end
end
