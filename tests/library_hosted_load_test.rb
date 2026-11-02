# frozen_string_literal: true

require_relative "test_helper"

# Version 2 loads: begun by the load command, polled on host timers, published only as a complete
# admitted snapshot, and dropped when the connection, the session or a newer load moved on.
class LibraryHostedLoadTest < PhComposerTestCase
  include HostedLibraryFixtures

  API = PhComposer::API
  Manager = PhComposer::Library::Connection::Manager
  SELECTED = { "provider_id" => PROVIDER_ID, "kind" => "materials" }.freeze

  def setup
    super
    PhComposer::Registry.install([HostedLibraryFixtures::Feature])
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @context = API.connect(:session_id => @session.id, :capabilities => %w[read setup])
    @server = HostedLibraryFixtures.server
    @now = 100.0
    Manager.clock = -> { @now }
    connection.finish_sign_in
  end

  def connection
    Manager.connection(PhComposer::Registry.current.library_providers.fetch(PROVIDER_KIND))
  end

  def load
    API.setup(:context => @context, :name => "ph_composer.library.load", :params => SELECTED)
  end

  def catalog
    API.query(:context => @context, :name => "ph_composer.library.catalog", :params => SELECTED).fetch("value")
  end

  def state_of_catalog
    API.query(:context => @context, :name => "ph_composer.library.providers").fetch("value")
       .find { |row| row.fetch("id") == PROVIDER_ID }.fetch("catalogs").first.fetch("state")
  end

  def test_a_load_is_loading_until_polled_complete_then_ready_with_its_snapshot
    started = load
    assert_equal %w[completed loading], [started.fetch("status"), started.dig("value", "state")]
    kind, handed, operation = @server.begun.first
    assert_equal "materials", kind
    assert_same connection, handed
    assert_equal operation.generation, Manager.generation(PhComposer::Registry.current.library_providers
                                                                             .fetch(PROVIDER_KIND))
    UI.run_next_timer
    assert_equal "loading", state_of_catalog
    @server.response = hosted_response
    UI.run_timers
    page = catalog
    assert_equal %w[ready rec-1], [page.fetch("state"), page.fetch("rows").first.fetch("record_id")]
    assert_equal({ "id" => "snap-1", "library_revision" => 7, "projection_schema_version" => 1 }, page["snapshot"])
    assert_equal %w[library_id library_name record_id snapshot wire_schema_version display_label].sort,
                 page.fetch("rows").first.keys.sort
  end

  def test_an_empty_ready_snapshot_differs_from_a_failed_load_with_nothing_kept
    load
    @server.response = hosted_response(:rows => [])
    UI.run_timers
    assert_equal ["ready", 0], [catalog.fetch("state"), catalog.fetch("total")]
    PhComposer::Library::State.for(@session).remove(PROVIDER_ID)
    load
    @server.failures[:poll_load] = PhComposer::Library::Error.new("library.hosted_snapshot_gone", "gone")
    UI.run_timers
    assert_equal %w[unavailable library.hosted_snapshot_gone], [catalog.fetch("state"), catalog.dig("failure", "code")]
    assert_nil catalog.fetch("generation")
  end

  def test_a_failed_reload_keeps_the_last_complete_snapshot_as_stale_with_an_undeclared_code_reduced
    load
    @server.response = hosted_response
    UI.run_timers
    generation = catalog.fetch("generation")
    load
    @server.failures[:poll_load] = RuntimeError.new("https://example.invalid/library?token=abc")
    UI.run_timers
    page = catalog
    assert_equal ["stale", generation, "library.provider_failed"],
                 [page.fetch("state"), page.fetch("generation"), page.dig("failure", "code")]
    assert_equal ["rec-1"], page.fetch("rows").map { |row| row.fetch("record_id") }
    refute_includes JSON.generate(page), "token"
    assert_equal 1, @server.cancelled.length
  end

  def test_cancel_keeps_the_published_snapshot_and_a_late_answer_is_never_published
    load
    @server.response = hosted_response
    UI.run_timers
    generation = catalog.fetch("generation")
    load
    cancelled = API.setup(:context => @context, :name => "ph_composer.library.cancel_load", :params => SELECTED)
    assert_equal({ "cancelled" => true }, cancelled.fetch("value"))
    assert_equal [@server.begun.last[2].id], @server.cancelled
    @server.response = hosted_response(:snapshot => "snap-late")
    UI.run_timers
    assert_equal ["cancelled", generation, "snap-1"],
                 [catalog.fetch("state"), catalog.fetch("generation"), catalog.dig("snapshot", "id")]
    second = API.setup(:context => @context, :name => "ph_composer.library.cancel_load", :params => SELECTED)
    assert_equal({ "cancelled" => false }, second.fetch("value"))
  end

  def test_a_newer_load_replaces_a_running_one_whose_answer_is_dropped
    load
    first = @server.begun.last[2]
    load
    assert_equal [first.id], @server.cancelled
    @server.response = hosted_response
    UI.run_timers
    assert_equal 1, catalog.fetch("generation")
    refute_includes @server.polled, first.id
  end

  def test_a_disconnect_during_a_load_drops_it_and_clears_the_catalog
    load
    @server.response = hosted_response
    UI.run_timers
    load
    API.setup(:context => @context, :name => "ph_composer.library.connections.disconnect",
              :params => { "provider_kind" => PROVIDER_KIND })
    polled = @server.polled.length
    UI.run_timers
    assert_equal polled, @server.polled.length
    assert_equal ["unloaded", nil], [catalog.fetch("state"), catalog.fetch("generation")]
    refused = load
    assert_equal %w[refused library.connection_required], refused.values_at("status", "code")
  end

  def test_a_reauthorize_during_a_load_ends_it_cancelled_with_the_last_snapshot_kept
    load
    @server.response = hosted_response
    UI.run_timers
    @server.response = nil
    load
    running = @server.begun.last[2].id
    API.setup(:context => @context, :name => "ph_composer.library.connections.reauthorize",
              :params => { "provider_kind" => PROVIDER_KIND })
    assert_includes @server.cancelled, running
    @server.response = hosted_response(:snapshot => "snap-late")
    UI.run_timers
    assert_equal %w[cancelled snap-1], [catalog.fetch("state"), catalog.dig("snapshot", "id")]
  end

  def test_a_closed_session_or_a_lost_authorization_ends_or_refuses_the_load
    load
    @session.detach
    UI.run_timers
    assert_empty @server.polled
    connection.lose_authorization
    session = PhComposer::Sessions.for(Sketchup.active_model)
    context = API.connect(:session_id => session.id, :capabilities => %w[read setup])
    refused = API.setup(:context => context, :name => "ph_composer.library.load", :params => SELECTED)
    assert_equal "library.reauthorization_required", refused.fetch("code")
  end

  def test_begin_load_keeps_a_declared_code_and_a_load_that_never_answers_times_out
    @server.failures[:begin_load] = PhComposer::Library::Error.new("library.hosted_busy", "busy")
    assert_equal "library.hosted_busy", load.fetch("code")
    assert_equal %w[unavailable library.hosted_busy], [catalog.fetch("state"), catalog.dig("failure", "code")]
    @server.failures.clear
    load
    @server.response = hosted_response
    UI.run_timers
    @server.failures[:begin_load] = RuntimeError.new("busy")
    assert_equal "library.provider_failed", load.fetch("code")
    assert_equal ["stale", 1, ["rec-1"]], [catalog.fetch("state"), catalog.fetch("generation"),
                                           catalog.fetch("rows").map { |row| row.fetch("record_id") }]
    @server.failures.clear
    @server.response = nil
    load
    UI.run_next_timer
    @now += PhComposer::Library::Connection::Load::TIMEOUT_SECONDS + 1
    UI.run_timers
    assert_equal %w[stale library.load_timeout], [catalog.fetch("state"), catalog.dig("failure", "code")]
  end

  # Every row needs exactly one positive revision under its own key; any break refuses the snapshot.
  def test_snapshot_revisions_must_name_each_row_once_with_a_positive_integer
    load
    @server.response = hosted_response
    UI.run_timers
    generation = catalog.fetch("generation")
    two = [material("rec-1"), material("rec-2", :name => "Second")]
    cases = { "missing" => { "materials/firm-lib/rec-1" => 3 },
              "foreign" => { "materials/firm-lib/rec-1" => 3, "materials/firm-lib/rec-2" => 3,
                             "materials/other-lib/rec-9" => 1 },
              "zero" => { "materials/firm-lib/rec-1" => 0, "materials/firm-lib/rec-2" => 3 },
              "negative" => { "materials/firm-lib/rec-1" => -1, "materials/firm-lib/rec-2" => 3 },
              "not an integer" => { "materials/firm-lib/rec-1" => "3", "materials/firm-lib/rec-2" => 3 } }
    cases.each do |label, revisions|
      load
      @server.response = hosted_response(:rows => two, :revisions => revisions)
      UI.run_timers
      assert_equal ["stale", "library.source_revision_invalid", generation],
                   [catalog.fetch("state"), catalog.dig("failure", "code"), catalog.fetch("generation")], label
    end
    load
    @server.response = hosted_response(:rows => [material("rec-1"), material("rec-1")],
                                       :revisions => { "materials/firm-lib/rec-1" => 3 })
    UI.run_timers
    assert_equal "library.source_revision_invalid", catalog.dig("failure", "code"), "duplicate"
  end

  def test_an_unexpected_fault_while_publishing_ends_the_load_instead_of_leaving_it_loading
    admission = PhComposer::Library::Admission
    original = admission.method(:revisioned)
    admission.define_singleton_method(:revisioned) { |*_arguments, **_options| raise NoMethodError, "adapter fault" }
    load
    @server.response = hosted_response
    UI.run_timers
    assert_equal %w[unavailable library.provider_failed], [catalog.fetch("state"), catalog.dig("failure", "code")]
    assert_equal 0, UI.timer_count
  ensure
    admission.define_singleton_method(:revisioned, original)
  end

  # A connection id that changes during the poll drops the answer, even if the extension never said so.
  def test_an_answer_whose_poll_moved_the_connection_on_is_not_published
    load
    @server.response = hosted_response
    swapped = connection
    @server.define_singleton_method(:response) do
      swapped.instance_variable_set(:@connection_id, "connection-2")
      @response
    end
    UI.run_timers
    assert_nil catalog.fetch("generation")
  end

  def test_a_malformed_snapshot_identity_is_refused_before_admission
    error = assert_raises(PhComposer::Library::Error) do
      hosted_response(:library_revision => 0)
    end
    assert_equal "library.provider_invalid", error.code
    load
    @server.response = "not a snapshot"
    UI.run_timers
    assert_equal "library.provider_invalid", catalog.dig("failure", "code")
  end
end
