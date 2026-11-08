# frozen_string_literal: true

require_relative "test_helper"

# Agent access tokens and the Agent Access dialog (context/AGENT_INTERFACE.md, "User-controlled local
# access"): a token is issued once, stored only as its digest, listed and revoked by the user, and never
# reachable through PhComposer::API.
class AgentAccessTokensTest < PhComposerTestCase
  Tokens = PhComposer::AgentAccess::Tokens
  Dialog = PhComposer::AgentAccess::Dialog

  def setup
    super
    PhComposer.compose
  end

  def test_a_token_is_returned_once_and_stored_only_as_its_digest
    issued = Tokens.issue(:label => "Claude Code")
    token = issued.fetch("token")

    assert_match(/\A\h{48}\z/, token)
    assert_equal %w[id label capabilities created_at last_used_at revoked_at].sort, issued.fetch("row").keys.sort
    assert_equal %w[read], issued.dig("row", "capabilities")
    stored = Sketchup.read_default(Tokens::SECTION, Tokens::KEY).unpack1("m0")
    refute_includes stored, token
    assert_includes stored, Tokens.digest(token)
    assert_equal [issued.fetch("row")], Tokens.list
    refute_includes JSON.generate(Tokens.list), Tokens.digest(token)
  end

  def test_the_snapshot_is_keyed_by_digest_frozen_and_holds_only_live_tokens
    kept = Tokens.issue
    gone = Tokens.issue
    Tokens.revoke(gone.dig("row", "id"))

    snapshot = Tokens.snapshot

    assert_equal [Tokens.digest(kept.fetch("token"))], snapshot.keys
    assert_equal kept.fetch("row"), snapshot.values.first
    assert snapshot.frozen? && snapshot.values.first.frozen?
    assert Tokens.live?
  end

  def test_revoking_keeps_a_dated_row_and_is_idempotent
    row = Tokens.issue(:label => "Codex").fetch("row")

    Tokens.revoke(row.fetch("id"))
    again = Tokens.revoke(row.fetch("id"))

    refute_nil again.first.fetch("revoked_at")
    refute Tokens.live?
    error = assert_raises(PhComposer::CodedError) { Tokens.revoke("token_AAAAAAAAAAAA") }
    assert_equal "agent_access.token_unknown", error.code
  end

  def test_default_labels_count_up_and_labels_are_checked
    assert_equal ["Agent token 1", "Agent token 2"], Array.new(2) { Tokens.issue.dig("row", "label") }
    error = assert_raises(PhComposer::CodedError) { Tokens.issue(:label => "x" * 81) }
    assert_equal "params.invalid", error.code
  end

  def test_capabilities_must_hold_read_and_only_what_is_offered
    [[], %w[model_write], %w[read eval]].each do |capabilities|
      error = assert_raises(PhComposer::CodedError) { Tokens.issue(:capabilities => capabilities) }
      assert_equal "params.invalid", error.code
    end
    granted = Tokens.issue(:capabilities => %w[export view read model_write setup capture]).dig("row", "capabilities")
    assert_equal PhComposer::CallerRegistry::CAPABILITIES, granted
  end

  def test_a_model_only_token_keeps_its_path_in_the_store_and_shows_only_the_file_name
    issued = Tokens.issue(:model_file => "/projects/a/house.skp")
    stored = Sketchup.read_default(Tokens::SECTION, Tokens::KEY).unpack1("m0")

    assert_equal "house.skp", issued.dig("row", "model_name")
    assert_includes stored, "/projects/a/house.skp"
    refute_includes JSON.generate(Tokens.list), "/projects/a"
    assert_equal "/projects/a/house.skp", Tokens.snapshot.values.first.fetch("model_file")
    assert_equal "readable", Tokens.state
    error = assert_raises(PhComposer::CodedError) { Tokens.issue(:model_file => "") }
    assert_equal "agent_access.model_unsaved", error.code
  end

  def test_at_most_eight_tokens_are_live_and_revoking_frees_a_place
    rows = Array.new(Tokens::MAX_LIVE) { Tokens.issue.fetch("row") }
    error = assert_raises(PhComposer::CodedError) { Tokens.issue }
    assert_equal "agent_access.limit", error.code

    Tokens.revoke(rows.first.fetch("id"))

    assert Tokens.issue.fetch("token")
  end

  def test_an_unreadable_store_is_reported_refused_and_reset_on_request
    Sketchup.write_default(Tokens::SECTION, Tokens::KEY, ["not json"].pack("m0"))

    assert_equal "unreadable", Tokens.state
    error = assert_raises(PhComposer::CodedError) { Tokens.issue }
    assert_equal "agent_access.store_unreadable", error.code
    Tokens.reset
    assert_equal ["readable", []], [Tokens.state, Tokens.list]
  end

  def test_a_store_with_a_repeated_id_a_missing_field_or_over_the_byte_cap_is_unreadable_and_resets
    row = { "id" => "token_AAAAAAAAAAAA", "label" => "A", "capabilities" => ["read"],
            "created_at" => "2026-10-18T12:00:00Z",
            "last_used_at" => nil, "revoked_at" => nil, "token_sha256" => "a" * 64 }
    twin = row.merge("token_sha256" => "b" * 64)
    oversized = Array.new(300) do |index|
      row.merge("id" => format("token_%012d", index), "label" => "x" * 80, "token_sha256" => format("%064x", index))
    end
    incomplete = [row.reject { |key, _value| key == "revoked_at" }]
    [[row, twin], oversized, incomplete].each do |tokens|
      Sketchup.write_default(Tokens::SECTION, Tokens::KEY, [JSON.generate("tokens" => tokens)].pack("m0"))

      assert_equal ["unreadable", {}], [Tokens.state, Tokens.snapshot]
      Tokens.reset
      assert_equal "readable", Tokens.state
    end
  end

  def test_a_revoke_near_the_byte_cap_drops_older_tombstones_rather_than_failing
    long = "/projects/#{'\u00e9' * 400}/house.skp"
    Tokens::MAX_REVOKED.times do |index|
      Tokens.revoke(Tokens.issue(:label => "x" * 80, :model_file => "#{long}#{index}").dig("row", "id"))
    end
    live = Tokens.issue(:label => "y" * 80, :model_file => long)

    Tokens.revoke(live.dig("row", "id"))

    refute Tokens.live?
    assert_empty Tokens.snapshot
    stored = Sketchup.read_default(Tokens::SECTION, Tokens::KEY).unpack1("m0")
    assert_operator stored.bytesize, :<=, Tokens::MAX_STORED_BYTES
  end

  def test_the_most_recently_revoked_rows_are_kept
    old = Tokens.issue(:label => "Old").fetch("row")
    Tokens::MAX_REVOKED.times do |index|
      Tokens.revoke(Tokens.issue(:label => "Short #{index}").dig("row", "id"))
    end

    Tokens.revoke(old.fetch("id"))

    revoked = Tokens.list.reject { |row| row["revoked_at"].nil? }
    assert_equal Tokens::MAX_REVOKED, revoked.length
    assert_includes revoked.map { |row| row["label"] }, "Old"
    refute_includes revoked.map { |row| row["label"] }, "Short 0"
  end

  def test_nothing_about_tokens_is_reachable_through_the_api
    token = Tokens.issue(:label => "Hidden").fetch("token")
    found = PhComposer::API.discover

    assert_includes found.fetch("features").map { |feature| feature.fetch("id") }, PhComposer::AgentAccess::FEATURE_ID
    operations = %w[queries view_commands setup_commands file_exports actions].flat_map { |kind| found.fetch(kind) }
    assert_empty operations.select { |entry| entry.fetch("owner") == PhComposer::AgentAccess::FEATURE_ID }
    text = JSON.generate(found)
    refute_includes text, token
    refute_includes text, Tokens.digest(token)
    refute_includes text, "Hidden"
  end

  def test_the_menu_item_opens_one_dialog_outside_the_viewport_menu
    item = PhComposer::Registry.current.menu_items.fetch("#{PhComposer::AgentAccess::FEATURE_ID}.open")

    item.handler.call(nil)
    dialog = item.handler.call(nil)

    assert_equal "Agent Access", item.menu
    refute item.available.call(nil)
    assert_equal 1, dialog.bring_to_front_count
    assert_equal File.expand_path(Dialog::PAGE), File.expand_path(dialog.file)
    refute PhComposer::Panel.open?
  end

  def test_the_dialog_issues_lists_and_revokes_through_its_own_messages
    dialog = Dialog.show
    dialog.fire(Dialog::CALLBACK, access_message("access.ready"))
    dialog.fire(Dialog::CALLBACK, access_message("access.issue", "label" => "Claude Code", "capabilities" => ["read"]))
    issued = delivered(dialog, "access.issued").last
    dialog.fire(Dialog::CALLBACK, access_message("access.revoke", "id" => issued.dig("row", "id")))

    states = delivered(dialog, "access.state")
    assert_equal [[], [issued.fetch("row").merge("last_call" => nil, "connected" => [])]],
                 states.first(2).map { |state| state.fetch("tokens") }
    refute_nil states.last.dig("tokens", 0, "revoked_at")
    assert_equal "listening", states[1].dig("server", "state")
    assert_equal({ "state" => "stopped", "port" => 46_110 }, states.last.fetch("server"))
    assert_equal 1, delivered(dialog, "access.issued").length
  end

  def stopped_events
    PhComposer::Diagnostics.tail.select { |line| line.include?('"agent_access_stopped"') }
  end

  def test_diagnostics_record_the_listener_stopping_after_the_last_revoke
    first = Tokens.issue(:label => "First").fetch("row")
    last = Tokens.issue(:label => "Last").fetch("row")

    Tokens.revoke(first.fetch("id"))
    assert_empty stopped_events, "a live token remains, so the listener keeps running"
    Tokens.revoke(last.fetch("id"))
    PhComposer::AgentAccess::Listener.refresh

    assert_equal 1, stopped_events.length, "logged once, by the refresh that stopped a running listener"
    assert_equal "no_live_token", JSON.parse(stopped_events.first).fetch("status")
  end

  # The last revoke answers a waiting call first and only asks the server to stop on its next tick; a new
  # token can cancel that, so the server records the stop when it happens (AgentAccessServerTest).
  def test_a_stop_a_waiting_call_defers_is_not_recorded_until_it_happens
    waiting = StubAgentServer.new(46_110)
    deferred = []
    waiting.define_singleton_method(:refuse_revoked) { |_live| { "token" => 1 } }
    waiting.define_singleton_method(:stop_soon) { deferred << :stop_soon }
    PhComposer::AgentAccess::Listener.server_factory = ->(_port) { waiting }
    row = Tokens.issue(:label => "Only").fetch("row")

    Tokens.revoke(row.fetch("id"))

    assert_equal [:stop_soon], deferred
    assert_empty stopped_events
  end

  def test_a_token_whose_listener_cannot_bind_is_not_kept_and_the_dialog_says_why
    taken = Struct.new(:port) do
      def start
        raise Errno::EADDRINUSE
      end
    end
    PhComposer::AgentAccess::Listener.server_factory = ->(port) { taken.new(port) }
    dialog = Dialog.show

    dialog.fire(Dialog::CALLBACK, access_message("access.issue", "label" => "Late", "capabilities" => ["read"]))

    assert_empty delivered(dialog, "access.issued")
    assert_includes delivered(dialog, "access.failure").last.fetch("message"), "in use"
    refute Tokens.live?
  end

  def test_a_refused_or_malformed_message_answers_a_failure_and_issues_nothing
    dialog = Dialog.show
    dialog.fire(Dialog::CALLBACK, access_message("access.issue", "label" => nil, "capabilities" => %w[read eval]))
    dialog.fire(Dialog::CALLBACK, access_message("access.issue", "label" => nil, "capabilities" => ["read"], "x" => 1))
    dialog.fire(Dialog::CALLBACK, "not json")

    assert_equal 3, delivered(dialog, "access.failure").length
    assert_empty Tokens.list
  end

  def test_this_model_only_binds_the_saved_active_model_and_an_unsaved_one_is_refused
    dialog = Dialog.show
    dialog.fire(Dialog::CALLBACK, access_message("access.issue", "label" => "Unsaved", "capabilities" => ["read"],
                                                                 "model_only" => true))
    Sketchup.active_model.path = "/projects/a/house.skp"
    dialog.fire(Dialog::CALLBACK, access_message("access.ready"))
    shown = delivered(dialog, "access.state").last.fetch("model")
    Sketchup.active_model.path = "/projects/b/house.skp"
    dialog.fire(Dialog::CALLBACK, access_message("access.issue", "label" => "Moved", "capabilities" => ["read"],
                                                                 "model_only" => shown.fetch("key")))
    Sketchup.active_model.path = "/projects/a/house.skp"
    dialog.fire(Dialog::CALLBACK, access_message("access.issue", "label" => "Bound", "capabilities" => ["read"],
                                                                 "model_only" => shown.fetch("key")))

    failures = delivered(dialog, "access.failure").map { |failure| failure.fetch("message") }
    assert_includes failures.first, "Save this Model first"
    assert_includes failures.last, "open Model changed"
    assert_equal "house.skp", shown.fetch("name")
    refute_includes JSON.generate(shown), "/projects"
    assert_equal [["Bound", "house.skp"]], Tokens.list.map { |row| row.values_at("label", "model_name") }
  end

  def test_the_page_sends_and_handles_exactly_the_declared_messages
    page = File.read(File.join(SOURCE_ROOT, "ph_composer", "html", "agent_access", "page.js"))

    assert_equal Dialog::INBOUND.keys.sort, page.scan(/(?:send|post)\("(access\.[a-z]+)"/).flatten.uniq.sort
    assert_equal Dialog::OUTBOUND.keys.sort, page.scan(/message\.type === "(access\.[a-z]+)"/).flatten.uniq.sort
    assert_raises(ArgumentError) { Dialog.script("access.state", "secret" => 1) }
  end

  private

  def access_message(type, payload = {})
    JSON.generate("type" => type, "payload" => payload)
  end

  def delivered(dialog, type)
    dialog.scripts.filter_map do |script|
      body = JSON.parse(script[/receive\((.*)\)\z/m, 1])
      body.fetch("payload") if body.fetch("type") == type
    end
  end
end
