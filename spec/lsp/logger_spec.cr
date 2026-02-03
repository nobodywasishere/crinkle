require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::Logger do
    it "logs to IO" do
      io = IO::Memory.new
      logger = Crinkle::LSP::Logger.new(io, Crinkle::LSP::Logger::Level::Debug)

      logger.debug("test debug")
      logger.info("test info")
      logger.warning("test warning")
      logger.error("test error")

      output = io.to_s
      output.should contain "test debug"
      output.should contain "test info"
      output.should contain "test warning"
      output.should contain "test error"
    end

    it "respects log level" do
      io = IO::Memory.new
      logger = Crinkle::LSP::Logger.new(io, Crinkle::LSP::Logger::Level::Warning)

      logger.debug("test debug")
      logger.info("test info")
      logger.warning("test warning")
      logger.error("test error")

      output = io.to_s
      output.should_not contain "test debug"
      output.should_not contain "test info"
      output.should contain "test warning"
      output.should contain "test error"
    end
  end
end
