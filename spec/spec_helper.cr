require "spec"
require "json"
require "yaml"
require "file_utils"
require "../src/crinkle"

record FixtureInfo, name : String, template_ext : String, path : String, base_dir : String

UPDATE_SNAPSHOTS = ENV["UPDATE_SNAPSHOTS"]? != nil

class AutoExample
  include Crinkle::Object::Auto

  @[Crinkle::Attribute]
  def name : String
    "Ada"
  end

  @[Crinkle::Attribute]
  def admin? : Bool
    true
  end

  def hidden : String
    "hidden"
  end
end

def tokens_to_json(tokens : Array(Crinkle::Token)) : JSON::Any
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

def diagnostics_to_json(diags : Array(Crinkle::Diagnostic)) : JSON::Any
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

def issues_to_json(issues : Array(Crinkle::Linter::Issue)) : JSON::Any
  payload = issues.map do |issue|
    {
      "id"       => issue.id,
      "severity" => issue.severity.to_s.downcase,
      "message"  => issue.message,
      "span"     => {
        "start" => {
          "offset" => issue.span.start_pos.offset,
          "line"   => issue.span.start_pos.line,
          "column" => issue.span.start_pos.column,
        },
        "end" => {
          "offset" => issue.span.end_pos.offset,
          "line"   => issue.span.end_pos.line,
          "column" => issue.span.end_pos.column,
        },
      },
    }
  end

  JSON.parse(payload.to_json)
end

def ensure_fixture_dir(path : String) : Nil
  dir = File.dirname(path)
  if !File.exists?(dir)
    FileUtils.mkdir_p(dir)
  end
end

def fixture_info(path : String) : FixtureInfo
  filename = File.basename(path)
  parts = filename.split(".")
  raise "Invalid fixture template name: #{filename}" unless parts.size == 3 && parts.last == "j2"

  name = parts.first
  template_ext = parts[1..].join(".")
  base_dir = File.dirname(path)
  FixtureInfo.new(name, template_ext, path, base_dir)
end

def fixture_templates(base_dir : String = "fixtures", recursive : Bool = false, exclude : Array(String) = Array(String).new) : Array(FixtureInfo)
  pattern = recursive ? File.join(base_dir, "**", "*.j2") : File.join(base_dir, "*.j2")
  Dir.glob(pattern).sort.compact_map do |path|
    # Skip excluded directories
    next if exclude.any? { |ex| path.includes?("/#{ex}/") }
    filename = File.basename(path)
    parts = filename.split(".")
    next unless parts.size == 3 && parts.last == "j2"
    fixture_info(path)
  end
end

def fixture_template_path(name : String, template_ext : String, base_dir : String = "fixtures") : String
  File.join(base_dir, "#{name}.#{template_ext}")
end

def fixture_path(name : String, pass_name : String, type : String? = nil, ext : String = "json", base_dir : String = "fixtures") : String
  suffix_parts = [pass_name, type].compact
  suffix = suffix_parts.empty? ? pass_name : suffix_parts.join(".")
  File.join(base_dir, "#{name}.#{suffix}.#{ext}")
end

def assert_json_fixture(name : String, pass_name : String, type : String, actual : JSON::Any, base_dir : String = "fixtures") : Nil
  path = fixture_path(name, pass_name, type, "json", base_dir)
  assert_snapshot(path, actual)
end

def assert_text_fixture(name : String, pass_name : String, type : String, actual : String, ext : String, base_dir : String = "fixtures") : Nil
  path = fixture_path(name, pass_name, type, ext, base_dir)
  assert_text_snapshot(path, actual)
end

def assert_snapshot(path : String, actual : JSON::Any) : Nil
  ensure_fixture_dir(path)
  if File.exists?(path)
    expected = JSON.parse(File.read(path))
    if actual != expected
      File.write(path, actual.to_pretty_json)
      if UPDATE_SNAPSHOTS
        STDERR.puts "WARNING: Snapshot mismatch for #{path}. Updated snapshot."
      else
        raise "Snapshot mismatch for #{path}. Updated snapshot."
      end
    end
  else
    File.write(path, actual.to_pretty_json)
    STDERR.puts "WARNING: Snapshot missing for #{path}. Created snapshot."
  end
