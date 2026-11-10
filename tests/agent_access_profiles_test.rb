# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# Client profiles (context/AGENT_INTERFACE.md, "User-controlled local access"): one client entry and header
# file per profile, the existing entry read as the default, replacement shown before a binding changes,
# Repair from a saved connection, Codex edits confined to the owned table, and configured, contacted and
# verified kept apart. Every client file is in the test's scratch home and no test runs a client.
class AgentAccessProfilesTest < PhComposerTestCase
  Tokens = PhComposer::AgentAccess::Tokens
  Dialog = PhComposer::AgentAccess::Dialog
  Connections = PhComposer::AgentAccess::Connections
  ClientSetup = PhComposer::AgentAccess::ClientSetup
  ClientConfig = PhComposer::AgentAccess::ClientConfig
  CodexConfig = PhComposer::AgentAccess::CodexConfig
  Listener = PhComposer::AgentAccess::Listener
  CallLog = PhComposer::AgentAccess::CallLog
  BINARY = "/opt/homebrew/bin/claude"

  def setup
    super
    PhComposer.compose
    @runs = []
    @answers = []
    ClientSetup.runner = lambda do |argv|
      @runs << argv
      @answers.shift || [true, ""]
    end
    Dir.mkdir(ClientSetup.codex_home)
    @config = File.join(ClientSetup.codex_home, "config.toml")
  end

  def test_two_profiles_of_one_client_each_keep_their_own_token_and_entry
    a = Tokens.issue(:label => "House A")
    b = Tokens.issue(:label => "House B")
    File.binwrite(@config, "model = \"x\"\n")

    ClientSetup.connect("codex", a.fetch("token"), 46_110)
    ClientSetup.connect("codex", b.fetch("token"), 46_110, :profile => "house-b")
    ClientSetup.stub(:claude_binary, BINARY) {
      ClientSetup.connect("claude_code", b.fetch("token"), 46_110, :profile => "house-b")
    }

    blocks = [ClientConfig.codex_block(46_110), ClientConfig.codex_block(46_110, "house-b")]
    assert_equal "model = \"x\"\n\n#{blocks.join("\n\n")}\n",
                 File.binread(@config)
    assert_equal "ph-composer-house-b", @runs.last[5]
    assert_includes @runs.last[6], Connections.path("claude_code", "house-b")
    assert_equal [Tokens.digest(a["token"]), Tokens.digest(b["token"])],
                 [Connections.digest("codex", "default"), Connections.digest("codex", "house-b")]
    rows = connection_rows
    assert_equal [%w[claude_code house-b], %w[codex default], %w[codex house-b]], rows.map { |row|
      row.values_at("client", "profile")
    }
    assert_equal ["House B", "House A", "House B"], rows.map { |row| row.dig("token", "label") }

    Tokens.revoke(a.dig("row", "id"))

    refute File.exist?(Connections.path("codex"))
    assert File.exist?(Connections.path("codex", "house-b")), "the other profile keeps its token"
    assert_equal [nil, "House B"], connection_rows.select { |row|
      row["client"] == "codex"
    }.map { |row| row.dig("token", "label") }
  end

  def test_an_existing_default_entry_and_file_read_as_the_default_profile_unchanged
    old = Tokens.issue(:label => "Old", :capabilities => %w[read model_write])
    Connections.write("codex", old.fetch("token"))
    before = "#{ClientConfig.codex_block(46_110)}\nstartup_timeout_sec = 30\n"
    File.binwrite(@config, before)

    row = connection_rows.find { |item| item["client"] == "codex" }

    assert_equal %w[default ph-composer configured file], row.values_at("profile", "server", "entry", "source")
    assert_equal %w[read model_write], row.dig("token", "capabilities")
    assert_equal "configured", ClientSetup.connect("codex", old.fetch("token"), 46_110).fetch("state"),
                 "a harmless extra setting is not a failed setup"
    assert_equal before, File.binread(@config)
  end

  def test_connect_to_a_profile_another_token_holds_shows_it_and_replaces_only_when_named
    held = Tokens.issue(:label => "Held")
    Connections.write("codex", held.fetch("token"))
    dialog = Dialog.show
    fresh = issue(dialog, "Fresh")

    connect(dialog, fresh["token"])
    replacement = delivered(dialog, "access.replacement").last
    assert_equal ["codex", "default", "Held"],
                 [replacement["client"], replacement["profile"], replacement.dig("token", "label")]
    assert_equal Tokens.digest(held["token"]), Connections.digest("codex", "default"), "nothing was written"

    connect(dialog, fresh["token"], "replace" => "token_ZZZZZZZZZZZZ")
    assert_includes delivered(dialog, "access.failure").last["message"], "now uses Held"

    connect(dialog, fresh["token"], "replace" => held.dig("row", "id"))
    assert_equal "configured", delivered(dialog, "access.connected").last["state"]
    assert_equal Tokens.digest(fresh["token"]), Connections.digest("codex", "default")
    assert(Tokens.list.find { |row|
      row["label"] == "Held"
    }["revoked_at"].nil?, "the old token stays live until revoked")
    assert_no_secret(dialog, fresh["token"])
  end

  def test_repair_after_a_port_change_edits_only_the_owned_url_line_and_keeps_a_backup
    token = Tokens.issue.fetch("token")
    Connections.write("codex", token)
    before = "# mine\n[mcp_servers.ph-composer]\n#{ClientConfig.codex_url_line(46_110)}  # old\n" \
             "#{ClientConfig.codex_helper_line}\nstartup_timeout_sec = 30\n[mcp_servers.ph-composer.tools.x]\n" \
             "approval = \"never\"\n\n[other]\nurl = \"keep\"\n"
    File.binwrite(@config, before)
    assert_equal "outdated", ClientSetup.entry("codex", 47_001, "default")["setup"]

    result = ClientSetup.repair("codex", 47_001)

    assert_equal "configured", result.fetch("state")
    assert_equal before.sub("#{ClientConfig.codex_url_line(46_110)}  # old", ClientConfig.codex_url_line(47_001)),
                 File.binread(@config)
    assert_equal before, File.binread("#{@config}#{ClientSetup::BACKUP_SUFFIX}")
    assert_valid_toml File.binread(@config)
    assert_equal 0o600, File.stat("#{@config}#{ClientSetup::BACKUP_SUFFIX}").mode & 0o777
    assert_empty @runs
  end

  def test_repair_claude_code_replaces_its_entry_by_name_with_its_own_commands
    token = Tokens.issue.fetch("token")
    Connections.write("claude_code", token, "house-b")
    File.write(ClientSetup.claude_settings, JSON.generate("mcpServers" => {
      "ph-composer-house-b" => ClientConfig.claude_server(46_110,
                                                          "house-b"),
      "ph-composer" => { "type" => "http" }
    }))
    @answers = [[false, "MCP server ph-composer-house-b already exists in user config"], [true, ""], [true, ""]]

    result = ClientSetup.stub(:claude_binary, BINARY) {
      ClientSetup.repair("claude_code", 47_001, :profile => "house-b")
    }

    assert_equal "configured", result.fetch("state")
    assert_equal [%w[add-json ph-composer-house-b], %w[remove ph-composer-house-b], %w[add-json ph-composer-house-b]],
                 @runs.map { |argv| [argv[2], argv[5]] }
    refute(@runs.flatten.any? { |part| part.include?(token) })
  end

  def test_repair_refuses_a_revoked_saved_token_which_stays_listed_as_needing_one
    issued = Tokens.issue
    Connections.write("codex", issued.fetch("token"))
    File.binwrite(@config, "#{ClientConfig.codex_block(46_110)}\n")
    Tokens.revoke(issued.dig("row", "id"))

    error = assert_raises(PhComposer::CodedError) { ClientSetup.repair("codex", 46_110) }

    assert_equal "agent_access.token_unknown", error.code
    row = connection_rows.find { |item| item["client"] == "codex" }
    assert_equal [nil, nil, "configured"], row.values_at("token", "source", "entry")
  end

  def test_an_inline_codex_token_is_named_before_connect_replaces_it_with_the_file
    old = Tokens.issue(:label => "Inline")
    File.binwrite(@config, "[mcp_servers.ph-composer]\n#{ClientConfig.codex_url_line(46_110)}\n" \
                           "http_headers = { Authorization = \"Bearer #{old['token']}\" }\nenabled = true\n")
    dialog = Dialog.show
    fresh = issue(dialog, "Fresh")
    row = delivered(dialog, "access.state").last["connections"].find { |item| item["client"] == "codex" }
    assert_equal ["inline", "inline", "Inline"], [row["entry"], row["source"], row.dig("token", "label")]

    connect(dialog, fresh["token"])
    assert_equal "Inline", delivered(dialog, "access.replacement").last.dig("token", "label")
    connect(dialog, fresh["token"], "replace" => old.dig("row", "id"))

    answer = delivered(dialog, "access.connected").last
    assert_equal "configured", answer["state"]
    assert_includes answer["message"], "revoke it here"
    expected = [ClientConfig.codex_url_line(46_110), ClientConfig.codex_helper_line, "enabled = true"]
    assert_equal "[mcp_servers.ph-composer]\n#{expected.join("\n")}\n", File.binread(@config)
    assert_no_secret(dialog, fresh["token"], old["token"])
  end

  # A refused migration leaves the client on its inline token: the row names that token, and the new one as
  # saved and waiting, so Revoke and Replace speak of what the client really uses (review of PR #448).
  def test_a_refused_inline_migration_keeps_the_inline_token_as_the_binding
    old = Tokens.issue(:label => "Inline")
    File.binwrite(@config, "[mcp_servers.ph-composer]\n#{ClientConfig.codex_url_line(46_110)}\n" \
                           "http_headers = { Authorization = \"Bearer #{old['token']}\" }\n")
    File.chmod(0o400, @config)
    dialog = Dialog.show
    fresh = issue(dialog, "Fresh")

    connect(dialog, fresh["token"], "replace" => old.dig("row", "id"))

    assert_includes delivered(dialog, "access.connected").last["message"], "is read-only"
    row = Dialog.connections(46_110).find { |item| item["client"] == "codex" }
    assert_equal %w[inline Inline Fresh], [row["source"], row.dig("token", "label"), row.dig("saved_token", "label")]
    connect(dialog, fresh["token"])
    assert_equal "Inline", delivered(dialog, "access.replacement").last.dig("token", "label")
  ensure
    File.chmod(0o600, @config) if File.exist?(@config)
  end

  def test_a_codex_file_changed_meanwhile_read_only_or_linked_is_never_clobbered
    token = Tokens.issue.fetch("token")
    stale = "[mcp_servers.ph-composer]\n#{ClientConfig.codex_url_line(46_110)}\n#{ClientConfig.codex_helper_line}\n"
    File.binwrite(@config, stale)
    planned = CodexConfig.method(:edit)
    edit = lambda do |*args|
      File.binwrite(@config, "#{stale}# the user saved this meanwhile\n")
      planned.call(*args)
    end
    result = CodexConfig.stub(:edit, edit) { ClientSetup.connect("codex", token, 47_001) }
    assert_equal "manual", result["state"]
    assert_includes result["message"], "changed while PH-Composer was reading it"
    assert_equal "#{stale}# the user saved this meanwhile\n", File.binread(@config)

    File.binwrite(@config, stale)
    File.chmod(0o400, @config)
    result = ClientSetup.connect("codex", token, 47_001)
    assert_includes result["message"], "is read-only"
    assert_equal stale, File.binread(@config)
    File.chmod(0o600, @config)

    real = File.join(@agent_home, "dotfiles.toml")
    File.rename(@config, real)
    File.symlink(real, @config)
    assert_equal "configured", ClientSetup.connect("codex", token, 47_001).fetch("state")
    assert File.symlink?(@config), "a linked config stays a link"
    assert_includes File.binread(real), ClientConfig.codex_url_line(47_001)
  end

  # Table-like text inside another setting's multi-line string or array is not a table (review of PR #448);
  # each result is checked by an independent TOML parser.
  def test_text_inside_strings_and_arrays_is_never_taken_for_the_entry
    token = Tokens.issue.fetch("token")
    prompt = "developer_instructions = \"\"\"\n[mcp_servers.ph-composer]\nurl = \"http://elsewhere\"\n\"\"\"\n"
    File.binwrite(@config, prompt)
    assert_equal "absent", ClientSetup.entry("codex", 46_110, "default")["setup"]
    assert_equal "configured", ClientSetup.connect("codex", token, 46_110).fetch("state")
    assert_equal "#{prompt}\n#{ClientConfig.codex_block(46_110)}\n", File.binread(@config)
    assert_valid_toml File.binread(@config)

    nested = "[mcp_servers.ph-composer]\ncustom = [ # comment\n  [1, 2],\n]\nurl = \"x\"\n"
    File.binwrite(@config, nested)
    assert_equal "manual", ClientSetup.connect("codex", token, 46_110).fetch("state")
    assert_equal nested, File.binread(@config)
    File.binwrite(@config, "x = \"unclosed\n[mcp_servers.ph-composer]\n")
    assert_equal "other", ClientSetup.entry("codex", 46_110, "default")["setup"]
  end

  def test_forms_codex_cannot_be_edited_for_certain_answer_manual_with_the_token_free_block
    token = Tokens.issue.fetch("token")
    ["[mcp_servers.ph-composer]\nurl = \"x\"\nbearer_token_env_var = \"T\"\n",
     "[mcp_servers.ph-composer]\nurl = \"x\"\nenv_http_headers = { A = \"B\" }\n",
     "[mcp_servers.ph-composer]\n\"url\" = \"x\"\n",
     "[mcp_servers.ph-composer]\nurl = \"x\"\nnote = \"\"\"\nurl = 1\n\"\"\"\n",
     "[mcp_servers.ph-composer]\nurl = \"x\"\nhttp_headers = { Authorization = \"Bearer #{token}\", X = \"y\" }\n",
     "[mcp_servers.ph-composer]\nurl = \"x\"\nhttp_headers.Authorization = \"Bearer #{token}\"\n",
     "[mcp_servers.ph-composer]\nurl = \"x\"\n[mcp_servers.ph-composer.http_headers]\n" \
     "Authorization = \"Bearer #{token}\"\n",
     "[mcp_servers.ph-composer]\nfoo = [\n  [1, 2],\n]\nurl = \"x\"\n",
     "[mcp_servers.ph-composer]\nurl = \"x\"\n\n[x]\nmcp_servers.ph-composer.enabled = false\n"]
      .each do |form|
      File.binwrite(@config, form)
      result = ClientSetup.connect("codex", token, 46_110)
      assert_equal "manual", result["state"], form
      assert_equal ClientConfig.codex_block(46_110), result["setup"]
      refute_includes result["setup"], token
      assert_equal form, File.binread(@config)
    end
  end

  def test_a_non_ascii_config_takes_the_block_and_a_failed_read_back_puts_the_file_back
    token = Tokens.issue.fetch("token")
    File.binwrite(@config, "# Jos\u00e9's settings\n".b)
    assert_equal "configured", ClientSetup.connect("codex", token, 46_110).fetch("state")
    assert_equal "# Jos\u00e9's settings\n\n#{ClientConfig.codex_block(46_110)}\n", File.read(@config)

    before = File.binread(@config)
    states = [CodexConfig.method(:state), ->(*) { "other" }]
    calls = 0
    reading = lambda do |*args|
      calls += 1
      (calls == 1 ? states.first : states.last).call(*args)
    end
    result = CodexConfig.stub(:state, reading) { ClientSetup.connect("codex", token, 47_001) }
    assert_includes result["message"], "put back as it was"
    assert_equal before, File.binread(@config)
    assert_equal before, File.binread("#{@config}#{ClientSetup::BACKUP_SUFFIX}")
  end

  def test_a_dangling_linked_config_and_an_unreadable_claude_file_never_break_the_dialog
    token = Tokens.issue.fetch("token")
    File.symlink(File.join(@agent_home, "gone.toml"), @config)
    assert_equal "manual", ClientSetup.connect("codex", token, 46_110).fetch("state")
    assert File.symlink?(@config)

    File.write(ClientSetup.claude_settings, "{ not json")
    rows = Dialog.connections(46_110)
    assert_equal [%w[codex default]], rows.map { |row| row.values_at("client", "profile") }
    assert_equal "unreadable", ClientSetup.entry("claude_code", 46_110, "default")["setup"]
  end

  def test_a_profile_name_that_cannot_be_an_entry_is_refused_before_anything_is_written
    dialog = Dialog.show
    fresh = issue(dialog, "Fresh")
    ["../x", "House", "a" * 33, "-x", 7].each do |profile|
      connect(dialog, fresh["token"], "profile" => profile)
      assert_includes delivered(dialog, "access.failure").last["message"], "profile name", profile.inspect
    end
    assert_empty Dir.exist?(Connections.directory) ? Dir.children(Connections.directory) : []
  end

  def test_repair_times_out_or_finds_no_claude_and_answers_the_setup_to_run
    token = Tokens.issue.fetch("token")
    Connections.write("claude_code", token)
    @answers = [[false, "it did not answer within 20 s"]]

    timed_out = ClientSetup.stub(:claude_binary, BINARY) { ClientSetup.repair("claude_code", 46_110) }
    missing = ClientSetup.stub(:claude_binary, nil) { ClientSetup.repair("claude_code", 46_110) }

    assert_equal %w[manual manual], [timed_out["state"], missing["state"]]
    assert_includes timed_out["message"], "did not finish (it did not answer within 20 s)"
    assert_includes missing["message"], "could not find the claude command"
    assert_equal ClientConfig.setup_text("claude_code", 46_110), missing["setup"]
  end

  def test_contacted_and_verified_are_recorded_apart_from_any_call
    token = Tokens.issue(:label => "T")
    id = token.dig("row", "id")
    log = CallLog.new
    row = { "id" => id }
    log.contact(row, "clientInfo" => { "name" => "codex-mcp-client", "version" => "0.167.0" })
    log.add(row, "invoke", {}, { "structuredContent" => { "status" => "completed" } }, 3)
    log.add(row, "discover", {}, { "structuredContent" => { "connection" => { "reason" => "not open" } } }, 3)
    log.add(row, "discover", {}, { "structuredContent" => { "status" => "busy", "code" => "session.busy" } }, 3)
    log.add(row, "context", {}, { "structuredContent" => { "status" => "failed" }, "isError" => false }, 3)
    assert_equal [false, false, false, false], log.take_unread.map { |call| call["verifies"] }
    Listener.calls_made([], log.take_contacts)
    assert_equal "codex-mcp-client 0.167.0", Listener.contacts.dig(id, "client")
    assert_empty Listener.verified

    log.add(row, "context", {}, { "structuredContent" => { "status" => "completed" } }, 3)
    Listener.calls_made(log.take_unread)
    refute_nil Listener.verified[id]
  end

  private

  def connection_rows
    Dialog.connections(46_110)
  end

  def issue(dialog, label)
    dialog.fire(Dialog::CALLBACK, JSON.generate("type" => "access.issue",
                                                "payload" => { "label" => label, "capabilities" => ["read"] }))
    delivered(dialog, "access.issued").last
  end

  def connect(dialog, token, extra = {})
    payload = { "client" => "codex", "token" => token, "profile" => "default" }.merge(extra)
    dialog.fire(Dialog::CALLBACK, JSON.generate("type" => "access.connect", "payload" => payload))
  end

  def delivered(dialog, type)
    dialog.scripts.filter_map do |script|
      message = JSON.parse(script[/receive\((.*)\)\z/m, 1])
      message.fetch("payload") if message.fetch("type") == type
    end
  end

  # Python's own TOML parser reads the file, so a check never shares the scanner it checks. Skipped where
  # python3 has no tomllib (before 3.11).
  def assert_valid_toml(text)
    output, status = Open3.capture2e("python3", "-c", "import sys, tomllib; tomllib.loads(sys.stdin.read())",
                                     :stdin_data => text)
    skip "python3 has no tomllib" if output.include?("No module named 'tomllib'")
    assert status.success?, output
  end

  # Only the issuing reply carries a secret; no state, replacement, answer or failure does.
  def assert_no_secret(dialog, *secrets)
    dialog.scripts.reject { |script| script.include?("\"access.issued\"") }.each do |script|
      secrets.each { |secret| refute_includes script, secret }
    end
  end
end
