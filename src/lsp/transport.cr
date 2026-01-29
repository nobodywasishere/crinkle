module Jinja
  module LSP
    class Transport
      def initialize(@io_in : IO, @io_out : IO) : Nil
      end

      def read_message : String?
        content_length = nil

        while line = @io_in.gets
          header = line.chomp
          break if header.empty?
          if header.starts_with?("Content-Length:")
            value = header.split(":", 2)[1]?.to_s.strip
            content_length = value.to_i?
          end
        end

        return if content_length.nil?

        @io_in.read_string(content_length)
      end

      def send_message(payload : String) : Nil
        @io_out << "Content-Length: #{payload.bytesize}\r\n\r\n"
        @io_out << payload
        @io_out.flush
      end
    end
  end
end
