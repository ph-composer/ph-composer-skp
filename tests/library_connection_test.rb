# frozen_string_literal: true

require_relative "test_helper"

# The version 2 declaration, its connection lifecycle and the Libraries setup commands, against the
# fake hosted library in support/hosted_library_fixtures.rb.
class LibraryConnectionTest < PhComposerTestCase
  include HostedLibraryFixtures

  API = PhComposer::API
  Registry = PhComposer::Registry
  Manager = PhComposer::Library::Connection::Manager
  PREFIX = "ph_composer.library.connections"

  def setup
    super
    Registry.install([HostedLibraryFixtures::Feature])
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @context = API.connect(:session_id => @session.id, :capabilities => %w[read setup])
  end

  def declaration
    Registry.current.library_providers.fetch(PROVIDER_KIND)
  end

  def connection
    Manager.connection(declaration)
  end

  def setup_call(name, params = { "provider_kind" => PROVIDER_KIND })
    API.setup(:context => @context, :name => name, :params => params)
  end

  def connections
    API.query(:context => @context, :name => PREFIX).fetch("value")
  end

  def probe(**options, &extra)
    Module.new do
      define_singleton_method(:name) { "HostedProbe" }
      define_singleton_method(:install) do |registry|
        scope = registry.feature("test.probe", :contract_version => 1)
        values = { :contract_version => 2, :kinds => ["materials"], :lifecycle => %i[connect disconnect],
                   :connection => ->(_context) { Object.new },
                   :refuses => REFUSES.slice(*PhComposer::Declarations::LIBRARY_PROVIDER_CALLBACKS, :connect,
                                             :disconnect) }
        scope.library_provider("test.probe.hosted", **values.merge(options)) { [] }
        extra&.call(scope)
      end
    end
  end

  def problems(feature)
    error = assert_raises(PhComposer::RegistrationError) { Registry.install([feature]) }
    error.diagnostics.map(&:message).join("\n")
  end

  def test_a_version_two_declaration_publishes_its_lifecycle_and_frozen_refusals_without_calling_factories
    called = []
    Registry.install([probe(:connection => ->(_context) { called << :connection })])
    published = Registry.current.library_providers.fetch("test.probe.hosted")
    assert_equal [2, %i[connect disconnect]], [published.contract_version, published.lifecycle]
    assert published.refuses.frozen?
    assert_equal ["library.hosted_busy"], published.refuses.fetch(:begin_load)
    assert_empty called
  end

  def test_version_two_refuses_missing_connection_lifecycle_or_refusals_and_version_one_refuses_them
    assert_match(/needs a callable connection factory/, problems(probe(:connection => nil)))
    assert_match(/lifecycle must be unique actions/, problems(probe(:lifecycle => %i[connect sign_in])))
    assert_match(/lifecycle must be unique actions/, problems(probe(:lifecycle => %i[connect connect disconnect])))
    no_disconnect = REFUSES.slice(*PhComposer::Declarations::LIBRARY_PROVIDER_CALLBACKS, :connect)
    assert_match(/including disconnect/, problems(probe(:lifecycle => [:connect], :refuses => no_disconnect)))
    missing = REFUSES.slice(:begin_load, :poll_load, :cancel_load)
    assert_match(/refuses must list codes for exactly/, problems(probe(:refuses => missing)))
    foreign = REFUSES.slice(*PhComposer::Declarations::LIBRARY_PROVIDER_CALLBACKS, :connect, :disconnect)
                     .merge(:connect => ["auth.mfa_required"])
    assert_match(/connect\.refuses must be unique library\.\* codes/, problems(probe(:refuses => foreign)))
    mixed = REFUSES.slice(*PhComposer::Declarations::LIBRARY_PROVIDER_CALLBACKS, :connect)
                   .merge("disconnect" => [])
    assert_match(/refuses must list codes for exactly/, problems(probe(:refuses => mixed)))
    assert_match(/lifecycle must be unique actions/, problems(probe(:lifecycle => [:connect, "disconnect"])))
    assert_match(/declares lifecycle, connection, refuses, which needs contract version 2/,
                 problems(probe(:contract_version => 1)))
    refute Registry.installed?("test.probe")
  end

  # Composer's own compose installs again what another extension installed; a test's reset does not.
  def test_an_extension_installed_after_composer_survives_a_new_composition
    PhComposer.compose
    assert Registry.installed?("test.hosted")
    assert Registry.current.library_providers.key?(PROVIDER_KIND)
    Registry.reset
    PhComposer.compose
    refute Registry.installed?("test.hosted")
  end

  def test_a_refused_reinstall_is_left_out_and_leaves_composer_composed
    Registry.install([probe])
    Registry.current.installed_batches[-1] = [probe(:lifecycle => [:sign_in])]
    PhComposer.compose
    assert Registry.installed?("ph_composer.library")
    refute Registry.installed?("test.probe")
    assert Registry.installed?("test.hosted")
  end

  def test_lifecycle_moves_through_states_and_each_action_but_settings_starts_a_new_generation
    assert_equal [{ "provider_kind" => PROVIDER_KIND, "label" => "Hosted test library", "state" => "disconnected",
                    "lifecycle" => %w[connect disconnect reauthorize settings] }], connections
    first = Manager.generation(declaration)
    connected = setup_call("#{PREFIX}.connect")
    assert_equal "authorizing", connected.dig("value", "state")
    connection.finish_sign_in
    assert_equal "connected", connections.first.fetch("state")
    assert_equal "Hosted test library: Synthetic firm", connections.first.fetch("label")
    assert_operator Manager.generation(declaration), :>, first
    before = Manager.generation(declaration)
    setup_call("#{PREFIX}.settings")
    assert_equal before, Manager.generation(declaration)
    assert_equal %i[connect settings], connection.calls
    setup_call("#{PREFIX}.reauthorize")
    assert_equal "authorizing", connections.first.fetch("state")
    assert_operator Manager.generation(declaration), :>, before
  end

  def test_a_lifecycle_refusal_keeps_only_a_declared_code_and_an_undeclared_action_is_refused
    HostedLibraryFixtures.server.failures[:connect] = PhComposer::Library::Error.new(
      "library.hosted_sign_in_refused", "Secret detail https://example.invalid/?token=abc"
    )
    refused = setup_call("#{PREFIX}.connect")
    assert_equal %w[refused library.hosted_sign_in_refused], refused.values_at("status", "code")
    refute_includes JSON.generate(refused), "token"
    HostedLibraryFixtures.server.failures[:connect] = RuntimeError.new("https://example.invalid/?token=abc")
    assert_equal "library.provider_failed", setup_call("#{PREFIX}.connect").fetch("code")
    Registry.install([probe])
    unavailable = setup_call("#{PREFIX}.reauthorize", "provider_kind" => "test.probe.hosted")
    assert_equal "library.lifecycle_unavailable", unavailable.fetch("code")
    assert_equal "library.provider_unavailable",
                 setup_call("#{PREFIX}.connect", "provider_kind" => "ph_composer.library.file").fetch("code")
  end

  def test_an_invalid_or_raising_status_reads_as_unavailable_under_the_declaration_name
    connection.define_singleton_method(:status) { { "state" => "signed_in", "label" => "Firm" } }
    assert_equal %w[unavailable test.hosted.library], connections.first.values_at("state", "label")
    connection.define_singleton_method(:status) { raise "https://example.invalid/?token=abc" }
    assert_equal "unavailable", connections.first.fetch("state")
  end

  def test_a_pairing_display_shows_only_while_authorizing_and_only_when_well_formed
    shown = lambda do |state, pairing|
      connection.define_singleton_method(:status) do
        { "state" => state, "label" => "Hosted test library", "pairing_display" => pairing }
      end
      connections.first.values_at("state", "pairing_display")
    end
    assert_equal %w[authorizing AB12-CD34], shown.call("authorizing", "AB12-CD34")
    assert_equal ["connected", nil], shown.call("connected", "AB12-CD34")
    assert_equal ["authorizing", nil], shown.call("authorizing", "https://example.invalid/?token=abc")
    assert_equal ["authorizing", nil], shown.call("authorizing", 1234)
  end

  def test_a_pairing_display_in_an_unreadable_encoding_drops_only_that_field
    [(+"AB12-\xFF").force_encoding("UTF-8"), "AB12-CD34".encode("UTF-16LE")].each do |pairing|
      connection.define_singleton_method(:status) do
        { "state" => "authorizing", "label" => "Hosted test library", "connection_id" => "connection-1",
          "pairing_display" => pairing }
      end
      status = Manager.status(declaration)
      assert_equal ["authorizing", "Hosted test library", "connection-1", nil],
                   status.values_at("state", "label", "connection_id", "pairing_display")
    end
  end

  def test_providers_metadata_names_the_connection_and_discovery_lists_declared_codes
    connection.finish_sign_in
    row = API.query(:context => @context, :name => "ph_composer.library.providers").fetch("value")
             .find { |provider| provider.fetch("id") == PROVIDER_ID }
    assert_equal({ "state" => "connected", "label" => "Hosted test library: Synthetic firm" }, row.fetch("connection"))
    load = PhComposer::Refusals.declared(Registry.current.setup_commands.fetch("ph_composer.library.load"))
    assert_includes load, "library.hosted_busy"
    copy = PhComposer::Refusals.declared(Registry.current.actions.fetch("ph_composer.library.copy"))
    assert_includes copy, "library.hosted_entitlement_ended"
    refute_includes copy, "library.hosted_busy"
  end

  # Disconnect and Remove clear what the connection loaded in every session; Remove also erases the
  # credential core can name. Neither is gated on the file provider.
  def test_remove_disconnects_erases_the_credential_and_clears_loaded_catalogs
    connection.finish_sign_in
    store = PhComposer::Library::Connection::CredentialStore
    assert_equal "synthetic-refresh-connection-1", store.read(PROVIDER_KIND, "connection-1")
    state = PhComposer::Library::State.for(@session)
    HostedLibraryFixtures.server.response = hosted_response
    setup_call("ph_composer.library.load", "provider_id" => PROVIDER_ID, "kind" => "materials")
    UI.run_timers
    refute_nil state.transport(PROVIDER_ID, "materials")
    removed = setup_call("#{PREFIX}.remove")
    assert_equal %w[completed disconnected], [removed.fetch("status"), removed.dig("value", "state")]
    assert_nil store.read(PROVIDER_KIND, "connection-1")
    assert_nil state.transport(PROVIDER_ID, "materials")
    assert_equal "unloaded", state.fetch(PROVIDER_ID, "materials", Registry.current).fetch("state")
    assert_includes connection.calls, :disconnect
  end

  # The extension's own disconnect normally erases its credential; when it refuses, Remove still does.
  def test_a_refused_disconnect_still_lets_remove_erase_the_credential_and_reports_the_refusal
    connection.finish_sign_in
    HostedLibraryFixtures.server.failures[:disconnect] = RuntimeError.new("revoke endpoint unreachable")
    refused = setup_call("#{PREFIX}.remove")
    assert_equal %w[refused library.provider_failed], refused.values_at("status", "code")
    assert_nil PhComposer::Library::Connection::CredentialStore.read(PROVIDER_KIND, "connection-1")
  end

  def test_an_abstract_stub_or_a_changed_call_inside_the_factory_is_handled
    stubbed = probe(:connection => lambda do |context|
      context.changed.call
      Class.new do
        def status
          raise NotImplementedError
        end
      end.new
    end)
    Registry.install([stubbed])
    row = connections.find { |item| item.fetch("provider_kind") == "test.probe.hosted" }
    assert_equal "unavailable", row.fetch("state")
    Manager.connection(Registry.current.library_providers.fetch("test.probe.hosted"))
           .define_singleton_method(:connect) { raise NotImplementedError }
    refused = setup_call("#{PREFIX}.connect", "provider_kind" => "test.probe.hosted")
    assert_equal "library.provider_failed", refused.fetch("code")
  end

  # A factory's own coded error is still the extension's text: only library.provider_failed comes out.
  def test_a_connection_factory_failure_keeps_no_code_text_or_detail
    secret = "https://example.invalid/?token=synthetic-secret"
    Registry.install([probe(:connection => lambda do |_context|
      raise PhComposer::Library::Error.new("library.hosted_busy", secret, "body" => secret)
    end)])
    refused = setup_call("#{PREFIX}.connect", "provider_kind" => "test.probe.hosted")
    assert_equal %w[refused library.provider_failed], refused.values_at("status", "code")
    refute_includes JSON.generate(refused), "synthetic-secret"
  end

  def test_a_new_connection_id_reported_through_changed_clears_the_old_connections_catalogs
    connection.finish_sign_in("connection-1")
    HostedLibraryFixtures.server.response = hosted_response
    setup_call("ph_composer.library.load", "provider_id" => PROVIDER_ID, "kind" => "materials")
    UI.run_timers
    state = PhComposer::Library::State.for(@session)
    refute_nil state.transport(PROVIDER_ID, "materials")
    connection.finish_sign_in("connection-2")
    assert_nil state.transport(PROVIDER_ID, "materials")
  end
end