end

def assert_text_snapshot(path : String, actual : String) : Nil
  ensure_fixture_dir(path)
  if actual.empty?
    File.delete(path) if File.exists?(path)
    return
  end

  if File.exists?(path)
    expected = File.read(path)
    if actual != expected
      File.write(path, actual)
      if UPDATE_SNAPSHOTS
        STDERR.puts "WARNING: Snapshot mismatch for #{path}. Updated snapshot."
      else
        raise "Snapshot mismatch for #{path}. Updated snapshot."
      end
    end
  else
    File.write(path, actual)
    STDERR.puts "WARNING: Snapshot missing for #{path}. Created snapshot."
  end
end

def diagnostics_payload(
  lexer : Array(Crinkle::Diagnostic),
  parser : Array(Crinkle::Diagnostic),
  formatter : Array(Crinkle::Diagnostic),
  renderer : Array(Crinkle::Diagnostic),
  linter : Array(Crinkle::Linter::Issue),
) : JSON::Any
  payload = {
    "lexer"     => diagnostics_to_json(lexer),
    "parser"    => diagnostics_to_json(parser),
    "formatter" => diagnostics_to_json(formatter),
    "renderer"  => diagnostics_to_json(renderer),
    "linter"    => issues_to_json(linter),
  }

  JSON.parse(payload.to_json)
end

def build_render_environment : Crinkle::Environment
  env = Crinkle::Environment.new

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
    args = Array(Crinkle::AST::Expr).new

    unless parser.current.type == Crinkle::TokenType::BlockEnd
      args << parser.parse_expression([Crinkle::TokenType::BlockEnd])
      parser.skip_whitespace
    end

    end_span = parser.expect_block_end("Expected '%}' to close note tag.")
    body, end_info, _end_tag = parser.parse_until_any_end_tag(["endnote"], allow_end_name: true)
    body_end = end_info ? end_info.span : end_span

    Crinkle::AST::CustomTag.new(
      "note",
      args,
      Array(Crinkle::AST::KeywordArg).new,
      body,
      parser.span_between(start_span, body_end)
    )
  end

  env.set_loader do |name|
    # Search for templates recursively in fixtures/
    found = Dir.glob(File.join("fixtures", "**", name)).first?
    found ? File.read(found) : nil
  end

  env
end

def build_extensions_environment : Crinkle::Environment
  env = Crinkle::Environment.new

  env.register_tag("note", ["endnote"]) do |parser, start_span|
    parser.skip_whitespace
    args = Array(Crinkle::AST::Expr).new

    unless parser.current.type == Crinkle::TokenType::BlockEnd
      args << parser.parse_expression([Crinkle::TokenType::BlockEnd])
      parser.skip_whitespace
    end

    end_span = parser.expect_block_end("Expected '%}' to close note tag.")
    body, end_info, _end_tag = parser.parse_until_any_end_tag(["endnote"], allow_end_name: true)
    body_end = end_info ? end_info.span : end_span

    Crinkle::AST::CustomTag.new(
      "note",
      args,
      Array(Crinkle::AST::KeywordArg).new,
      body,
      parser.span_between(start_span, body_end)
    )
  end

  env.register_tag("shout") do |parser, start_span|
    parser.skip_whitespace
    args = Array(Crinkle::AST::Expr).new

    unless parser.current.type == Crinkle::TokenType::BlockEnd
      args << parser.parse_expression([Crinkle::TokenType::BlockEnd])
      parser.skip_whitespace
    end

    end_span = parser.expect_block_end("Expected '%}' to close shout tag.")

    Crinkle::AST::CustomTag.new(
      "shout",
      args,
      Array(Crinkle::AST::KeywordArg).new,
      Array(Crinkle::AST::Node).new,
      parser.span_between(start_span, end_span)
    )
  end

  env.register_tag("recover", ["endrecover"]) do |parser, _start_span|
    parser.skip_whitespace
    parser.expect_block_end("Expected '%}' to close recover tag.")
    nil
  end

  env.set_loader do |name|
    # Search for templates in fixtures/extensions/ and recursively in fixtures/
    path = File.join("fixtures", "extensions", name)
    if File.exists?(path)
      File.read(path)
    else
      found = Dir.glob(File.join("fixtures", "**", name)).first?
      found ? File.read(found) : nil
    end
  end

  env
