# Minimal CLI scaffold for Phase 2.
# Prints tokens and diagnostics from the lexer and parser.

require "./jinja"

args = ARGV.dup
emit_ast = args.delete("--ast")

if args.size != 1
  STDERR.puts "Usage: j2parse [--ast] <template.j2>"
  exit 1
end

path = args[0]
content = File.read(path)

lexer = Jinja::Lexer.new(content)
tokens = lexer.lex_all
parser = Jinja::Parser.new(tokens)
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
