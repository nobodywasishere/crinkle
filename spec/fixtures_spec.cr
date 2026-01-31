require "./spec_helper"

private def register_base_renderers(renderer : Crinkle::Renderer) : Nil
  renderer.register_tag_renderer("note") do |render, tag|
    label_value = tag.args.first? ? render.evaluate(tag.args.first) : "note"
    label = label_value.to_s
    "[#{label}]#{render.render_fragment(tag.body)}[/#{label}]"
  end
end

private def register_extension_renderers(renderer : Crinkle::Renderer) : Nil
  register_base_renderers(renderer)
  renderer.register_tag_renderer("shout") do |render, tag|
    value = tag.args.first? ? render.evaluate(tag.args.first) : ""
    value.to_s.upcase
  end
end

private def run_fixture(info : FixtureInfo, env : Crinkle::Environment, context : Hash(String, Crinkle::Value), &register_renderers : Crinkle::Renderer -> Nil) : Nil
  source = File.read(info.path)
  lexer = Crinkle::Lexer.new(source)
  tokens = lexer.lex_all

  parser = Crinkle::Parser.new(tokens, env)
  template = parser.parse

  html_aware = Crinkle::Formatter.html_aware?(info.template_ext)
  formatter = Crinkle::Formatter.new(source, Crinkle::Formatter::Options.new(html_aware: html_aware, normalize_text_indent: html_aware))

  renderer = Crinkle::Renderer.new(env)
  register_renderers.call(renderer)
  renderer_output = renderer.render(template, context)

  linter_issues = Array(Crinkle::Linter::Issue).new
  if info.base_dir.includes?("linter")
    linter_issues = Crinkle::Linter::Runner.new.lint(template, source, lexer.diagnostics + parser.diagnostics)
  end

  assert_json_fixture(info.name, "lexer", "tokens", tokens_to_json(tokens), info.base_dir)
  assert_json_fixture(info.name, "parser", "ast", JSON.parse(Crinkle::AST::Serializer.to_pretty_json(template)), info.base_dir)
  assert_text_fixture(info.name, "formatter", "output", formatter.format, info.template_ext, info.base_dir)
  assert_text_fixture(info.name, "renderer", "output", renderer_output, "txt", info.base_dir)

  diags = diagnostics_payload(lexer.diagnostics, parser.diagnostics, formatter.diagnostics, renderer.diagnostics, linter_issues)
  path = fixture_path(info.name, "diagnostics", nil, "json", info.base_dir)
  if lexer.diagnostics.empty? && parser.diagnostics.empty? && formatter.diagnostics.empty? && renderer.diagnostics.empty? && linter_issues.empty?
    File.delete(path) if File.exists?(path)
  else
    assert_snapshot(path, diags)
  end
end

MAIN_FIXTURES = fixture_templates(recursive: true, exclude: ["extensions"])
EXT_FIXTURES  = fixture_templates("fixtures/extensions")
ENV_MAIN      = build_render_environment
ENV_EXT       = build_extensions_environment
CTX           = render_context

describe "fixtures" do
  MAIN_FIXTURES.each do |info|
    it info.path do
      run_fixture(info, ENV_MAIN, CTX) { |renderer| register_base_renderers(renderer) }
    end
  end

  EXT_FIXTURES.each do |info|
    it info.path do
      run_fixture(info, ENV_EXT, CTX) { |renderer| register_extension_renderers(renderer) }
    end
  end
end