end

def render_context : Hash(String, Crinkle::Value)
  context = Hash(String, Crinkle::Value).new
  context["name"] = "Ada"
  context["flag_true"] = true
  context["flag_false"] = false
  context["outer"] = true
  context["inner"] = true
  context["items"] = [1_i64, 2_i64] of Crinkle::Value
  context["empty_items"] = Array(Crinkle::Value).new
  context["count"] = 1_i64
  context["lower_name"] = "ada"
  context["pairs"] = [[1_i64, 2_i64] of Crinkle::Value, [3_i64, 4_i64] of Crinkle::Value] of Crinkle::Value
  context["user"] = {"name" => "Ada", "profile" => {"avatar" => "avatar.png"} of String => Crinkle::Value} of String => Crinkle::Value

  # Format template variables
  context["title"] = "Page Title"
  context["heading"] = "Welcome"
  context["content"] = "This is the content."
  context["show_header"] = true
  context["menu"] = [
    {"url" => "/home", "name" => "Home"} of String => Crinkle::Value,
    {"url" => "/about", "name" => "About"} of String => Crinkle::Value,
  ] of Crinkle::Value
  context["show_code"] = true
  context["inline_code"] = "x = 1"
  context["json_value"] = 42_i64
  context["debug"] = true
  context["image_url"] = "/img/photo.jpg"
  context["alt_text"] = "A photo"
  context["default_value"] = "Enter text"
  context["safe_list"] = [
    Crinkle::SafeString.new("<b>one</b>"),
    "<b>two</b>",
  ] of Crinkle::Value
  context["notes"] = [
    {"title" => "Install", "details" => "Run `shards install`"} of String => Crinkle::Value,
    {"title" => "Build", "details" => "crystal build src/cli/cli.cr"} of String => Crinkle::Value,
    {"title" => "Deploy", "details" => nil} of String => Crinkle::Value,
  ] of Crinkle::Value
  context["show_meta"] = true
  context["description"] = "Page description"
  context["fallback_image"] = "/img/default.png"
  context["data"] = {"key" => {"nested" => "value"} of String => Crinkle::Value} of String => Crinkle::Value
  context["a"] = 1_i64
  context["b"] = 2_i64
  context["c"] = 5_i64
  context["d"] = 3_i64
  context["is_active"] = true
  context["has_permission"] = true
  context["condition"] = true
  context["value"] = "test value"
  context["single_item"] = "item"
  context["item"] = {"value" => "Item Value", "active" => true} of String => Crinkle::Value
  context["copyright"] = "2024 Company"
  context["dict"] = Hash(String, Crinkle::Value).new
  context["x"] = 42_i64
  context["greeting"] = "Hello"
  context["required"] = false
  context["auto_user"] = AutoExample.new
  context["safe_value"] = Crinkle::SafeString.new("<b>safe</b>")
  context["undefined_value"] = Crinkle::Undefined.new("missing")
  context["range_items"] = Crinkle.value(1..3)
  context["tuple_items"] = Crinkle.value({1, "two"})
  context["named_tuple_items"] = Crinkle.value({one: 1, two: "two"})
  context["json_any"] = JSON.parse(%({"name":"Ada","items":[1,2]}))
  context["yaml_any"] = YAML.parse("name: Ada\nitems:\n  - 1\n  - 2\n")

  # Common test variables
  context["foo"] = "foo_value"
  context["bar"] = "bar_value"
  context["baz"] = "baz_value"
  context["enabled"] = true

  context
end
