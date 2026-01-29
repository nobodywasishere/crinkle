require "./spec_helper"

private def build_environment : Jinja::Environment
  env = Jinja::Environment.new

  env.register_filter("upper") do |value, _args, _kwargs|
    value.to_s.upcase
  end

  env.register_filter("trim") do |value, _args, _kwargs|
    value.to_s.strip
  end

  env.register_filter("join") do |value, args, _kwargs|
    sep = args.first?.to_s
    case value
    when Array
      value.map(&.to_s).join(sep)
    else
      value.to_s
    end
  end

  env.register_filter("default") do |value, args, _kwargs|
    fallback = args.first?
    if value.nil? || (value.is_a?(String) && value.empty?)
      fallback
    else
      value
    end
  end

  env.register_filter("escape") do |value, _args, _kwargs|
    value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end

  env.register_filter("length") do |value, _args, _kwargs|
    case value
    when Array  then value.size.to_i64
    when Hash   then value.size.to_i64
    when String then value.size.to_i64
    else             0_i64
    end
  end

  env.register_filter("if") do |value, args, _kwargs|
    condition = args.first?
    condition == true ? value : ""
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
    body, end_info, _end_tag = parser.parse_until_any_end_tag(["endnote"], allow_end_name: true)
    body_end = end_info ? end_info.span : end_span

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
  context["outer"] = true
  context["inner"] = true
  context["items"] = [1_i64, 2_i64] of Jinja::Value
  context["empty_items"] = Array(Jinja::Value).new
  context["count"] = 1_i64
  context["lower_name"] = "ada"
  context["pairs"] = [[1_i64, 2_i64] of Jinja::Value, [3_i64, 4_i64] of Jinja::Value] of Jinja::Value
  context["user"] = {"name" => "Ada", "profile" => {"avatar" => "avatar.png"} of String => Jinja::Value} of String => Jinja::Value

  # Format template variables
  context["title"] = "Page Title"
  context["heading"] = "Welcome"
  context["content"] = "This is the content."
  context["show_header"] = true
  context["menu"] = [
    {"url" => "/home", "name" => "Home"} of String => Jinja::Value,
    {"url" => "/about", "name" => "About"} of String => Jinja::Value,
  ] of Jinja::Value
  context["show_code"] = true
  context["inline_code"] = "x = 1"
  context["json_value"] = 42_i64
  context["debug"] = true
  context["image_url"] = "/img/photo.jpg"
  context["alt_text"] = "A photo"
  context["default_value"] = "Enter text"
  context["show_meta"] = true
  context["description"] = "Page description"
  context["fallback_image"] = "/img/default.png"
  context["data"] = {"key" => {"nested" => "value"} of String => Jinja::Value} of String => Jinja::Value
  context["a"] = 1_i64
  context["b"] = 2_i64
  context["c"] = 5_i64
  context["d"] = 3_i64
  context["is_active"] = true
  context["has_permission"] = true
  context["condition"] = true
  context["value"] = "test value"
  context["single_item"] = "item"
  context["item"] = {"value" => "Item Value", "active" => true} of String => Jinja::Value
  context["copyright"] = "2024 Company"
  context["dict"] = Hash(String, Jinja::Value).new
  context["x"] = 42_i64
  context["greeting"] = "Hello"
  context["required"] = false

  # Common test variables
  context["foo"] = "foo_value"
  context["bar"] = "bar_value"
  context["baz"] = "baz_value"
  context["enabled"] = true

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
