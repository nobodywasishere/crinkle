require "./spec_helper"

private def register_base_renderers(renderer : Jinja::Renderer) : Nil
  renderer.register_tag_renderer("note") do |render, tag|
    label_value = tag.args.first? ? render.evaluate(tag.args.first) : "note"
    label = label_value.to_s
    "[#{label}]#{render.render_fragment(tag.body)}[/#{label}]"
  end
end

private def register_extension_renderers(renderer : Jinja::Renderer) : Nil
  renderer.register_tag_renderer("note") do |render, tag|
    label_value = tag.args.first? ? render.evaluate(tag.args.first) : "note"
    label = label_value.to_s
    "[#{label}]#{render.render_fragment(tag.body)}[/#{label}]"
  end

  renderer.register_tag_renderer("shout") do |render, tag|
    value = tag.args.first? ? render.evaluate(tag.args.first) : ""
    value.to_s.upcase
  end
end

private def run_fixture_snapshots(
  info : FixtureInfo,
  parser_env : Jinja::Environment?,
  render_env : Jinja::Environment?,
  context : Hash(String, Jinja::Value),
  register_renderers : Proc(Jinja::Renderer, Nil)?,
) : Nil
  source = File.read(info.path)
  lexer = Jinja::Lexer.new(source)
  tokens = lexer.lex_all

  parser = parser_env ? Jinja::Parser.new(tokens, parser_env) : Jinja::Parser.new(tokens)
  template = parser.parse
  ast_json = JSON.parse(Jinja::AST::Serializer.to_pretty_json(template))

  html_aware = Jinja::Formatter.html_aware?(info.template_ext)
  formatter_options = Jinja::Formatter::Options.new(html_aware: html_aware, normalize_text_indent: html_aware)
  formatter = Jinja::Formatter.new(source, formatter_options)
  formatted = formatter.format

  renderer_output = ""
  renderer_diags = Array(Jinja::Diagnostic).new
  if render_env
    render_parser = Jinja::Parser.new(tokens, render_env)
    render_template = render_parser.parse
    renderer = Jinja::Renderer.new(render_env)
    register_renderers.try &.call(renderer)
    renderer_output = renderer.render(render_template, context)
    renderer_diags = renderer.diagnostics
  end

  linter_issues = Array(Jinja::Linter::Issue).new
  if info.name.starts_with?("lint_")
    diagnostics = lexer.diagnostics + parser.diagnostics
    linter_issues = Jinja::Linter::Runner.new.lint(template, source, diagnostics)
  end

  assert_json_fixture(info.name, "lexer", "tokens", tokens_to_json(tokens), info.base_dir)
  assert_json_fixture(info.name, "parser", "ast", ast_json, info.base_dir)
  assert_text_fixture(info.name, "formatter", "output", formatted, info.template_ext, info.base_dir)
  if render_env
    assert_text_fixture(info.name, "renderer", "output", renderer_output, "txt", info.base_dir)
  end

  diagnostics_json = diagnostics_payload(
    lexer.diagnostics,
    parser.diagnostics,
    formatter.diagnostics,
    renderer_diags,
    linter_issues
  )
  diagnostics_path = fixture_path(info.name, "diagnostics", nil, "json", info.base_dir)
  if lexer.diagnostics.empty? && parser.diagnostics.empty? && formatter.diagnostics.empty? && renderer_diags.empty? && linter_issues.empty?
    File.delete(diagnostics_path) if File.exists?(diagnostics_path)
  else
    assert_snapshot(diagnostics_path, diagnostics_json)
  end
end

describe "fixture snapshots" do
  it "matches snapshots for main fixtures" do
    env = build_render_environment
    context = render_context
    fixture_templates.each do |info|
      run_fixture_snapshots(
        info,
        nil,
        env,
        context,
        ->(renderer : Jinja::Renderer) : Nil { register_base_renderers(renderer) }
      )
    end
  end

  it "matches snapshots for extension fixtures" do
    env = build_extensions_environment
    context = render_context
    fixture_templates("fixtures/extensions").each do |info|
      run_fixture_snapshots(
        info,
        env,
        env,
        context,
        ->(renderer : Jinja::Renderer) : Nil { register_extension_renderers(renderer) }
      )
    end
  end
end
