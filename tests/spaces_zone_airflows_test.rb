# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The airflow mode per Zone (context/CONTRACTS.md, "Translation sections and artifacts"): the extraction carries
# each Space's Zone's mode, From Program clears a Zone in one Undo step, and a Zone with no Spaces is an export
# warning that does not block. On the Spaces reference model, Zone A is detailed (Living, Bath and Hall each carry
# one rate) and Zone B is By Program (Loft carries none).
class SpacesZoneAirflowsTest < PhComposerTestCase
  include SpaceFixtures

  X = PhComposer::Spaces::ExportProjection
  API = PhComposer::API
  CLEAR = "ph_composer.spaces.clear_zone_airflows"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    reference_model
  end

  def extraction
    snapshot = PhComposer::Export::GeometrySnapshot.capture(@model, :revision => 0)
    catalog = PhComposer::Registry.current.catalog
    reader = PhComposer::Export::SnapshotReader.new(
      PhComposer::Export::RecordReader.new(PhComposer::Records::Engine.new(@model, catalog), catalog), snapshot
    )
    rows = reader.within(X::SECTION) { X.records(reader) }
    rows.to_h { |row| [row.fetch("name"), row] }
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => name, :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def zone(name)
    query("ph_composer.spaces.all").fetch("zones").find { |row| row["name"] == name }
  end

  def zone_param(name)
    zone(name).slice("zone_id", "zone_path")
  end

  def rates(space_name)
    group = @model.entities.to_a.flat_map { |zone| zone.entities.to_a }
                  .find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity)&.fetch("name") == space_name }
    PhComposer::Spaces::SPACE_STORE.read(group).slice(*PhComposer::Spaces::AIRFLOWS)
  end

  def test_each_space_leaves_with_its_zones_mode_and_its_stored_rates
    rows = extraction
    modes = rows.values_at("Living", "Bath", "Hall").map { |row| row["airflow_mode"] }
    assert_equal %w[detailed detailed detailed], modes
    assert_equal "by_program", rows.fetch("Loft")["airflow_mode"]
    refute rows.fetch("Living").key?("v_eta_m3h"), "a blank leaves absent; the translation writes it as 0"
    assert_equal 2, PhComposer::Registry.current.export_contributors.fetch(X::SECTION).section_version
  end

  def test_from_program_clears_every_space_in_the_zone_in_one_undo_step
    before = @model.operations.length
    cleared = invoke(CLEAR, "zones" => [zone_param("Zone A")])
    assert_equal "completed", cleared["status"], cleared.inspect
    assert_equal %w[spc_LLLLLLLLLLLL spc_BBBBBBBBBBBB spc_HHHHHHHHHHHH].sort, cleared.dig("value", "space_ids").sort
    assert_equal before + 1, @model.operations.length
    assert_equal "by_program", zone("Zone A")["airflow_mode"]
    assert(%w[Living Bath Hall].all? { |name| rates(name).empty? })
    Sketchup.undo
    assert_equal "detailed", zone("Zone A")["airflow_mode"]
    assert_equal({ "v_sup_m3h" => 60.0 }, rates("Living"))
  end

  def test_from_program_on_a_by_program_zone_writes_nothing
    before = @model.operations.length
    cleared = invoke(CLEAR, "zones" => [zone_param("Zone B")])
    assert_equal ["completed", []], [cleared["status"], cleared.dig("value", "space_ids")]
    assert_equal before, @model.operations.length
  end

  # All or nothing: a locked Space would stay rated and keep its Zone detailed, so nothing is written.
  def test_from_program_refuses_the_whole_zone_when_one_space_cannot_be_written
    hall = @model.entities.to_a.first.entities.to_a.last
    hall.locked = true
    refused = invoke(CLEAR, "zones" => [zone_param("Zone A")])
    assert_equal %w[refused target.locked], refused.values_at("status", "code")
    assert_equal({ "v_sup_m3h" => 60.0 }, rates("Living"))
    assert_equal "detailed", zone("Zone A")["airflow_mode"]
  end

  def test_a_zone_with_no_spaces_is_an_export_warning_that_does_not_block
    @model.entities << zone_group(3000, "C", [])
    findings = query(X::PREFLIGHT).fetch("findings").select { |row| row["code"] == "space.zone_without_spaces" }
    assert_equal [["zon_CCCCCCCCCCCC", false]], findings.map { |row| row.values_at("object_id", "blocks_export") }
    assert_match(/Zone Zone C has no Spaces/, findings.first["message"])
  end

  # A Zone in no Building Segment leaves export with everything in it, so its emptiness is not reported; a copied
  # Zone's occurrences are read together by id, as its Spaces' membership is.
  def test_the_no_spaces_warning_skips_a_left_out_zone_and_reads_a_copy_by_id
    zones = [{ "zone_id" => "zon_A", "name" => "A", "space_count" => 2 },
             { "zone_id" => "zon_A", "name" => "A", "space_count" => 0 },
             { "zone_id" => "zon_O", "name" => "Out", "space_count" => 0 },
             { "zone_id" => "zon_E", "name" => "Empty", "space_count" => 0 }]
    found = X.without_spaces_findings(zones, "zon_O" => "Out")
    assert_equal ["zon_E"], found.map { |row| row.fetch("object_id") }
  end
end
