# frozen_string_literal: true

require_relative "test_helper"

# Connect (context/AGENT_INTERFACE.md, "Security posture"): the token a client uses is saved in that
# client's owner-only file, the client is set up once to read it there, a new token changes only the
# file, and the file goes when its token is no longer live.
class AgentAccessConnectionsTest < PhComposerTestCase
  Tokens = PhComposer::AgentAccess::Tokens
  Dialog = PhComposer::AgentAccess::Dialog
  Connections = PhComposer::AgentAccess::Connections
  ClientSetup = PhComposer::AgentAccess::ClientSetup
  ClientConfig = PhComposer::AgentAccess::ClientConfig

  def setup
    super
    PhComposer.compose
    @runs = []
    @answers = []
    ClientSetup.runner = lambda do |argv|
      @runs << argv
      @answers.shift || [true, ""]
    end
  end

  def test_the_saved_token_is_owner_only_holds_the_header_and_a_new_token_replaces_it
    first = Tokens.issue.fetch("token")
    Connections.write("codex", first)
    second = Tokens.issue.fetch("token")
    Connections.write("codex", second)

    path = Connections.path("codex")
    assert_equal({ "Authorization" => "Bearer #{second}" }, JSON.parse(File.read(path)))
    assert_equal 0o600, File.stat(path).mode & 0o777
    assert_equal 0o700, File.stat(Connections.directory).mode & 0o777
    assert_equal ["codex.json"], Dir.children(Connections.directory), "no temporary file is left"
    assert_equal({ "codex" => Tokens.digest(second) }, Connections.digests)
  end

  def test_a_folder_that_is_a_link_is_refused_and_nothing_is_written
    target = Dir.mktmpdir("elsewhere")
    File.symlink(target, Connections.directory)

    error = assert_raises(PhComposer::CodedError) { Connections.write("codex", Tokens.issue.fetch("token")) }
    assert_equal "agent_access.connection_unavailable", error.code
    assert_empty Dir.children(target)
  ensure
    FileUtils.rm_rf(target)
  end

  def test_revoking_or_resetting_deletes_the_saved_copy_of_that_token_only
    kept = Tokens.issue
    gone = Tokens.issue
    Connections.write("claude_code", gone.fetch("token"))
    Connections.write("codex", kept.fetch("token"))

    Tokens.revoke(gone.dig("row", "id"))

    refute File.exist?(Connections.path("claude_code"))
    assert File.exist?(Connections.path("codex"))
    Sketchup.write_default(Tokens::SECTION, Tokens::KEY, "not base64 json")
    Tokens.reset
    refute File.exist?(Connections.path("codex"))
  end

  def test_a_client_file_that_cannot_be_read_never_stops_a_revoke_and_is_deleted_with_it
    issued = Tokens.issue
    Connections.write("codex", issued.fetch("token"))
    File.binwrite(Connections.path("codex"), "{\"Authorization\":\"Bearer \xFF\"}")
    File.binwrite(Connections.path("claude_code"), "not json")

    assert_empty Connections.digests
    Tokens.revoke(issued.dig("row", "id"))

    refute File.exist?(Connections.path("codex"))
    refute File.exist?(Connections.path("claude_code"))
    assert_equal 0, Tokens.snapshot.length
  end

  def test_connect_claude_code_runs_add_json_without_the_token_and_replaces_an_entry_that_exists
    token = Tokens.issue.fetch("token")
    binary = "/opt/homebrew/bin/claude"
    @answers = [[false, "MCP server ph-composer already exists in user config"], [true, ""], [true, ""]]

    result = ClientSetup.stub(:claude_binary, binary) { ClientSetup.connect("claude_code", token, 46_110) }

    server = JSON.generate(ClientConfig.claude_server(46_110))
    add = [binary, "mcp", "add-json", "--scope", "user", "ph-composer", server]
    assert_equal [add, [binary, "mcp", "remove", "--scope", "user", "ph-composer"], add], @runs
    refute(@runs.flatten.any? { |part| part.include?(token) })
    assert_equal "configured", result.fetch("state")
    assert_includes result.fetch("message"), "start a new Claude Code session"
    assert_includes result.fetch("message"), "SketchUp does not need a restart"
    assert_equal({ "claude_code" => Tokens.digest(token) }, Connections.digests)
  end

  def test_connect_claude_code_without_the_command_saves_the_token_and_says_to_run_the_command
    ClientSetup.stub(:claude_binary, nil) do
      result = ClientSetup.connect("claude_code", Tokens.issue.fetch("token"), 46_110)

      assert_equal "manual", result.fetch("state")
      assert_includes result.fetch("message"), "could not find the claude command"
      assert_includes result.fetch("message"), "start a new Claude Code session"
    end
    assert_empty @runs
    assert File.exist?(Connections.path("claude_code"))
  end

  def test_connect_claude_code_runs_nothing_when_its_settings_already_hold_the_entry
    server = ClientConfig.claude_server(46_110)
    File.write(ClientSetup.claude_settings, JSON.generate("mcpServers" => { "ph-composer" => server }))

    result = ClientSetup.stub(:claude_binary, "/opt/homebrew/bin/claude") do
      ClientSetup.connect("claude_code", Tokens.issue.fetch("token"), 46_110)
    end

    assert_equal "configured", result.fetch("state")
    assert_empty @runs, "a new token changes only the file"
  end

  def test_a_failed_add_json_never_removes_the_entry_it_could_not_replace
    token = Tokens.issue.fetch("token")
    @answers = [[false, "Invalid configuration\nmore"]]

    result = ClientSetup.stub(:claude_binary, "/opt/homebrew/bin/claude") do
      ClientSetup.connect("claude_code", token, 46_110)
    end

    assert_equal 1, @runs.length
    assert_equal "manual", result.fetch("state")
    assert_includes result.fetch("message"), "(Invalid configuration)"
  end

  def test_connect_codex_appends_its_block_keeping_every_byte_already_in_the_config
    Dir.mkdir(ClientSetup.codex_home)
    config = File.join(ClientSetup.codex_home, "config.toml")
    before = "# my settings\nmodel = \"gpt\"\n\n[mcp_servers.other]\nurl = \"http://x\"  # keep"
    File.binwrite(config, before)

    result = ClientSetup.connect("codex", Tokens.issue.fetch("token"), 46_110)

    assert_equal "configured", result.fetch("state")
    assert_equal "#{before}\n\n#{ClientConfig.codex_block(46_110)}\n", File.binread(config)
    assert_includes result.fetch("message"), "start a new Codex session"
    assert_empty @runs
  end

  def test_connect_codex_leaves_a_config_that_names_the_server_as_it_is
    Dir.mkdir(ClientSetup.codex_home)
    config = File.join(ClientSetup.codex_home, "config.toml")
    File.binwrite(config, "#{ClientConfig.codex_block(46_110)}\n\n# a comment\n[other]\n")
    same = ClientSetup.connect("codex", Tokens.issue.fetch("token"), 46_110)
    old = "[mcp_servers.ph-composer]\nurl = \"http://127.0.0.1:46110/mcp\"\nbearer_token_env_var = \"X\"\n"
    File.binwrite(config, old)
    other = ClientSetup.connect("codex", Tokens.issue.fetch("token"), 46_110)

    assert_equal "configured", same.fetch("state")
    assert_equal "manual", other.fetch("state")
    assert_includes other.fetch("message"), "already names the ph-composer server"
    assert_equal old, File.binread(config)
  end

  # A second definition in any TOML form would make the whole file invalid for Codex; a project folder
  # whose path holds the name is not a definition.
  def test_connect_codex_never_appends_beside_another_form_of_the_server_and_ignores_paths_with_its_name
    Dir.mkdir(ClientSetup.codex_home)
    config = File.join(ClientSetup.codex_home, "config.toml")
    ["mcp_servers.ph-composer.url = \"x\"\n", "mcp_servers = { 'ph-composer' = { url = \"x\" } }\n",
     "[mcp_servers.\"ph-composer\".tools]\nx = 1\n", "mcp_servers = {}\n", "mcp_servers.other.url = \"x\"\n",
     "[mcp_servers.\"ph\\u002dcomposer\"]\nurl = \"x\"\n", "[mcp_servers]\nother = { url = \"x\" }\n"].each do |form|
      File.binwrite(config, form)
      assert_equal "manual", ClientSetup.connect("codex", Tokens.issue.fetch("token"), 46_110).fetch("state"), form
      assert_equal form, File.binread(config)
    end
    File.binwrite(config, "[projects.\"/Users/someone/ph-composer\"]\ntrust_level = \"trusted\"\n")
    assert_equal "configured", ClientSetup.connect("codex", Tokens.issue.fetch("token"), 46_110).fetch("state")
  end

  def test_connect_codex_without_codex_saves_the_token_and_creates_no_codex_folder
    result = ClientSetup.connect("codex", Tokens.issue.fetch("token"), 46_110)

    assert_equal "manual", result.fetch("state")
    assert_includes result.fetch("message"), "Codex is not set up on this computer"
    refute File.exist?(ClientSetup.codex_home)
    assert File.exist?(Connections.path("codex"))
  end

  def test_the_dialog_connects_only_a_live_token_and_lists_the_client_beside_it
    Dir.mkdir(ClientSetup.codex_home)
    dialog = Dialog.show
    dialog.fire(Dialog::CALLBACK, access_message("access.issue", "label" => "Codex", "capabilities" => ["read"]))
    issued = delivered(dialog, "access.issued").last
    dialog.fire(Dialog::CALLBACK, access_message("access.connect", "client" => "codex", "token" => issued["token"]))
    dialog.fire(Dialog::CALLBACK, access_message("access.connect", "client" => "codex", "token" => "ab" * 24))
    dialog.fire(Dialog::CALLBACK, access_message("access.connect", "client" => "shell", "token" => issued["token"]))

    assert_equal ["codex", "configured"], delivered(dialog, "access.connected").last.values_at("client", "state")
    assert_equal ["Codex"], delivered(dialog, "access.state").last.dig("tokens", 0, "connected")
    failures = delivered(dialog, "access.failure").map { |failure| failure.fetch("message") }
    assert_equal 2, failures.length
    assert_includes failures.first, "no longer live"
    assert_equal 1, delivered(dialog, "access.connected").length
  end

  # The runner itself, on real processes: no shell, an environment of three names, a time limit that ends
  # the command, and output kept short without blocking the command.
  def test_a_command_runs_with_only_its_environment_and_ends_at_the_time_limit
    ClientSetup.runner = nil
    ClientSetup.timeout = 1
    deadline = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1 }

    done, printed = ClientSetup.send(:run, ["/usr/bin/env"], deadline.call)
    assert done
    assert_equal %w[HOME PATH USER], printed.lines.map { |line| line[/\A[^=]+/] }.sort

    script = File.join(@agent_home, "chatty")
    File.write(script, "#!/bin/sh\nhead -c 200000 /dev/zero | tr '\\000' a\nprintf '\\377'\n")
    File.chmod(0o700, script)
    done, printed = ClientSetup.send(:run, [script], deadline.call)
    assert done
    assert_equal ClientSetup::MAX_OUTPUT, printed.bytesize
    assert printed.valid_encoding?

    # The command leaves on TERM; what it started ignores TERM and is ended with the group.
    pid_file = File.join(@agent_home, "child.pid")
    File.write(script, "#!/bin/sh\n(trap '' TERM; exec sleep 30) &\necho $! > '#{pid_file}'\nsleep 30\n")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    done, printed = ClientSetup.send(:run, [script], deadline.call)
    refute done
    assert_includes printed, "did not answer"
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
    child = File.read(pid_file).to_i
    assert(20.times.any? { (Process.kill(0, child) && sleep(0.05) && false) rescue true }, "the child was left running")
  end

  private

  def access_message(type, payload = {})
    JSON.generate("type" => type, "payload" => payload)
  end

  def delivered(dialog, type)
    dialog.scripts.filter_map do |script|
      message = JSON.parse(script[/receive\((.*)\)\z/m, 1])
      message.fetch("payload") if message.fetch("type") == type
    end
  end
end
