# Minimal CLI scaffold for Phase 1.
# Prints tokens and diagnostics from the lexer.

require "./jinja"

if ARGV.size != 1
  STDERR.puts "Usage: j2parse <template.j2>"
  exit 1
end

path = ARGV[0]
content = File.read(path)

lexer = Jinja::Lexer.new(content)
tokens = lexer.lex_all

puts "[phase1] Tokens:"
tokens.each do |token|
  puts "  #{token.type}: #{token.lexeme.inspect} @#{token.span.start_pos.line}:#{token.span.start_pos.column}"
end

if lexer.diagnostics.any?
  puts "[phase1] Diagnostics:"
  lexer.diagnostics.each do |diag|
    puts "  #{diag.id} (#{diag.severity}) at #{diag.span.start_pos.line}:#{diag.span.start_pos.column} - #{diag.message}"
  end
end
