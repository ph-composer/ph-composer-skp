# frozen_string_literal: true

require_relative "test_helper"

# The text the Agent Access dialog shows for each supported client, pinned to Claude Code 2.1.317 and
# Codex 0.167.0 (context/AGENT_INTERFACE.md, "User-controlled local access"). A changed flag in a later
# client is a change to these goldens, made on purpose with the new version recorded.
class AgentAccessClientConfigTest < PhComposerTestCase
  ClientConfig = PhComposer::AgentAccess::ClientConfig
  Connections = PhComposer::AgentAccess::Connections
  TOKEN = "0123456789abcdef0123456789abcdef0123456789abcdef"

  def setup
    super
    Connections.directory = "/Users/someone/.ph-composer"
  end

  def test_claude_code_reads_its_token_through_a_helper_first_and_from_its_command_last
    claude = ClientConfig.for(:port => 46_110, :token => TOKEN).first

    assert_equal %w[claude_code Claude\ Code], claude.values_at("id", "client")
    assert_equal ["claude mcp add-json --scope user ph-composer '{\"type\":\"http\"," \
                  "\"url\":\"http://127.0.0.1:46110/mcp\"," \
                  "\"headersHelper\":\"/bin/cat /Users/someone/.ph-composer/claude_code.json\"}'",
                  "claude mcp add --transport http --scope user ph-composer http://127.0.0.1:46110/mcp " \
                  "--header \"Authorization: Bearer #{TOKEN}\""], claude.fetch("forms").map { |form| form["text"] }
    assert_equal ["What Connect runs. If it cannot, run this in Terminal once. It names the file PH-Composer keeps " \
                  "the token in, not the token.",
                  "Or, one command with the token itself, kept in Claude Code's settings file and your shell " \
                  "history. A new token then means running it again."],
                 claude.fetch("forms").map { |form| form["title"] }
    assert_equal ["claude mcp get ph-composer", "claude mcp remove --scope user ph-composer"],
                 claude.values_at("check", "remove")
  end

  def test_codex_reads_its_token_through_a_helper_first_or_inline_in_its_config
    codex = ClientConfig.for(:port => 46_110, :token => TOKEN).last

    assert_equal %w[codex Codex], codex.values_at("id", "client")
    block = "[mcp_servers.ph-composer]\nurl = \"http://127.0.0.1:46110/mcp\"\n" \
            "default_tools_approval_mode = \"approve\"\n"
    assert_equal ["#{block}http_headers_helper = \"/bin/cat /Users/someone/.ph-composer/codex.json\"",
                  "#{block}http_headers = { Authorization = \"Bearer #{TOKEN}\" }"],
                 codex.fetch("forms").map { |form| form["text"] }
    assert_equal ["codex mcp get ph-composer",
                  "Delete the [mcp_servers.ph-composer] block from ~/.codex/config.toml"],
                 codex.values_at("check", "remove")
  end

  def test_each_client_leads_with_a_form_that_names_the_file_and_not_the_token
    ClientConfig.for(:port => 46_110, :token => TOKEN).each do |client|
      first = client.fetch("forms").first.fetch("text")
      assert_includes first, Connections.path(client.fetch("id")), client.fetch("client")
      refute_includes first, TOKEN, client.fetch("client")
    end
  end

  # A home folder with a space or a quote stays one shell word in the helper, and the command stays one
  # shell word in the terminal; the TOML string escapes what the helper's escaping added.
  def test_a_path_that_needs_quoting_stays_one_word_in_every_form
    Connections.directory = "/Users/Jo O'Neil/.ph-composer"
    claude, codex = ClientConfig.for(:port => 46_110, :token => TOKEN).map { |client| client["forms"].first["text"] }

    assert_equal "/bin/cat /Users/Jo\\ O\\'Neil/.ph-composer/claude_code.json", Connections.helper("claude_code")
    assert_equal ["claude", "mcp", "add-json", "--scope", "user", "ph-composer",
                  JSON.generate(ClientConfig.claude_server(46_110))], Shellwords.split(claude)
    assert_includes codex, 'http_headers_helper = "/bin/cat /Users/Jo\\\\ O\\\\\'Neil/.ph-composer/codex.json"'
  end

  def test_a_changed_port_reaches_every_form
    forms = ClientConfig.for(:port => 47_001, :token => TOKEN).flat_map { |client| client.fetch("forms") }

    assert(forms.all? { |form| form["text"].include?("http://127.0.0.1:47001/mcp") })
    refute(forms.any? { |form| form["text"].include?("46110") })
  end
end
