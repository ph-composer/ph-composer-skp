# frozen_string_literal: true

require "json"
require_relative "test_helper"

# The panel's Setup view (context/EXTENSIBILITY.md, "Setup entries"): menu items declared `in_setup`, listed
# with their summaries and run from the panel as the Extensions menu runs them, and never an API operation.
class SetupEntriesTest < PhComposerTestCase
  Registry = PhComposer::Registry
  Panel = PhComposer::Panel

  def setup
    super
    @session = PhComposer::Sessions.for(Sketchup.active_model)
  end

  def feature(&install)
    Module.new do
      define_singleton_method(:install) { |registry| install.call(registry) }
      define_singleton_method(:name) { "Probe" }
    end
  end

  def install_probe(reached)
    Registry.install([feature do |registry|
      scope = registry.feature("outside.probe", :contract_version => 1)
      scope.menu_item("outside.probe.open", :label => "Probe…", :menu => "Probe", :in_setup => true,
                                            :summary => ->(_session) { "Ready" }) { |session| reached << session }
      scope.menu_item("outside.probe.broken", :label => "Broken…", :menu => "Probe", :in_setup => true,
                                              :summary => ->(_session) { raise "no" }) { |_session| nil }
      scope.menu_item("outside.probe.menu_only", :label => "Menu only", :menu => "Probe") { |_session| nil }
    end])
  end

  def test_an_outside_feature_lists_a_setup_entry_and_the_panel_runs_it_as_the_menu_does
    reached = []
    install_probe(reached)
    dialog = Panel.show

    dialog.fire("ph_composer_message", envelope("panel.setup_entries", {}))
    dialog.fire("ph_composer_message", envelope("panel.setup_open", "name" => "outside.probe.open"))

    listed = messages(dialog, "panel.setup").map { |payload| payload.fetch("entries") }
    probe = listed.first.select { |entry| entry["name"].start_with?("outside.") }
    expected = [["outside.probe.open", "Probe", "Probe…", "Ready"], ["outside.probe.broken", "Probe", "Broken…", nil]]
    assert_equal expected, probe.map { |entry| entry.values_at("name", "menu", "label", "summary") }
    assert_equal 2, listed.length, "running an entry answers the entries again"
    assert_equal [@session], reached
    assert_includes PhComposer::Diagnostics.tail.join, "setup_summary_failed"
  end

  def test_the_panel_runs_only_a_setup_entry
    ran = []
    install_probe(ran)
    dialog = Panel.show

    dialog.fire("ph_composer_message", envelope("panel.setup_open", "name" => "outside.probe.menu_only"))

    assert_empty ran
    assert_empty messages(dialog, "panel.setup")
    assert_equal 1, messages(dialog, "panel.failure").length
  end

  def test_a_setup_entry_is_no_api_operation
    install_probe([])
    names = PhComposer::API.discover.values.select { |value| value.is_a?(Array) }.flatten
                           .select { |entry| entry.is_a?(Hash) }.map { |entry| entry["name"] }

    refute_includes names, "outside.probe.open"
    refute_includes names, "ph_composer.agent_access.open"
  end

  def test_a_summary_without_in_setup_or_an_entries_provider_in_setup_refuses_the_batch
    grayed = { :in_setup => true, :state => ->(_session) { MF_GRAYED } }
    [{ :summary => ->(_session) { "x" } }, { :in_setup => "yes" }, grayed].each do |options|
      probe = feature do |registry|
        registry.feature("outside.probe", :contract_version => 1)
                .menu_item("outside.probe.go", :label => "Go", :menu => "Probe", **options) { |_session| nil }
      end
      error = assert_raises(PhComposer::RegistrationError) { Registry.install([probe]) }
      assert_includes error.diagnostics.map(&:code), "registration.schema_invalid"
    end
    provider = feature do |registry|
      registry.feature("outside.probe", :contract_version => 1)
              .menu_entries("outside.probe.list", :menu => "Probe") { |_read| [] }
    end
    assert Registry.install([provider])
  end

  def test_agent_access_is_a_setup_entry_saying_whether_agents_can_connect
    listener = PhComposer::AgentAccess::Listener
    stopped = { "state" => "stopped", "port" => 46_110 }
    entry = listener.stub(:status, stopped) do
      PhComposer::SetupEntries.list(@session).find { |item| item["name"] == "ph_composer.agent_access.open" }
    end
    assert_equal ["Agent Access", "Agent Access…", "Not listening · no live tokens"],
                 entry.values_at("menu", "label", "summary")
    PhComposer::AgentAccess::Tokens.issue(:label => "One")
    listening = listener.stub(:status, { "state" => "listening", "port" => 46_110 }) do
      PhComposer::AgentAccess.setup_summary
    end
    assert_equal "Listening on port 46110 · 1 live token", listening
    Sketchup.write_default(PhComposer::AgentAccess::Tokens::SECTION, PhComposer::AgentAccess::Tokens::KEY, "not-json")
    assert_includes listener.stub(:status, stopped) { PhComposer::AgentAccess.setup_summary }, "cannot be read"
  end

  def test_a_refused_entry_is_the_models_notice_and_the_entries_come_again
    Registry.install([feature do |registry|
      registry.feature("outside.probe", :contract_version => 1)
              .menu_item("outside.probe.refuse", :label => "Refuse…", :menu => "Probe", :in_setup => true) do |_session|
        raise PhComposer::CodedError.new("probe.refused", "Not now.")
      end
    end])
    dialog = Panel.show
    notices = []

    @session.stub(:notice, ->(message, tone:) { notices << [message, tone] }) do
      dialog.fire("ph_composer_message", envelope("panel.setup_open", "name" => "outside.probe.refuse"))
    end

    assert_equal [["Not now.", :warning]], notices
    assert_equal 1, messages(dialog, "panel.setup").length
  end

  private

  def envelope(type, payload)
    JSON.generate("type" => type, "payload" => payload)
  end

  def messages(dialog, type)
    dialog.scripts.map { |script| JSON.parse(script[/receive\((.*)\)\z/m, 1]) }
          .select { |item| item.fetch("type") == type }.map { |item| item.fetch("payload") }
  end
end
