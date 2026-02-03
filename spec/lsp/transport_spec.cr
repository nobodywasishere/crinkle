require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::Transport do
    it "writes response messages with Content-Length header" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_response(1_i64, JSON.parse(%({"success": true})))

      result = output.to_s
      result.should contain "Content-Length:"
      result.should contain "jsonrpc"
      result.should contain "result"
    end

    it "writes error responses" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_error(1_i64, -32601, "Method not found")

      result = output.to_s
      result.should contain "error"
      result.should contain "Method not found"
      result.should contain "-32601"
    end

    it "writes error responses with correct JSON structure" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_error(42_i64, -32601, "Method not found: textDocument/hover")

      result = output.to_s
      # Extract JSON body (after headers)
      if body_start = result.index("{")
        json_body = result[body_start..]

        parsed = JSON.parse(json_body)
        parsed["jsonrpc"].should eq "2.0"
        parsed["id"].should eq 42
        parsed["error"]["code"].should eq -32601
        parsed["error"]["message"].should eq "Method not found: textDocument/hover"
      else
        fail "No JSON body found in response"
      end
    end

    it "writes notifications" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_notification("textDocument/publishDiagnostics", JSON.parse(%({"uri": "file:///test.j2"})))

      result = output.to_s
      result.should contain "textDocument/publishDiagnostics"
      result.should_not contain "\"id\""
    end

    it "writes notifications with correct JSON structure" do
      output = IO::Memory.new
      transport = Crinkle::LSP::Transport.new(IO::Memory.new, output)

      transport.write_notification("window/logMessage", JSON.parse(%({"type": 3, "message": "test"})))

      result = output.to_s
      if body_start = result.index("{")
        json_body = result[body_start..]

        parsed = JSON.parse(json_body)
        parsed["jsonrpc"].should eq "2.0"
        parsed["method"].should eq "window/logMessage"
        parsed["params"]["type"].should eq 3
        parsed["params"]["message"].should eq "test"
        parsed["id"]?.should be_nil
      else
        fail "No JSON body found in notification"
      end
    end

    it "reads messages with Content-Length header" do
      message = %({"jsonrpc": "2.0", "id": 1, "method": "initialize"})
      input = IO::Memory.new("Content-Length: #{message.bytesize}\r\n\r\n#{message}")
      transport = Crinkle::LSP::Transport.new(input, IO::Memory.new)

      result = transport.read_message
      result.should_not be_nil
      result.try(&.["method"]).should eq "initialize"
      result.try(&.["id"]).should eq 1
    end

    it "returns nil on EOF" do
      input = IO::Memory.new("")
      transport = Crinkle::LSP::Transport.new(input, IO::Memory.new)

      transport.read_message.should be_nil
    end
  end
end
