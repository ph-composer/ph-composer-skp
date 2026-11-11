# frozen_string_literal: true

require "json"
require_relative "connections"

module PhComposer
  module AgentAccess
    # What the Agent Access dialog shows for each supported client, generated from the port, the token just
    # issued and the connection profile (Connections). Pure text: ClientSetup is what writes a client's
    # configuration. The forms are the ones
    # checked against Claude Code 2.1.317 and Codex 0.167.0 (context/AGENT_INTERFACE.md, "User-controlled
    # local access"); a flag a later client renames is a golden-test failure, not a silent edit.
    module ClientConfig
      SERVER_NAME = "ph-composer"
      DEFAULT = Connections::DEFAULT_PROFILE
      # Codex asks before each call to a server's tools unless the entry approves them, and a session that
      # cannot ask, such as `codex exec`, then refuses every write (0.167.0); the token's grants still bound
      # what a call can do (context/AGENT_INTERFACE.md, "User-controlled local access").
      CODEX_APPROVAL_KEY = "default_tools_approval_mode"
      CODEX_APPROVAL_LINE = "#{CODEX_APPROVAL_KEY} = \"approve\"".freeze

      module_function

      def url(port)
        "http://127.0.0.1:#{port}/mcp"
      end

      # The client entry's name for a profile: `ph-composer` for the default, `ph-composer-<name>` otherwise.
      def server_name(profile = DEFAULT)
        Connections.checked_profile(profile) == DEFAULT ? SERVER_NAME : "#{SERVER_NAME}-#{profile}"
      end

      # The token-free setup for one profile: what Connect and Repair make, for the user to run or paste
      # when they cannot.
      def setup_text(client, port, profile = DEFAULT)
        if client == "claude_code"
          "claude mcp add-json --scope user #{server_name(profile)} " \
            "#{single_quoted(JSON.generate(claude_server(port, profile)))}"
        else
          codex_block(port, profile)
        end
      end

      # One entry per client: its id and name, the setup forms (each a title and the text to paste), and the
      # commands that check and remove the entry. The first form is what Connect sets up and names the file
      # PH-Composer keeps the client's token in, never the token; the last carries the token itself.
      def for(port:, token:)
        [claude_code(port, token), codex(port, token)]
      end

      # The server as Claude Code's `add-json` takes it: its header comes from the helper, run each time
      # Claude Code connects (2.1.317, checked from a session started with no terminal environment).
      def claude_server(port, profile = DEFAULT)
        { "type" => "http", "url" => url(port), "headersHelper" => Connections.helper("claude_code", profile) }
      end

      def claude_code(port, token)
        { "id" => "claude_code", "client" => "Claude Code",
          "forms" => [
            { "title" => "What Connect runs. If it cannot, run this in Terminal once. It names the file " \
                         "PH-Composer keeps the token in, not the token.",
              "text" => setup_text("claude_code", port) },
            { "title" => "Or, one command with the token itself, kept in Claude Code's settings file and your " \
                         "shell history. A new token then means running it again.",
              "text" => "claude mcp add --transport http --scope user #{SERVER_NAME} #{url(port)} " \
                        "--header \"Authorization: Bearer #{token}\"" }
          ],
          "check" => "claude mcp get #{SERVER_NAME}",
          "remove" => "claude mcp remove --scope user #{SERVER_NAME}" }
      end

      # The block Connect appends to ~/.codex/config.toml: its header comes from the helper (0.167.0, checked
      # from a session started with no terminal environment).
      def codex_block(port, profile = DEFAULT)
        "#{codex_table(port, profile)}#{codex_helper_line(profile)}"
      end

      # The block's token line: the header comes from the helper.
      def codex_helper_line(profile = DEFAULT)
        "http_headers_helper = #{JSON.generate(Connections.helper('codex', profile))}"
      end

      def codex(port, token)
        { "id" => "codex", "client" => "Codex",
          "forms" => [
            { "title" => "What Connect adds to ~/.codex/config.toml. If it cannot, paste this there. It names " \
                         "the file PH-Composer keeps the token in, not the token.",
              "text" => codex_block(port) },
            { "title" => "Or this block instead, with the token itself kept in ~/.codex/config.toml. A new " \
                         "token then means editing it again.",
              "text" => "#{codex_table(port)}http_headers = { Authorization = \"Bearer #{token}\" }" }
          ],
          "check" => "codex mcp get #{SERVER_NAME}",
          "remove" => "Delete the [mcp_servers.#{SERVER_NAME}] block from ~/.codex/config.toml" }
      end

      def codex_table(port, profile = DEFAULT)
        "[mcp_servers.#{server_name(profile)}]\n#{codex_url_line(port)}\n#{CODEX_APPROVAL_LINE}\n"
      end

      def codex_url_line(port)
        "url = \"#{url(port)}\""
      end

      # One shell word, quoted for a terminal: a quote inside it closes, escapes and reopens the quoting.
      def single_quoted(text)
        "'#{text.gsub("'") { "'\\''" }}'"
      end
    end
  end
end
