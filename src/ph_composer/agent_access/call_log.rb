# frozen_string_literal: true

require "time"

module PhComposer
  module AgentAccess
    # The listener's record of recent tool calls, for diagnosis and for each token's latest call. A row
    # holds the token's id, the tool, the operation name and session the arguments carry, how the call
    # ended, whether it verified the connection and how long it took; never params, a value, a path or the
    # token. It also holds the clients that started a session with a token (`initialize`), named as they name
    # themselves, until the pump passes them on. Not thread safe: the Server holds its lock around every call.
    class CallLog
      SIZE = 64
      CLIENT_LENGTH = 60
      # The reads that prove a connection end to end without changing anything (context/AGENT_INTERFACE.md,
      # "User-controlled local access").
      VERIFYING_TOOLS = %w[discover context].freeze

      def initialize
        @rows = []
        @unread = 0
        @contacts = []
      end

      def add(token, tool, arguments, result, milliseconds)
        outcome = result["structuredContent"].is_a?(Hash) ? result["structuredContent"] : {}
        @rows << { "token" => token.fetch("id"), "tool" => tool, "operation" => text(arguments["name"], 120),
                   "session" => text(arguments["session"], 60), "status" => outcome["status"] || "completed",
                   "code" => outcome["code"], "error" => result["isError"] == true,
                   "verifies" => verifies?(tool, result, outcome), "ms" => milliseconds, "at" => Time.now.utc.iso8601 }
        @rows.shift while @rows.length > SIZE
        @unread = [@unread + 1, SIZE].min
      end

      # The rows added since the last call, oldest first.
      def take_unread
        rows = @rows.last(@unread)
        @unread = 0
        rows
      end

      def recent
        @rows.map(&:dup)
      end

      # A client began a session with this token: its `clientInfo` name and version as it gave them, cut.
      def contact(token, params)
        info = params.is_a?(Hash) && params["clientInfo"].is_a?(Hash) ? params["clientInfo"] : {}
        name = [info["name"], info["version"]].select { |part| part.is_a?(String) }.join(" ")
        @contacts.shift while @contacts.length >= SIZE
        @contacts << { "token" => token.fetch("id"), "client" => name.scrub[0, CLIENT_LENGTH],
                       "at" => Time.now.utc.iso8601 }
      end

      # The contacts recorded since the last call, oldest first.
      def take_contacts
        @contacts.slice!(0..)
      end

      private

      # A discover or context that completed and reached the Models the token serves. An Outcome must say
      # `completed`; discover answers a page with no status. A busy, failed or refused answer never verifies.
      def verifies?(tool, result, outcome)
        VERIFYING_TOOLS.include?(tool) && result["isError"] != true &&
          (outcome.key?("status") ? outcome["status"] == "completed" : tool == "discover") &&
          !(outcome["connection"].is_a?(Hash) && outcome["connection"]["reason"])
      end

      def text(value, length)
        value.is_a?(String) ? value[0, length] : nil
      end
    end
  end
end
