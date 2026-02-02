require "../crinkle"
require "../lsp/lsp"
require "option_parser"
require "json"

module Crinkle
  module CLI
    enum OutputFormat
      Json
      Text
      Html
      Dot
    end

    struct Options
      property? stdin : Bool
      property path : String?
      property paths : Array(String)
      property format : OutputFormat
      property? pretty : Bool
      property? no_color : Bool
      property? strict : Bool
      property max_errors : Int32?
      property snapshots_dir : String?

      def initialize(
        @stdin : Bool = false,
        @path : String? = nil,
        @paths : Array(String) = Array(String).new,
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
        sources = read_sources(opts, allow_multiple: false)
        source, label = sources.first
        tokens, diagnostics = lex_source(source)
        write_snapshots(opts.snapshots_dir, label, tokens: tokens, diagnostics: diagnostics)
        exit_with = emit_tokens_and_diagnostics(tokens, diagnostics, opts, label)
        exit exit_with
      when "parse"
        opts = parse_options(args, default_format: OutputFormat::Json)
        sources = read_sources(opts, allow_multiple: false)
        source, label = sources.first
        tokens, diagnostics = lex_source(source)
        template, parser_diags = parse_tokens(tokens)
        all_diags = diagnostics + parser_diags
        write_snapshots(opts.snapshots_dir, label, ast: template, diagnostics: all_diags)
        exit_with = emit_ast_and_diagnostics(template, all_diags, opts, label)
        exit exit_with
      when "render"
        opts = parse_options(args, default_format: OutputFormat::Text)
        sources = read_sources(opts, allow_multiple: false)
        source, label = sources.first
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
        sources = read_sources(opts, allow_multiple: true)
        if sources.size == 1 && opts.paths.empty? && opts.format != OutputFormat::Dot
          source, label = sources.first
          html_aware = Formatter.html_aware?(label)
          formatter_options = Formatter::Options.new(html_aware: html_aware, normalize_text_indent: html_aware)
          formatter = Formatter.new(source, formatter_options)
          output = formatter.format
          all_diags = formatter.diagnostics
          write_snapshots(opts.snapshots_dir, label, output: output, diagnostics: all_diags, output_ext: "j2")
          exit_with = emit_output_and_diagnostics(output, all_diags, opts, label)
          exit exit_with
        else
          results = Array(Tuple(String, Array(Diagnostic))).new
          all_diags = Array(Diagnostic).new
          sources.each do |entry_source, entry_label|
            html_aware = Formatter.html_aware?(entry_label)
            formatter_options = Formatter::Options.new(html_aware: html_aware, normalize_text_indent: html_aware)
            formatter = Formatter.new(entry_source, formatter_options)
            output = formatter.format
            File.write(entry_label, output) unless entry_label == "stdin"
            results << {entry_label, formatter.diagnostics}
            all_diags.concat(formatter.diagnostics)
            write_snapshots(opts.snapshots_dir, entry_label, output: output, diagnostics: formatter.diagnostics, output_ext: "j2")
          end
          emit_format_diagnostics_results(results, opts)
          exit exit_code(all_diags, opts)
        end
      when "lint"
        opts = parse_options(args, default_format: OutputFormat::Json)
        sources = read_sources(opts, allow_multiple: true)
        results = Array(Tuple(String, Array(Linter::Issue))).new
        all_issues = Array(Linter::Issue).new
        sources.each do |entry_source, entry_label|
          formatter = Formatter.new(entry_source)
          formatter.format
          tokens, _diagnostics = lex_source(entry_source)
          template, _parser_diags = parse_tokens(tokens)
          all_diags = formatter.diagnostics
          issues = Linter::Runner.new.lint(template, entry_source, all_diags)
          results << {entry_label, issues}
          all_issues.concat(issues)
          write_snapshots(opts.snapshots_dir, entry_label, issues: issues)
        end
        emit_issues_results(results, opts)
        exit exit_code_for_issues(all_issues, opts)
      when "lsp"
        exit LSP.run(args)
      when "schema"
        opts = parse_options(args, default_format: OutputFormat::Json)
        emit_schema(opts)
        exit 0
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
        Usage: crinkle <command> [path ...] [--stdin] [options]

        Commands:
          lex      Lex template and output tokens + diagnostics
          parse    Parse template and output AST + diagnostics
          render   Render template and output result + diagnostics
          format   Format template and output formatted source
          lint     Lint template and output diagnostics
          lsp      Start the Language Server Protocol server
          schema   Output schema of registered filters/tests/functions

        Options:
          --stdin                Read from stdin instead of file path
          --format json|text|html|dot Output format (default varies by command)
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

      opts.paths = args
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
      when "dot"
        OutputFormat::Dot
      else
        STDERR.puts "Unknown format '#{value}'."
        exit 2
      end
    end

    private def self.read_sources(opts : Options, allow_multiple : Bool) : Array(Tuple(String, String))
      if opts.stdin? && !opts.paths.empty?
        STDERR.puts "Specify either paths or --stdin, not both."
        exit 2
      end

      if opts.stdin?
        return [{STDIN.gets_to_end, "stdin"}]
      end

      if opts.paths.empty?
        default_paths = Dir.glob("**/*.j2").sort
        if default_paths.empty?
          STDERR.puts "No .j2 files found. Provide paths or use --stdin."
          exit 2
        end
        opts.paths = default_paths
      end

      unless allow_multiple
        if opts.paths.size > 1
          STDERR.puts "Too many positional arguments."
          exit 2
        end
      end

      opts.paths.map { |path| {File.read(path), path} }
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

    private def self.emit_issues_results(results : Array(Tuple(String, Array(Linter::Issue))), opts : Options) : Nil
      case opts.format
      when OutputFormat::Json
        files = results.map do |label, issues|
          {
            "path"        => JSON.parse(label.to_json),
            "diagnostics" => issues_to_json(issues, opts),
          }
        end
        print_json({"files" => JSON.parse(files.to_json)}, opts)
      when OutputFormat::Dot
        emit_dot_results_for_issues(results, opts)
      else
        results.each do |label, issues|
          print_issues(issues, opts, label)
        end
      end
    end

    private def self.emit_schema(opts : Options) : Nil
      case opts.format
      when OutputFormat::Json
        if opts.pretty?
          STDOUT.puts(Crinkle::Schema.to_pretty_json)
        else
          STDOUT.puts(Crinkle::Schema.to_json)
        end
      else
        # Text format - human readable
        registry = Crinkle::Schema.registry
        STDOUT.puts("Crinkle Schema v#{Crinkle::Schema::VERSION}")
        STDOUT.puts

        unless registry.filters.empty?
          STDOUT.puts("Filters (#{registry.filters.size}):")
          registry.filters.each do |filter_name, schema|
            params_str = schema.params.map { |param| "#{param.name}: #{param.type}#{param.required? ? "" : "?"}" }.join(", ")
            STDOUT.puts("  #{filter_name}(#{params_str}) -> #{schema.returns}")
            STDOUT.puts("    #{schema.doc}") if schema.doc
          end
          STDOUT.puts
        end

        unless registry.tests.empty?
          STDOUT.puts("Tests (#{registry.tests.size}):")
          registry.tests.each do |test_name, schema|
            params_str = schema.params.map { |param| "#{param.name}: #{param.type}#{param.required? ? "" : "?"}" }.join(", ")
            STDOUT.puts("  #{test_name}(#{params_str})")
            STDOUT.puts("    #{schema.doc}") if schema.doc
          end
          STDOUT.puts
        end

        unless registry.functions.empty?
          STDOUT.puts("Functions (#{registry.functions.size}):")
          registry.functions.each do |func_name, schema|
            params_str = schema.params.map { |param| "#{param.name}: #{param.type}#{param.required? ? "" : "?"}" }.join(", ")
            STDOUT.puts("  #{func_name}(#{params_str}) -> #{schema.returns}")
            STDOUT.puts("    #{schema.doc}") if schema.doc
          end
          STDOUT.puts
        end

        unless registry.callables.empty?
          STDOUT.puts("Callables (#{registry.callables.size}):")
          registry.callables.each do |_name, schema|
            STDOUT.puts("  #{schema.class_name}:")
            if dc = schema.default_call
              params_str = dc.params.map { |param| "#{param.name}: #{param.type}#{param.required? ? "" : "?"}" }.join(", ")
              STDOUT.puts("    __call__(#{params_str}) -> #{dc.returns}")
            end
            schema.methods.each do |method_name, method_schema|
              params_str = method_schema.params.map { |param| "#{param.name}: #{param.type}#{param.required? ? "" : "?"}" }.join(", ")
              STDOUT.puts("    #{method_name}(#{params_str}) -> #{method_schema.returns}")
              STDOUT.puts("      #{method_schema.doc}") if method_schema.doc
            end
          end
        end
      end
    end

    private def self.emit_format_diagnostics_results(results : Array(Tuple(String, Array(Diagnostic))), opts : Options) : Nil
      case opts.format
      when OutputFormat::Json
        files = results.map do |label, diags|
          {
            "path"        => JSON.parse(label.to_json),
            "diagnostics" => diagnostics_to_json(diags, opts),
          }
        end
        print_json({"files" => JSON.parse(files.to_json)}, opts)
      when OutputFormat::Dot
        emit_dot_results_for_diagnostics(results, opts)
      else
        results.each do |label, diags|
          print_diagnostics(diags, opts, label)
        end
      end
    end

    private def self.emit_dot_results_for_issues(
      results : Array(Tuple(String, Array(Linter::Issue))),
      opts : Options,
    ) : Nil
      started_at = Time.instant
      total = results.size
      STDOUT.puts(dot_started_message(total))
      STDOUT.puts

      failures = 0
      results.each do |_label, issues|
        if issues.empty?
          STDOUT << "."
        else
          STDOUT << "F"
          failures += issues.size
        end
      end

      STDOUT << "\n\n"

      results.each do |label, issues|
        next if issues.empty?
        print_issues(issues, opts, label)
        STDOUT.puts
      end

      STDOUT.puts(dot_finished_message(started_at, Time.instant))
      STDOUT.puts(dot_summary_message(total, failures))
    end

    private def self.emit_dot_results_for_diagnostics(
      results : Array(Tuple(String, Array(Diagnostic))),
      opts : Options,
    ) : Nil
      started_at = Time.instant
      total = results.size
      STDOUT.puts(dot_started_message(total))
      STDOUT.puts

      failures = 0
      results.each do |_label, diags|
        if diags.empty?
          STDOUT << "."
        else
          STDOUT << "F"
          failures += diags.size
        end
      end

      STDOUT << "\n\n"

      results.each do |label, diags|
        next if diags.empty?
        print_diagnostics(diags, opts, label)
        STDOUT.puts
      end

      STDOUT.puts(dot_finished_message(started_at, Time.instant))
      STDOUT.puts(dot_summary_message(total, failures))
    end

    private def self.dot_started_message(total : Int32) : String
      "Inspecting #{total} #{pluralize(total, "file")}"
    end

    private def self.dot_finished_message(started_at : Time::Instant, finished_at : Time::Instant) : String
      "Finished in #{to_human_duration(finished_at - started_at)}"
    end

    private def self.dot_summary_message(total : Int32, failures : Int32) : String
      "#{total} inspected, #{failures} #{pluralize(failures, "failure")}"
    end

    private def self.pluralize(count : Int32, word : String) : String
      count == 1 ? word : "#{word}s"
    end

    private def self.to_human_duration(span : Time::Span) : String
      seconds = span.total_seconds
      if seconds < 1
        "#{(seconds * 1000).round(2)}ms"
      elsif seconds < 60
        "#{seconds.round(2)}s"
      else
        minutes = (seconds / 60).floor
        remaining = (seconds - minutes * 60).round(2)
        "#{minutes}m#{remaining}s"
      end
    end

    private def self.print_json(payload : Hash(String, JSON::Any), opts : Options) : Nil
      output = opts.pretty? ? payload.to_pretty_json : payload.to_json
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

    private def self.span_to_json(span : Span) : Hash(String, Hash(String, Int32))
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
      return 1 if opts.strict? && diags.any?(&.severity.warning?)
      0
    end

    private def self.exit_code_for_issues(issues : Array(Linter::Issue), opts : Options) : Int32
      return 1 if issues.any?(&.severity.error?)
      return 1 if opts.strict? && issues.any?(&.severity.warning?)
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

Crinkle::CLI.run(ARGV)
