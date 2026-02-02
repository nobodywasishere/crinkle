require "./protocol"
require "./logger"
require "./transport"
require "./document"
require "./server"

module Crinkle::LSP
  def self.run(args : Array(String)) : Int32
    log_file : String? = nil
    log_level = MessageType::Info

    args.each_with_index do |arg, i|
      case arg
      when "--log"
        log_file = args[i + 1]? if args[i + 1]?
      when "--log-level"
        if level = args[i + 1]?
          log_level = case level.downcase
                      when "debug"   then MessageType::Log
                      when "info"    then MessageType::Info
                      when "warning" then MessageType::Warning
                      when "error"   then MessageType::Error
                      else                MessageType::Info
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

    # Create file logger if specified (for debugging)
    file_logger : Logger? = nil
    if log_file
      file_log_level = case log_level
                       when .log?     then Logger::Level::Debug
                       when .info?    then Logger::Level::Info
                       when .warning? then Logger::Level::Warning
                       when .error?   then Logger::Level::Error
                       else                Logger::Level::Info
                       end
      file_logger = Logger.file(log_file, file_log_level)
    end

    transport = Transport.new(STDIN, STDOUT, file_logger)
    server = Server.new(transport, file_logger, log_level)

    exit_code = server.run

    file_logger.try(&.close)

    exit_code
  end

  def self.print_help : Nil
    STDERR.puts <<-HELP
      Usage: crinkle lsp [options]

      Start the Language Server Protocol server for Jinja2/Crinkle templates.

      Options:
        --log FILE           Log to file (for debugging)
        --log-level LEVEL    Log level: debug, info, warning, error (default: info)
        -h, --help           Show this help
        -v, --version        Show version
      HELP
  end
end
