# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/box_zone_fixtures"
require_relative "support/climate_fixtures"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The heat pump export over ACCEPTANCE's reference model: Zone A (5 x 4 m) and Zone B (4 x 4 m), 3 m boxes in one
# Building Segment, with a typed climate (14 F and 95 F design temperatures). Two outdoor models: ODU-A, a COP pair
# with EER2 and SEER2 cooling, on outdoor unit HP-1 (two units), and ODU-C, a COP pair with IEER cooling, on HP-3;
# indoor unit HP-1.1 serves A, HP-3.1 serves A and B. The golden feeds the Python section and the PHX round trip
# (tests/python/test_heat_pump_sections.py, test_heat_pumps_phx_round_trip.py).
class MechanicalHeatPumpExportTest < PhComposerTestCase
  include BoxZoneFixtures
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  X = M::HeatPumpExport
  PREFIX = "ph_composer.mechanical"
  SERVES = "#{PREFIX}.serves".freeze
  OUTDOOR = "#{PREFIX}.heat_pumps.outdoor_equipment".freeze
  INDOOR = "#{PREFIX}.heat_pumps.indoor_equipment".freeze
  OUTDOOR_UNITS = "#{PREFIX}.heat_pumps.outdoor_units".freeze
  INDOOR_UNITS = "#{PREFIX}.heat_pumps.indoor_units".freeze
  FIXTURES = File.join(TESTS_ROOT, "fixtures", "mechanical")
  GOLDEN = File.join(FIXTURES, "heat_pump_extraction.json")
  # The result fields the contributor declares, for the Python section's test to hold its rows to.
  RESULT_FIELDS = File.join(FIXTURES, "heat_pump_result_fields.json")
  ODU_A = { "name" => "ODU-A", "heating_cap_17f_kw" => 6.4, "heating_cap_47f_kw" => 7.3, "cop_17f" => 2.4,
            "cop_47f" => 3.9, "cooling_rating_mode" => "eer_seer", "cooling_cap_95f_kw" => 6.4, "eer" => 12.5,
            "seer" => 20.0 }.freeze
  ODU_C = { "name" => "ODU-C", "heating_cap_17f_kw" => 21.0, "heating_cap_47f_kw" => 28.1, "cop_17f" => 2.1,
            "cop_47f" => 3.6, "cooling_rating_mode" => "ieer", "cooling_cap_95f_kw" => 28.1, "ieer" => 21.4 }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @ids = {}
    @assembly_id = seed_export_construction
  end

  def test_the_reference_exports_one_blend_per_segment_on_every_served_zone_and_owns_the_golden
    reference
    extraction = extract
    pairs = heat_pumps(extraction)
    assert_equal [zone_id("A"), zone_id("B")], pairs.map { |row| row.fetch("zone_id") }
    a, b = pairs
    identifier = M::HeatPumpPlan.identifier("Main")
    assert_equal [identifier, "Heat pumps: Main", "Main"], a.values_at("system_identifier", "display_name", "segment")
    assert_equal a.reject { |key, _| %w[id zone_id].include?(key) }, b.reject { |key, _| %w[id zone_id].include?(key) },
                 "every pair of one Segment is equal"
    # Heating: 2 x 6.4 kW and 21.0 kW at 17 F, 2 x 7.3 and 28.1 at 47 F, each COP by its share.
    assert_in_delta ((12.8 * 2.4) + (21.0 * 2.1)) / 33.8, a.fetch("cop_1"), 1e-9
    assert_in_delta ((14.6 * 3.9) + (28.1 * 3.6)) / 42.7, a.fetch("cop_2"), 1e-9
    cooling = a.fetch("cooling")
    assert_in_delta 40.9, cooling.fetch("capacity_kw"), 1e-9
    assert_equal [true, 12.0, false, true, 1.0],
                 cooling.values_at("used", "min_coil_temp_c", "single_speed", "flow_rate_variable", "percent_coverage")
    assert_equal [-8.333, 8.333, 1.0], a.values_at("ambient_temp_1_c", "ambient_temp_2_c", "percent_coverage")
    assert_empty notes(extraction)
    assert_empty preflight_rows
    write_or_compare(GOLDEN, stable(extraction.document))
    write_or_compare(RESULT_FIELDS, X::RESULT_FIELDS)
  end

  def test_without_the_climate_the_blend_is_left_out_with_a_note_and_the_export_proceeds
    reference(:climate => false)
    extraction = extract
    assert_empty heat_pumps(extraction)
    assert_equal [["mechanical.hp_climate_missing", nil]], notes(extraction)
    assert_equal [["mechanical.hp_climate_missing", false]],
                 preflight_rows.map { |row| row.values_at("code", "blocks_export") }
  end

  def test_segments_blend_apart_and_cooling_over_200_kw_is_noted_unsplit
    reference(:segment_b => "Annex")
    completed(invoke("#{OUTDOOR_UNITS}.update", "id" => @ids.fetch("HP-3"), "values" => { "quantity" => 8 },
                                                "expected_values" => { "quantity" => 1 }))
    extraction = extract
    pairs = heat_pumps(extraction)
    assert_equal %w[Annex Main], pairs.map { |row| row.fetch("segment") }.sort
    refute_equal(*pairs.map { |row| row.fetch("system_identifier") })
    annex = pairs.find { |row| row.fetch("segment") == "Annex" }
    assert_in_delta 8 * 28.1, annex.dig("cooling", "capacity_kw"), 1e-9, "one system, the whole capacity"
    found = notes(extraction)
    assert_includes found, ["mechanical.item_across_segments", @ids.fetch("HP-3")]
    assert_equal 2, found.count { |code, _id| code == "mechanical.hp_cooling_over_200kw" }
  end

  def test_unpaired_units_and_an_incomplete_model_are_left_out_with_their_notes
    reference
    lone = create(OUTDOOR_UNITS, "name" => "HP-9", "outdoor_equipment_id" => @ids.fetch("ODU-A"))
    spare = create(INDOOR_UNITS, "name" => "HP-9.1", "indoor_equipment_id" => @ids.fetch("IDU-1"),
                                 "outdoor_unit_id" => lone)
    completed(invoke("#{OUTDOOR}.update", "id" => @ids.fetch("ODU-C"), "values" => { "ieer" => nil },
                                          "expected_values" => { "ieer" => 21.4 }))
    extraction = extract
    assert_equal [zone_id("A")], heat_pumps(extraction).map { |row| row.fetch("zone_id") },
                 "Zone B is served only through the incomplete model"
    assert_equal [["mechanical.hp_equipment_incomplete", @ids.fetch("ODU-C")],
                  ["mechanical.hp_unit_unpaired", lone], ["mechanical.hp_unit_unpaired", spare]].sort,
                 notes(extraction).sort
    locate = preflight_rows.find { |row| row.fetch("object_id") == spare }.fetch("locate")
    assert_equal({ "name" => M::Locate::NAME, "params" => { "hp_indoor_unit_ids" => [spare] } }, locate)
  end

  def test_user_data_on_a_heat_pump_record_is_left_out_with_a_finding
    reference
    completed(metadata(OUTDOOR, @ids.fetch("ODU-A"), "maker_ref" => "A"))
    omitted = extract.findings.select { |row| row["code"] == "export.metadata_omitted" }
    assert_equal [[X::SECTION, @ids.fetch("ODU-A")]], omitted.map { |row| row.values_at("section", "object_id") }
  end

  def test_the_privacy_allowlist_admits_only_the_declared_rows
    row = X::RESULT_FIELDS.fetch("heat_pumps").to_h { |key| [key, "x"] }
    result = { "schema_version" => 1, "run_id" => "r", "state" => "complete",
               "summary" => { "objects" => 1, "unavailable" => 0, "findings" => 0, "publishable" => true },
               "sections" => [], "findings" => [], X::SECTION => { "heat_pumps" => [row] } }
    assert PhComposer::Export::Privacy.validate!(result)
    error = assert_raises(PhComposer::CodedError) do
      PhComposer::Export::Privacy.validate!(result.merge(X::SECTION => { "heat_pumps" => [row.merge("model" => "x")] }))
    end
    assert_equal "export.privacy_undeclared", error.code
  end

  private

  def reference(segment_b: "Main", climate: true)
    @model.entities << box(1000, "A", "Zone A", "Main", [0, 5, 0, 4]) <<
      box(2000, "B", "Zone B", segment_b, [6, 10, 0, 4])
    adopt_zone_options
    enter_climate if climate
    create(OUTDOOR, ODU_A)
    create(OUTDOOR, ODU_C)
    create(INDOOR, "name" => "IDU-1")
    create(OUTDOOR_UNITS, "name" => "HP-1", "outdoor_equipment_id" => @ids.fetch("ODU-A"), "quantity" => 2)
    create(OUTDOOR_UNITS, "name" => "HP-3", "outdoor_equipment_id" => @ids.fetch("ODU-C"))
    create(INDOOR_UNITS, "name" => "HP-1.1", "indoor_equipment_id" => @ids.fetch("IDU-1"),
                         "outdoor_unit_id" => @ids.fetch("HP-1"))
    create(INDOOR_UNITS, "name" => "HP-3.1", "indoor_equipment_id" => @ids.fetch("IDU-1"),
                         "outdoor_unit_id" => @ids.fetch("HP-3"))
    completed(assign(%w[A], @ids.fetch("HP-1.1")))
    completed(assign(%w[A B], @ids.fetch("HP-3.1")))
  end

  def enter_climate
    values = ClimateFixtures.sparse_values
    values["monthly"]["air_c"] = [-2.0, -1.0, 3.0, 9.0, 15.0, 20.0, 23.0, 22.0, 18.0, 12.0, 6.0, 0.0]
    completed(invoke("ph_composer.climate.climate.enter_values", "values" => values))
    completed(invoke("ph_composer.climate.design_temperatures.update",
                     "values" => { "heating_99_c" => -10.0, "cooling_1_c" => 35.0 },
                     "expected_values" => { "heating_99_c" => nil, "cooling_1_c" => nil }))
  end

  def create(prefix, values)
    @ids[values.fetch("name")] = completed(invoke("#{prefix}.create", "values" => values)).fetch("id")
  end

  def zone_id(letter)
    "zon_#{letter * 12}"
  end

  def assign(letters, item_id)
    invoke("#{SERVES}.assign", "zones" => letters.map { |letter| target(letter) }, "slot" => "hp_indoor_unit_ids",
                               "item_id" => item_id)
  end

  def target(letter)
    row = query("#{SERVES}.all").fetch("zones").find { |zone| zone.fetch("zone_id") == zone_id(letter) }
    { "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }
  end

  def metadata(prefix, id, user_data)
    record = query("#{prefix}.all").fetch("records").find { |row| row.fetch("id") == id }
    invoke("ph_composer.records.update_metadata", "updates" => [{
      "reference" => { "kind" => record.fetch("kind"), "id" => id }, "user_data" => user_data,
      "expected_metadata" => record.slice("user_data", "extension_data")
    }])
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "mechanical-heat-pump-export")
  end

  def heat_pumps(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  # This section's notes, as `[code, object_id]`.
  def notes(extraction)
    extraction.findings.select { |row|
      row.fetch("section") == X::SECTION && row.fetch("code").start_with?("mechanical.")
    }
              .map { |row| row.values_at("code", "object_id") }
  end

  # The heat pump export's rows of the mechanical preflight.
  def preflight_rows
    rows = completed(API.query(:context => @context, :name => M::Preflight::NAME, :params => {})).fetch("findings")
    rows.select { |row| row.fetch("section") == X::SECTION }
  end

  # The document with the ids each run mints renumbered by name: Building Segments and every mechanical record, so
  # the golden compares.
  def stable(document)
    fixed = {}
    segments = query("ph_composer.zones.options.all").fetch("building_segments").map do |row|
      [row.dig("values", "name"), row.fetch("id")]
    end
    (segments + @ids.to_a).sort.each_with_index do |(_name, id), index|
      fixed[id] = format("#{id[0, 3]}_FIXED%<number>07d", :number => index + 1)
    end
    pattern = /(?<![A-Za-z0-9])(?:bsg|hpo|hpi|hou|hiu)_[A-Za-z0-9]{12}(?![A-Za-z0-9])/
    stable = JSON.parse(JSON.generate(document).gsub(pattern) { |id| fixed.fetch(id, id) })
    stable.fetch("sections").each_value { |section| section.fetch("records").sort_by! { |row| row.fetch("id").to_s } }
    stable
  end

  def query(name, params = {})
    completed(API.query(:context => @context, :name => name, :params => params))
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
