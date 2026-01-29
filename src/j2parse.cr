# Minimal CLI scaffold for Phase 2.
# Prints tokens and diagnostics from the lexer and parser.

require "./jinja"

args = ARGV.dup
emit_ast = args.delete("--ast")
ext_name = nil

if ext_index = args.index("--ext")
  ext_name = args[ext_index + 1]?
  if ext_name.nil?
    STDERR.puts "Usage: j2parse [--ast] [--ext NAME] <template.j2>"
    exit 1
  end
  args.delete_at(ext_index + 1)
  args.delete_at(ext_index)
end

if args.size != 1
  STDERR.puts "Usage: j2parse [--ast] [--ext NAME] <template.j2>"
  exit 1
end

path = args[0]
content = File.read(path)

lexer = Jinja::Lexer.new(content)
tokens = lexer.lex_all

environment = Jinja::Environment.new
if ext_name == "demo"
  environment.register_tag("note", ["endnote"]) do |parser, start_span|
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
elsif ext_name
  STDERR.puts "Unknown extension set '#{ext_name}'."
  exit 1
end

parser = Jinja::Parser.new(tokens, environment)
template = parser.parse
all_diagnostics = lexer.diagnostics + parser.diagnostics

puts "[phase2] Tokens:"
tokens.each do |token|
  puts "  #{token.type}: #{token.lexeme.inspect} @#{token.span.start_pos.line}:#{token.span.start_pos.column}"
end

if emit_ast
  puts "[phase2] AST:"
  puts Jinja::AST::Serializer.to_pretty_json(template)
end

if all_diagnostics.present?
  puts "[phase2] Diagnostics:"
  all_diagnostics.each do |diag|
    puts "  #{diag.id} (#{diag.severity}) at #{diag.span.start_pos.line}:#{diag.span.start_pos.column} - #{diag.message}"
  end
end
