# frozen_string_literal: true

require "io/wait"
require "socket"

module PhComposer
  # The HTTP/1.1 the loopback asset server speaks: read one request line within a deadline and a
  # header budget, and write one complete response with the isolation headers the runtime needs.
  module LoopbackHttp
    STATUS_TEXT = {
      200 => "OK",
      202 => "Accepted",
      400 => "Bad Request",
      401 => "Unauthorized",
      403 => "Forbidden",
      404 => "Not Found",
      405 => "Method Not Allowed",
      408 => "Request Timeout",
      411 => "Length Required",
      413 => "Content Too Large",
      415 => "Unsupported Media Type",
      431 => "Request Header Fields Too Large",
      500 => "Internal Server Error"
    }.freeze

    # One whole request: its line, its headers by lower-case name, and its body. `refusal` is the status
    # a request that could not be read within its budgets is answered with, and then the rest is nil.
    Request = Struct.new(:verb, :target, :headers, :body, :refusal, keyword_init: true)

    module_function

    # The request line, or nil when the client sent nothing complete in time or overran the budget.
    def read_request_line(session, timeout:, max_header_bytes:)
      deadline = monotonic + timeout
      buffer = +""
      loop do
        remaining = deadline - monotonic
        return nil if remaining <= 0 || !session.wait_readable(remaining)

        chunk = session.read_nonblock(4096, :exception => false)
        return nil if chunk == :wait_readable || chunk.nil?

        buffer << chunk
        return nil if buffer.bytesize > max_header_bytes
        break if buffer.include?("\r\n\r\n") || buffer.include?("\n\n")
      end
      buffer.lines.first
    end

    # Reads the request line, the headers within `max_header_bytes` and a body of exactly its
    # `Content-Length`, at most `max_body_bytes`, all before the deadline. A request without a body
    # declares none; one that declares a length over the budget is refused before its body is read.
    def read_request(session, timeout:, max_header_bytes:, max_body_bytes:)
      deadline = monotonic + timeout
      buffer = String.new(:encoding => Encoding::BINARY)
      until (split = buffer.index("\r\n\r\n"))
        return Request.new(:refusal => 431) if buffer.bytesize > max_header_bytes
        return Request.new(:refusal => 408) unless (chunk = read_chunk(session, deadline))

        buffer << chunk.b
      end
      head = buffer[0, split]
      return Request.new(:refusal => 431) if head.bytesize > max_header_bytes

      verb, target, = head.lines.first.to_s.split(" ", 3)
      headers = parse_headers(head.lines.drop(1))
      length = headers["content-length"]
      return Request.new(:refusal => 400) if length && !length.match?(/\A\d+\z/)
      return Request.new(:refusal => 413) if length.to_i > max_body_bytes

      body = buffer.byteslice(split + 4, buffer.bytesize)
      while body.bytesize < length.to_i
        return Request.new(:refusal => 408) unless (chunk = read_chunk(session, deadline))

        body << chunk.b
      end
      Request.new(:verb => verb, :target => target.to_s, :headers => headers,
                  :body => body.byteslice(0, length.to_i).force_encoding(Encoding::UTF_8))
    end

    # Lower-case header names to their values; a repeated header keeps its first value.
    def parse_headers(lines)
      lines.each_with_object({}) do |line, headers|
        name, value = line.split(":", 2)
        next unless value

        headers[name.strip.downcase] ||= value.strip
      end
    end

    # The next bytes before `deadline`, or nil when it passes or the peer closes.
    def read_chunk(session, deadline)
      remaining = deadline - monotonic
      return nil if remaining <= 0 || !session.wait_readable(remaining)

      chunk = session.read_nonblock(4096, :exception => false)
      chunk.is_a?(String) ? chunk : nil
    end

    def percent_decode(text)
      text.gsub(/%([0-9A-Fa-f]{2})/) { Regexp.last_match(1).hex.chr }
    end

    def respond(session, status, type, body, extra = nil)
      headers = [
        "HTTP/1.1 #{status} #{STATUS_TEXT.fetch(status)}",
        "Content-Type: #{type}",
        "Content-Length: #{body.bytesize}",
        "Cross-Origin-Opener-Policy: same-origin",
        "Cross-Origin-Embedder-Policy: require-corp",
        "Cross-Origin-Resource-Policy: same-origin",
        "X-Content-Type-Options: nosniff",
        "Cache-Control: no-store",
        "Connection: close"
      ]
      headers << extra if extra
      session.write(headers.join("\r\n") + "\r\n\r\n")
      session.write(body)
    end

    # A complete JSON or empty response with only the headers an API reply needs.
    def respond_json(session, status, body, extra = [])
      headers = ["HTTP/1.1 #{status} #{STATUS_TEXT.fetch(status)}", "Content-Length: #{body.bytesize}",
                 "Cache-Control: no-store", "Connection: close"]
      headers << "Content-Type: application/json" unless body.empty?
      session.write((headers + extra).join("\r\n") + "\r\n\r\n")
      session.write(body)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Whether the client is still there to read a reply, asked once its whole request has been read: false
    # when a peek reads the end of the stream (the client closed its side, as one does when it stops waiting)
    # or the connection was reset; true while it waits with nothing more to send, or when it sent more. A
    # client that shuts down its sending side and still waits for the reply reads as gone; MCP clients close
    # both sides together.
    def peer_open?(session)
      peeked = session.recv_nonblock(1, Socket::MSG_PEEK, :exception => false)
      !(peeked.nil? || peeked == "")
    rescue IOError, SystemCallError
      false
    end
  end
end
