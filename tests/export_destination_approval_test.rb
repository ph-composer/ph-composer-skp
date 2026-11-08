# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# Approving a destination an agent exports to (context/AGENT_INTERFACE.md, "Locations only the user can
# choose"): the approval keeps an HBJSON name, export_preflight reports a destination start_export would
# refuse, and an agent asking to approve one is told where the user does it.
class ExportDestinationApprovalTest < PhComposerTestCase
  Locations = PhComposer::ApprovedLocations
  APPROVE = "ph_composer.locations.approve_destination"

  def setup
    super
    @directory = Dir.mktmpdir("phc-export-destination")
    @session = PhComposer::Sessions.for(Sketchup.active_model)
  end

  def teardown
    FileUtils.rm_rf(@directory)
    super
  end

  def context(grants)
    PhComposer::API.connect(:session_id => @session.id, :capabilities => grants)
  end

  def test_a_destination_named_without_an_extension_is_approved_as_hbjson
    UI.selected_save_path = File.join(@directory, "Export 3")
    named = PhComposer::NativeApproval.setup(context(%w[read setup]), APPROVE, {})
    assert_match(/\.hbjson\z/, UI.last_savepanel.last, "the dialog offers an HBJSON name")
    UI.selected_save_path = File.join(@directory, "Client v1.2")
    dotted = PhComposer::NativeApproval.setup(context(%w[read setup]), APPROVE, {})
    UI.selected_save_path = File.join(@directory, "Upper.HBJSON")
    upper = PhComposer::NativeApproval.setup(context(%w[read setup]), APPROVE, {})
    UI.selected_save_path = File.join(@directory, "model-library.json")
    library = PhComposer::NativeApproval.setup(context(%w[read setup]), APPROVE, {})

    assert_equal File.join(@directory, "Export 3.hbjson"),
                 Locations.resolve(named.dig("value", "id"), :kind => "save_file")
    assert_equal [File.join(@directory, "Client v1.2.hbjson"), File.join(@directory, "Upper.HBJSON")],
                 [dotted, upper].map { |outcome| Locations.resolve(outcome.dig("value", "id"), :kind => "save_file") },
                 "a dot inside a name is not an extension; HBJSON in any case is"
    assert_equal File.join(@directory, "model-library.json"),
                 Locations.resolve(library.dig("value", "id"), :kind => "save_file"),
                 "a name the user gave an extension keeps it"
  end

  def test_export_preflight_reports_a_destination_start_export_would_refuse
    refused = Locations.approve(:kind => "save_file", :path => File.join(@directory, "model.json")).fetch("id")
    fine = Locations.approve(:kind => "save_file", :path => File.join(@directory, "model.hbjson")).fetch("id")
    caller = context(%w[read export])

    reported = PhComposer::API.export_preflight(:context => caller, :location => refused)
    started = PhComposer::API.start_export(:context => caller, :location => { "id" => refused })
    clean = PhComposer::API.export_preflight(:context => caller, :location => fine)

    assert_equal "completed", reported.fetch("status"), reported.inspect
    assert_equal "The export destination must end in .hbjson.", reported.dig("value", "destination", "problem")
    assert_equal %w[refused export.refused], started.values_at("status", "code")
    assert_equal reported.dig("value", "destination", "problem"), started.fetch("message")
    assert_nil clean.dig("value", "destination", "problem")
  end

  # A destination left from earlier work that is no longer there says so in the list, and the user can
  # revoke it like any other.
  def test_a_destination_no_longer_there_is_listed_as_such_and_can_be_revoked
    folder = File.join(@directory, "gone")
    Dir.mkdir(folder)
    stale = Locations.approve(:kind => "save_file", :path => File.join(folder, "old.hbjson")).fetch("id")
    FileUtils.rm_rf(folder)
    caller = context(%w[read setup])

    listed = PhComposer::API.query(:context => caller, :name => "ph_composer.locations.list", :params => {})
    revoked = PhComposer::API.setup(:context => caller, :name => "ph_composer.locations.revoke",
                                    :params => { "id" => stale })

    row = listed.dig("value", "locations").find { |location| location["id"] == stale }
    assert_equal false, row.fetch("available")
    assert_equal "completed", revoked.fetch("status"), revoked.inspect
    assert_empty Locations.list.select { |row| row["id"] == stale }
  end

  def test_an_agent_asking_to_approve_a_destination_is_told_where_the_user_does_it
    outcome = PhComposer::API.setup(:context => context(%w[read setup]), :name => APPROVE, :params => {})

    assert_equal %w[refused access.user_required], outcome.values_at("status", "code")
    assert_includes outcome.fetch("message"), "Allow agents to export here"
    assert_includes outcome.fetch("message"), "Extensions > PH-Composer > Libraries > Approve Export Destination"
  end

  # A library export needs a .json destination, so its refusal points only at the Libraries menu and says
  # so; the Export tab's approval offers an HBJSON name.
  def test_a_library_export_without_a_location_names_the_libraries_route_and_its_json_name
    outcome = PhComposer::API.export_file(:context => context(%w[read export]),
                                          :name => "ph_composer.library.export_file", :params => {})

    assert_equal %w[refused access.user_required], outcome.values_at("status", "code")
    assert_includes outcome.fetch("message"), "Extensions > PH-Composer > Libraries > Approve Export Destination"
    assert_includes outcome.fetch("message"), ".json"
    refute_includes outcome.fetch("message"), "Allow agents to export here"
  end
end
