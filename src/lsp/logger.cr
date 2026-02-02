module Crinkle::LSP
  # Simple file-based logger for LSP debugging.
  # Logs to a file since stdout is used for LSP communication.
  class Logger
    enum Level
      Debug
      Info
      Warning
      Error
    end

    @io : IO
    @level : Level
    @mutex : Mutex

    def initialize(@io : IO, @level : Level = Level::Info) : Nil
      @mutex = Mutex.new
    end

    def self.file(path : String, level : Level = Level::Info) : Logger
      io = File.open(path, "a")
      new(io, level)
    end

    def self.stderr(level : Level = Level::Info) : Logger
      new(STDERR, level)
    end

    def debug(message : String) : Nil
      log(Level::Debug, message)
    end

    def info(message : String) : Nil
      log(Level::Info, message)
    end

    def warning(message : String) : Nil
      log(Level::Warning, message)
    end

    def error(message : String) : Nil
      log(Level::Error, message)
    end

    def close : Nil
      @io.close unless @io == STDERR
    end

    private def log(level : Level, message : String) : Nil
      return if level.value < @level.value

      @mutex.synchronize do
        timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S.%3N")
        @io.puts("[#{timestamp}] [#{level}] #{message}")
        @io.flush
      end
    end
  end
end
