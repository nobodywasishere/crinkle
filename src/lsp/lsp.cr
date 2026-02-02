require "./protocol"
require "./logger"
require "./transport"
require "./document"
require "./server"

module Crinkle::LSP
  def self.run(args : Array(String)) : Int32
    log_file : String? = nil
    log_level = Logger::Level::Info

    args.each_with_index do |arg, i|
      case arg
      when "--log"
        log_file = args[i + 1]? if args[i + 1]?
      when "--log-level"
        if level = args[i + 1]?
          log_level = case level.downcase
                      when "debug"   then Logger::Level::Debug
                      when "info"    then Logger::Level::Info
                      when "warning" then Logger::Level::Warning
                      when "error"   then Logger::Level::Error
                      else                Logger::Level::Info
                      end
        end
      when "-h", "--help"
        print_help
        return 0
      when "-v", "--version"
        puts "crinkle lsp #{Server::VERSION}"
        return 0
      end
    end

    logger = log_file.try { |file| Logger.file(file, log_level) }

    transport = Transport.new(STDIN, STDOUT, logger)
    server = Server.new(transport, logger)

    exit_code = server.run

    logger.try(&.close)

    exit_code
  end

  def self.print_help : Nil
    STDERR.puts <<-HELP
      Usage: crinkle lsp [options]

      Start the Language Server Protocol server for Jinja2/Crinkle templates.

      Options:
        --log FILE           Log to file (default: no logging)
        --log-level LEVEL    Log level: debug, info, warning, error (default: info)
        -h, --help           Show this help
        -v, --version        Show version
      HELP
  end
end
