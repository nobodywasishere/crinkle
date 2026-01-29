require "./spec_helper"
require "lsprotocol"
require "../src/lsp/server"

def frame(json : String) : String
  "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
end

def read_frame(io : IO) : String
  content_length = nil
  while line = io.gets
    header = line.chomp
    break if header.empty?
    if header.starts_with?("Content-Length:")
      content_length = header.split(":", 2)[1]?.to_s.strip.to_i
    end
  end
  raise "Missing Content-Length header" unless content_length
  io.read_string(content_length)
end

def read_all_frames(io : IO) : Array(JSON::Any)
  frames = Array(JSON::Any).new
  while io.pos < io.size
    frames << JSON.parse(read_frame(io))
  end
  frames
end

describe Crinkle::LSP::Server do
  it "responds to initialize with textDocumentSync capabilities" do
    params = LSProtocol::InitializeParams.new(
      LSProtocol::ClientCapabilities.new,
      nil,
      nil,
    )
    request = LSProtocol::InitializeRequest.new(1, params)

    input = IO::Memory.new(frame(request.to_json))
    output = IO::Memory.new
    errors = IO::Memory.new

    server = Crinkle::LSP::Server.new
    server.run(input, output, errors)

    output.rewind
    response = JSON.parse(read_frame(output))
    response["id"].as_i.should eq(1)
    response["result"]["capabilities"]["textDocumentSync"]["openClose"].as_bool.should be_true
    response["result"]["capabilities"]["textDocumentSync"]["change"].as_i.should eq(1)
  end

  it "publishes diagnostics on didOpen" do
    params = LSProtocol::InitializeParams.new(
      LSProtocol::ClientCapabilities.new,
      nil,
      nil,
    )
    request = LSProtocol::InitializeRequest.new(1, params)
    uri = URI.parse("file:///tmp/example.j2")
    text_document = LSProtocol::TextDocumentItem.new("crinkle", "Hello", uri, 1)
    open_params = LSProtocol::DidOpenTextDocumentParams.new(text_document)
    open_notification = LSProtocol::DidOpenTextDocumentNotification.new(open_params)

    input = IO::Memory.new(frame(request.to_json) + frame(open_notification.to_json))
    output = IO::Memory.new
    errors = IO::Memory.new

    server = Crinkle::LSP::Server.new
    server.run(input, output, errors)

    output.rewind
    _response = JSON.parse(read_frame(output))
    notification = JSON.parse(read_frame(output))

    notification["method"].as_s.should eq("textDocument/publishDiagnostics")
    notification["params"]["uri"].as_s.should eq("file:///tmp/example.j2")
    notification["params"]["version"].as_i.should eq(1)
    notification["params"]["diagnostics"].as_a.should be_empty
  end

  it "handles hover, definition, document symbols, and folding ranges" do
    params = LSProtocol::InitializeParams.new(
      LSProtocol::ClientCapabilities.new,
      nil,
      nil,
    )
    request = LSProtocol::InitializeRequest.new(1, params)
    uri = URI.parse("file:///tmp/example.j2")
    template = "{% set foo = 1 %}\n{{ foo }}\n{% block content %}x{% endblock %}\n{% macro greet(name) %}{{ name }}{% endmacro %}\n"
    text_document = LSProtocol::TextDocumentItem.new("crinkle", template, uri, 1)
    open_params = LSProtocol::DidOpenTextDocumentParams.new(text_document)
    open_notification = LSProtocol::DidOpenTextDocumentNotification.new(open_params)

    text_id = LSProtocol::TextDocumentIdentifier.new(uri)
    position = LSProtocol::Position.new(3, 1)
    hover_params = LSProtocol::HoverParams.new(
      position,
      text_id,
    )
    hover_request = LSProtocol::HoverRequest.new(2, hover_params)
    definition_params = LSProtocol::DefinitionParams.new(
      position,
      text_id,
    )
    definition_request = LSProtocol::DefinitionRequest.new(3, definition_params)
    symbol_params = LSProtocol::DocumentSymbolParams.new(text_id)
    symbol_request = LSProtocol::DocumentSymbolRequest.new(4, symbol_params)
    folding_params = LSProtocol::FoldingRangeParams.new(text_id)
    folding_request = LSProtocol::FoldingRangeRequest.new(5, folding_params)

    input_payload = String.build do |io|
      io << frame(request.to_json)
      io << frame(open_notification.to_json)
      io << frame(hover_request.to_json)
      io << frame(definition_request.to_json)
      io << frame(symbol_request.to_json)
      io << frame(folding_request.to_json)
    end

    input = IO::Memory.new(input_payload)
    output = IO::Memory.new
    errors = IO::Memory.new

    server = Crinkle::LSP::Server.new
    server.run(input, output, errors)

    output.rewind
    frames = read_all_frames(output)

    hover_response = frames.find { |frame| frame["id"]?.try(&.as_i?) == 2 }
    definition_response = frames.find { |frame| frame["id"]?.try(&.as_i?) == 3 }
    symbol_response = frames.find { |frame| frame["id"]?.try(&.as_i?) == 4 }
    folding_response = frames.find { |frame| frame["id"]?.try(&.as_i?) == 5 }

    hover_payload = hover_response || raise "Missing hover response"
    hover_payload["result"]["contents"]["value"].as_s.should contain("foo")

    definition_payload = definition_response || raise "Missing definition response"
    definition_payload["result"]["uri"].as_s.should eq("file:///tmp/example.j2")

    symbol_payload = symbol_response || raise "Missing document symbols response"
    symbols = symbol_payload["result"].as_a
    symbols.map(&.["name"].as_s).should contain("content")
    symbols.map(&.["name"].as_s).should contain("greet")
    symbols.map(&.["name"].as_s).should contain("foo")

    folding_payload = folding_response || raise "Missing folding range response"
    _folding_ranges = folding_payload["result"].as_a
  end
end
