# frozen_string_literal: true

require "json"

module PhComposer
  module AgentAccess
    # What the Agent Access dialog shows for each supported client, generated from the port and the token
    # just issued. Pure text: ClientSetup is what writes a client's configuration. The forms are the ones
    # checked against Claude Code 2.1.317 and Codex 0.167.0 (context/AGENT_INTERFACE.md, "User-controlled
    # local access"); a flag a later client renames is a golden-test failure, not a silent edit.
    module ClientConfig
      SERVER_NAME = "ph-composer"

      module_function

      def url(port)
        "http://127.0.0.1:#{port}/mcp"
      end

      # One entry per client: its id and name, the setup forms (each a title and the text to paste), and the
      # commands that check and remove the entry. The first form is what Connect sets up and names the file
      # PH-Composer keeps the client's token in, never the token; the last carries the token itself.
      def for(port:, token:)
        [claude_code(port, token), codex(port, token)]
      end

      # The server as Claude Code's `add-json` takes it: its header comes from the helper, run each time
      # Claude Code connects (2.1.317, checked from a session started with no terminal environment).
      def claude_server(port)
        { "type" => "http", "url" => url(port), "headersHelper" => Connections.helper("claude_code") }
      end

      def claude_code(port, token)
        { "id" => "claude_code", "client" => "Claude Code",
          "forms" => [
            { "title" => "What Connect runs. If it cannot, run this in Terminal once. It names the file " \
                         "PH-Composer keeps the token in, not the token.",
              "text" => "claude mcp add-json --scope user #{SERVER_NAME} " \
                        "#{single_quoted(JSON.generate(claude_server(port)))}" },
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
      def codex_block(port)
        "#{codex_table(port)}http_headers_helper = #{JSON.generate(Connections.helper('codex'))}"
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

      def codex_table(port)
        "[mcp_servers.#{SERVER_NAME}]\nurl = \"#{url(port)}\"\n"
      end

      # One shell word, quoted for a terminal: a quote inside it closes, escapes and reopens the quoting.
      def single_quoted(text)
        "'#{text.gsub("'") { "'\\''" }}'"
      end
    end
  end
end
