require "../jinja"
require "option_parser"
require "json"

module Jinja
  module CLI
    enum OutputFormat
      Json
      Text
      Html
    end

    struct Options
      property? stdin : Bool
      property path : String?
      property format : OutputFormat
      property? pretty : Bool
      property? no_color : Bool
      property? strict : Bool
      property max_errors : Int32?
      property snapshots_dir : String?

      def initialize(
        @stdin : Bool = false,
        @path : String? = nil,
        @format : OutputFormat = OutputFormat::Json,
        @pretty : Bool = false,
        @no_color : Bool = false,
        @strict : Bool = false,
        @max_errors : Int32? = nil,
        @snapshots_dir : String? = nil,
      ) : Nil
      end
    end

    def self.run(args : Array(String)) : Nil
      if args.empty?
        print_usage
        exit 2
      end

      command = args.shift
      case command
      when "lex"
        opts = parse_options(args, default_format: OutputFormat::Json)
        source, label = read_source(opts)
        tokens, diagnostics = lex_source(source)
        write_snapshots(opts.snapshots_dir, label, tokens: tokens, diagnostics: diagnostics)
        exit_with = emit_tokens_and_diagnostics(tokens, diagnostics, opts, label)
        exit exit_with
      when "parse"
        opts = parse_options(args, default_format: OutputFormat::Json)
        source, label = read_source(opts)
        tokens, diagnostics = lex_source(source)
        template, parser_diags = parse_tokens(tokens)
        all_diags = diagnostics + parser_diags
        write_snapshots(opts.snapshots_dir, label, ast: template, diagnostics: all_diags)
        exit_with = emit_ast_and_diagnostics(template, all_diags, opts, label)
        exit exit_with
      when "render"
        opts = parse_options(args, default_format: OutputFormat::Text)
        source, label = read_source(opts)
        tokens, diagnostics = lex_source(source)
        template, parser_diags = parse_tokens(tokens)
        renderer = Renderer.new
        output = renderer.render(template)
        all_diags = diagnostics + parser_diags + renderer.diagnostics
        write_snapshots(opts.snapshots_dir, label, output: output, diagnostics: all_diags, output_ext: "html")
        exit_with = emit_output_and_diagnostics(output, all_diags, opts, label)
        exit exit_with
      when "format"
        opts = parse_options(args, default_format: OutputFormat::Text)
        source, label = read_source(opts)
        formatter = Formatter.new(source)
        output = formatter.format
        write_snapshots(opts.snapshots_dir, label, output: output, output_ext: "j2")
        STDOUT.print(output)
        exit 0
      when "lint"
        opts = parse_options(args, default_format: OutputFormat::Json)
        source, label = read_source(opts)
        tokens, diagnostics = lex_source(source)
        template, parser_diags = parse_tokens(tokens)
        all_diags = diagnostics + parser_diags
        issues = Linter::Runner.new.lint(template, source, all_diags)
        write_snapshots(opts.snapshots_dir, label, issues: issues)
        exit_with = emit_issues(issues, opts, label)
        exit exit_with
      when "-h", "--help", "help"
        print_usage
        exit 0
      else
        STDERR.puts "Unknown command '#{command}'."
        print_usage
        exit 2
      end
    end

    private def self.print_usage : Nil
      STDERR.puts <<-USAGE
        Usage: jinja <command> [path] [--stdin] [options]

        Commands:
          lex      Lex template and output tokens + diagnostics
          parse    Parse template and output AST + diagnostics
          render   Render template and output result + diagnostics
          format   Format template and output formatted source
          lint     Lint template and output diagnostics

        Options:
          --stdin                Read from stdin instead of file path
          --format json|text|html Output format (default varies by command)
          --pretty               Pretty-print JSON
          --no-color             Disable ANSI colors in text output
          --strict               Treat warnings as errors
          --max-errors N         Cap reported diagnostics
          --snapshots-dir PATH   Write tokens/ast/diagnostics/output snapshots
        USAGE
    end

    private def self.parse_options(args : Array(String), default_format : OutputFormat) : Options
      opts = Options.new(format: default_format)
      parser = OptionParser.new
      parser.on("--stdin", "Read from stdin") { opts.stdin = true }
      parser.on("--format FORMAT", "Output format") do |value|
        opts.format = parse_format(value)
      end
      parser.on("--pretty", "Pretty JSON") { opts.pretty = true }
      parser.on("--no-color", "Disable colors") { opts.no_color = true }
      parser.on("--strict", "Treat warnings as errors") { opts.strict = true }
      parser.on("--max-errors N", "Limit diagnostics") { |value| opts.max_errors = value.to_i? }
      parser.on("--snapshots-dir PATH", "Write snapshots") { |value| opts.snapshots_dir = value }
      parser.on("-h", "--help", "Show help") do
        print_usage
        exit 0
      end

      parser.parse(args)

      if args.size > 1
        STDERR.puts "Too many positional arguments."
        exit 2
      end

      opts.path = args.first?
      opts
    end

    private def self.parse_format(value : String) : OutputFormat
      case value
      when "json"
        OutputFormat::Json
      when "text"
        OutputFormat::Text
      when "html"
        OutputFormat::Html
      else
        STDERR.puts "Unknown format '#{value}'."
        exit 2
      end
    end

    private def self.read_source(opts : Options) : {String, String}
      if opts.stdin && opts.path
        STDERR.puts "Specify either a path or --stdin, not both."
        exit 2
      end

      if path = opts.path
        {File.read(path), path}
      else
        {STDIN.gets_to_end, "stdin"}
      end
    end

    private def self.lex_source(source : String) : {Array(Token), Array(Diagnostic)}
      lexer = Lexer.new(source)
      tokens = lexer.lex_all
      {tokens, lexer.diagnostics}
    end

    private def self.parse_tokens(tokens : Array(Token)) : {AST::Template, Array(Diagnostic)}
      parser = Parser.new(tokens)
      template = parser.parse
      {template, parser.diagnostics}
    end

    private def self.emit_tokens_and_diagnostics(
      tokens : Array(Token),
      diagnostics : Array(Diagnostic),
      opts : Options,
      label : String,
    ) : Int32
      case opts.format
      when OutputFormat::Json
        payload = {
          "tokens"      => tokens_to_json(tokens),
          "diagnostics" => diagnostics_to_json(diagnostics, opts),
        }
        print_json(payload, opts)
      else
        tokens.each do |token|
          STDOUT.puts("#{token.type}: #{token.lexeme.inspect} @#{token.span.start_pos.line}:#{token.span.start_pos.column}")
        end
        print_diagnostics(diagnostics, opts, label)
      end
      exit_code(diagnostics, opts)
    end

    private def self.emit_ast_and_diagnostics(
      template : AST::Template,
      diagnostics : Array(Diagnostic),
      opts : Options,
      label : String,
    ) : Int32
      case opts.format
      when OutputFormat::Json
        payload = {
          "ast"         => JSON.parse(AST::Serializer.to_pretty_json(template)),
          "diagnostics" => diagnostics_to_json(diagnostics, opts),
        }
        print_json(payload, opts)
      else
        STDOUT.puts(AST::Serializer.to_pretty_json(template))
        print_diagnostics(diagnostics, opts, label)
      end
      exit_code(diagnostics, opts)
    end

    private def self.emit_output_and_diagnostics(
      output : String,
      diagnostics : Array(Diagnostic),
      opts : Options,
      label : String,
    ) : Int32
      case opts.format
      when OutputFormat::Json
        payload = {
          "output"      => JSON.parse(output.to_json),
          "diagnostics" => diagnostics_to_json(diagnostics, opts),
        }
        print_json(payload, opts)
      else
        STDOUT.print(output)
        print_diagnostics(diagnostics, opts, label)
      end
      exit_code(diagnostics, opts)
    end

    private def self.emit_issues(issues : Array(Linter::Issue), opts : Options, label : String) : Int32
      case opts.format
      when OutputFormat::Json
        payload = {
          "diagnostics" => issues_to_json(issues, opts),
        }
        print_json(payload, opts)
      else
        print_issues(issues, opts, label)
      end
      exit_code_for_issues(issues, opts)
    end

    private def self.print_json(payload : Hash(String, JSON::Any), opts : Options) : Nil
      output = opts.pretty ? payload.to_pretty_json : payload.to_json
      STDOUT.puts(output)
    end

    private def self.diagnostics_to_json(diags : Array(Diagnostic), opts : Options) : JSON::Any
      limited = limit_diagnostics(diags, opts.max_errors)
      payload = limited.map do |diag|
        {
          "id"       => diag.id,
          "severity" => diag.severity.to_s.downcase,
          "message"  => diag.message,
          "span"     => span_to_json(diag.span),
        }
      end
      JSON.parse(payload.to_json)
    end

    private def self.tokens_to_json(tokens : Array(Token)) : JSON::Any
      payload = tokens.map do |token|
        {
          "type"   => token.type.to_s,
          "lexeme" => token.lexeme,
          "span"   => span_to_json(token.span),
        }
      end
      JSON.parse(payload.to_json)
    end

    private def self.issues_to_json(issues : Array(Linter::Issue), opts : Options) : JSON::Any
      limited = limit_issues(issues, opts.max_errors)
      payload = limited.map do |issue|
        {
          "id"       => issue.id,
          "severity" => issue.severity.to_s.downcase,
          "message"  => issue.message,
          "span"     => span_to_json(issue.span),
        }
      end
      JSON.parse(payload.to_json)
    end

    private def self.span_to_json(span : Span) : Hash(String, JSON::Any)
      {
        "start" => {
          "offset" => span.start_pos.offset,
          "line"   => span.start_pos.line,
          "column" => span.start_pos.column,
        },
        "end" => {
          "offset" => span.end_pos.offset,
          "line"   => span.end_pos.line,
          "column" => span.end_pos.column,
        },
      }
    end

    private def self.print_diagnostics(diags : Array(Diagnostic), opts : Options, label : String) : Nil
      limit_diagnostics(diags, opts.max_errors).each do |diag|
        STDOUT.puts(format_diagnostic(diag, label, opts))
      end
    end

    private def self.print_issues(issues : Array(Linter::Issue), opts : Options, label : String) : Nil
      limit_issues(issues, opts.max_errors).each do |issue|
        STDOUT.puts(format_issue(issue, label, opts))
      end
    end

    private def self.format_diagnostic(diag : Diagnostic, label : String, opts : Options) : String
      location = "#{label}:#{diag.span.start_pos.line}:#{diag.span.start_pos.column}"
      "#{location}: #{diag.id} #{diag.message}"
    end

    private def self.format_issue(issue : Linter::Issue, label : String, _opts : Options) : String
      location = "#{label}:#{issue.span.start_pos.line}:#{issue.span.start_pos.column}"
      "#{location}: #{issue.id} #{issue.message}"
    end

    private def self.limit_diagnostics(diags : Array(Diagnostic), max : Int32?) : Array(Diagnostic)
      return diags unless max
      diags.first(max)
    end

    private def self.limit_issues(issues : Array(Linter::Issue), max : Int32?) : Array(Linter::Issue)
      return issues unless max
      issues.first(max)
    end

    private def self.exit_code(diags : Array(Diagnostic), opts : Options) : Int32
      return 1 if diags.any?(&.severity.error?)
      return 1 if opts.strict && diags.any?(&.severity.warning?)
      0
    end

    private def self.exit_code_for_issues(issues : Array(Linter::Issue), opts : Options) : Int32
      return 1 if issues.any?(&.severity.error?)
      return 1 if opts.strict && issues.any?(&.severity.warning?)
      0
    end

    private def self.write_snapshots(
      dir : String?,
      label : String,
      tokens : Array(Token)? = nil,
      ast : AST::Template? = nil,
      diagnostics : Array(Diagnostic)? = nil,
      issues : Array(Linter::Issue)? = nil,
      output : String? = nil,
      output_ext : String? = nil,
    ) : Nil
      return unless dir
      Dir.mkdir_p(dir)
      basename = File.basename(label, File.extname(label))

      if tokens
        File.write(File.join(dir, "#{basename}.tokens.json"), tokens_to_json(tokens).to_pretty_json)
      end

      if ast
        File.write(File.join(dir, "#{basename}.ast.json"), AST::Serializer.to_pretty_json(ast))
      end

      if diagnostics
        File.write(File.join(dir, "#{basename}.diagnostics.json"), diagnostics_to_json(diagnostics, Options.new(pretty: true)).to_pretty_json)
      end

      if issues
        File.write(File.join(dir, "#{basename}.lint.json"), issues_to_json(issues, Options.new(pretty: true)).to_pretty_json)
      end

      if output
        ext = output_ext || "txt"
        File.write(File.join(dir, "#{basename}.#{ext}"), output)
      end
    end
  end
end

Jinja::CLI.run(ARGV)
