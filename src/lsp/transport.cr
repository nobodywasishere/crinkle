module Crinkle::LSP
  # Handles LSP message transport over stdio.
  # LSP uses Content-Length headers followed by JSON-RPC messages.
  class Transport
    CONTENT_LENGTH_HEADER = "Content-Length: "

    @input : IO
    @output : IO
    @logger : Logger?

    def initialize(@input : IO = STDIN, @output : IO = STDOUT, @logger : Logger? = nil) : Nil
    end

    # Read a message from the transport.
    # Returns a JSON::Any parsed from the message body.
    # Returns nil on EOF.
    def read_message : JSON::Any?
      content_length = read_headers
      return unless content_length

      body = read_body(content_length)
      return unless body

      @logger.try(&.debug("Received: #{body}"))

      begin
        JSON.parse(body)
      rescue ex : JSON::ParseException
        @logger.try(&.error("Failed to parse JSON: #{ex.message}"))
        nil
      end
    end

    # Write a response message to the transport.
    def write_response(id : (Int64 | String)?, result : JSON::Any) : Nil
      body = JSON.build do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "id" do
            write_id(json, id)
          end
          json.field "result", result
        end
      end
      write_message(body)
    end

    # Write an error response to the transport.
    def write_error(id : (Int64 | String)?, code : Int32, message : String, data : JSON::Any? = nil) : Nil
      body = JSON.build do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "id" do
            write_id(json, id)
          end
          json.field "error" do
            json.object do
              json.field "code", code
              json.field "message", message
              if data
                json.field "data", data
              end
            end
          end
        end
      end
      write_message(body)
    end

    # Write a notification to the transport (no id).
    def write_notification(method : String, params : JSON::Any) : Nil
      body = JSON.build do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "method", method
          json.field "params" { params.to_json(json) }
        end
      end
      write_message(body)
    end

    private def write_id(json : JSON::Builder, id : (Int64 | String)?) : Nil
      case id
      when Int64
        json.number(id)
      when String
        json.string(id)
      else
        json.null
      end
    end

    private def read_headers : Int32?
      content_length : Int32? = nil

      loop do
        line = @input.gets
        return unless line

        line = line.chomp
        break if line.empty?

        if line.starts_with?(CONTENT_LENGTH_HEADER)
          length_str = line[CONTENT_LENGTH_HEADER.size..]
          content_length = length_str.to_i?
        end
        # Ignore other headers (Content-Type, etc.)
      end

      content_length
    end

    private def read_body(length : Int32) : String?
      buffer = Bytes.new(length)
      bytes_read = @input.read_fully?(buffer)
      return unless bytes_read

      String.new(buffer)
    end

    private def write_message(body : String) : Nil
      @logger.try(&.debug("Sending: #{body}"))

      @output << "Content-Length: #{body.bytesize}\r\n"
      @output << "\r\n"
      @output << body
      @output.flush
    end
  end
end
