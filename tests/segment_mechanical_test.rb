# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/box_zone_fixtures"
require_relative "support/climate_fixtures"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# Mechanical settings on Building Segments, over two 3 m box Zones: Zone A in Main and Zone B in Annex, and a third
# Segment, Spare, that no Zone names. The settings are the mechanical feature's extension on each Segment record,
# saved through Zones' settings Save. At export the feature claims them on the Segment kind and writes one record
# per exported Segment with the defaults applied, and compares each Segment's cooling switch with its blended heat
# pump: ODU-A, which cools, serves Zone A through HP-1.1. The golden feeds the Python section and the PHX round trip
# (tests/python/test_mechanical_segment_sections.py, test_mechanical_segment_phx_round_trip.py); Zone A and Zone B
# take a Program with 19 °C and 26 °C set points so the round trip can show the section leaves them alone.
class SegmentMechanicalTest < PhComposerTestCase
  include BoxZoneFixtures
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  O = PhComposer::Zones::Options
  M = PhComposer::Mechanical
  S = M::SegmentSettings
  P = PhComposer::Programs
  NAMESPACE = S::NAMESPACE
  CERTIFICATION = PhComposer::Certification::Segment
  SECTION = M::SegmentExport::SECTION
  READ = M::SegmentRegistration::READ
  MISMATCH = M::Codes::SEGMENT_COOLING_MISMATCH
  HEAT_PUMPS = "ph_composer.mechanical.heat_pumps"
  FIXTURES = File.join(TESTS_ROOT, "fixtures", "segments")
  GOLDEN = File.join(FIXTURES, "mechanical_extraction.json")
  CHOICES = File.join(FIXTURES, "mechanical_choices.json")
  MAIN = { "mechanical_cooling" => true, "mech_room_temp_c" => 18.5, "summer_bypass_mode" => "temperature_controlled",
           "ventilation_system_ach" => 0.3, "daytime_window_ach" => 0.5, "nighttime_window_ach" => 1.2 }.freeze
  ODU_A = { "name" => "ODU-A", "heating_cap_17f_kw" => 6.4, "heating_cap_47f_kw" => 7.3, "cop_17f" => 2.4,
            "cop_47f" => 3.9, "cooling_rating_mode" => "eer_seer", "cooling_cap_95f_kw" => 6.4, "eer" => 12.5,
            "seer" => 20.0 }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @ids = {}
    @assembly_id = seed_export_construction
  end

  # ---------------------------------------------------------------- the extension

  def test_the_values_the_translation_and_the_section_map_are_these
    write_or_compare(CHOICES, { "bypass_modes" => S::BYPASS_MODES, "defaults" => S::DEFAULTS })
    assert_equal S::FIELDS, S::DEFAULTS.keys
    assert_empty S.problems(S::DEFAULTS)
  end

  def test_a_segment_reads_the_defaults_until_saved_with_another_section_in_one_undo_step
    reference
    main = segment_id("Main")
    assert_equal({ "id" => main, "values" => S::DEFAULTS, "stored" => false, "extension_status" => nil },
                 query(READ, "id" => main))
    operations = @model.operations.length
    phius = CERTIFICATION::DEFAULTS.merge("status" => "complete")

    saved = completed(save("Main", NAMESPACE => MAIN, CERTIFICATION::NAMESPACE => phius))

    assert_equal [CERTIFICATION::NAMESPACE, NAMESPACE].sort, saved.fetch("namespaces").sort
    assert_equal operations + 1, @model.operations.length, "one Undo step for both sections"
    assert_equal({ "id" => main, "values" => MAIN, "stored" => true, "extension_status" => "understood" },
                 query(READ, "id" => main))
    @model.undo
    assert_equal false, query(READ, "id" => main).fetch("stored")
    assert_equal false, query("ph_composer.certification.segment.get", "id" => main).fetch("stored"),
                 "Undo takes both sections back"
  end

  def test_a_partial_extra_mistyped_or_negative_payload_refuses_and_writes_nothing
    reference
    revision = @session.revision
    [MAIN.reject { |field, _| field == "nighttime_window_ach" }, MAIN.merge("note" => "x"),
     MAIN.merge("mechanical_cooling" => "yes"), MAIN.merge("mech_room_temp_c" => "20"),
     MAIN.merge("summer_bypass_mode" => "sometimes"), MAIN.merge("daytime_window_ach" => -0.1),
     MAIN.merge("daytime_window_ach" => nil), MAIN.merge("ventilation_system_ach" => -1)].each do |payload|
      outcome = save("Main", NAMESPACE => payload)
      assert_equal %w[refused validation.failed], outcome.values_at("status", "code"), payload.inspect
    end
    assert_equal revision, @session.revision
    assert_equal false, query(READ, "id" => segment_id("Main")).fetch("stored")
    assert_equal "target.not_found", API.query(:context => @context, :name => READ,
                                               :params => { "id" => "bsg_Ab12Cd34Ef56" }).fetch("code")
  end

  def test_the_settings_go_with_a_deleted_segment
    reference
    spare = segment_id("Spare")
    completed(save("Spare", NAMESPACE => MAIN))
    removed = completed(invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => spare))
    assert_equal [{ "id" => spare, "namespaces" => [NAMESPACE] }], removed.fetch("removed_extensions")
  end

  # ---------------------------------------------------------------- export

  def test_export_writes_one_record_per_exported_segment_with_the_defaults_and_owns_the_golden
    reference
    programs
    completed(save("Main", NAMESPACE => MAIN))
    completed(save("Spare", NAMESPACE => MAIN.merge("mech_room_temp_c" => 30.0)))

    extraction = extract
    records = extraction.document.dig("sections", SECTION, "records")
    by_name = records.to_h { |row| [row.fetch("name"), row] }
    assert_equal %w[Annex Main], by_name.keys.sort, "Spare names no exported Zone"
    assert_equal MAIN, by_name.fetch("Main").slice(*S::FIELDS)
    assert_equal S::DEFAULTS, by_name.fetch("Annex").slice(*S::FIELDS), "no settings, the defaults"
    refute_includes JSON.generate(extraction.document.dig("sections", SECTION)), "30.0"
    assert_empty notes(extraction), "Main cools with its blend, Annex has neither"
    assert_empty preflight_rows
    write_or_compare(GOLDEN, stable(extraction.document))
  end

  def test_the_switch_against_the_blend_is_a_warning_that_never_blocks
    reference
    main = segment_id("Main")
    annex = segment_id("Annex")
    found = preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    assert_equal [[MISMATCH, main, false]], found, "off while its blend cools"
    assert_equal [[MISMATCH, main]], notes(extract)

    completed(save("Main", NAMESPACE => MAIN))
    completed(save("Annex", NAMESPACE => S::DEFAULTS.merge("mechanical_cooling" => true)))
    assert_equal [[MISMATCH, annex]], preflight_rows.map { |row| row.values_at("code", "object_id") },
                 "on with no heat pump at all"
    assert_equal [[MISMATCH, annex]], notes(extract)

    heating_only = { "cooling_rating_mode" => nil, "cooling_cap_95f_kw" => nil }
    completed(invoke("#{HEAT_PUMPS}.outdoor_equipment.update", "id" => @ids.fetch("ODU-A"), "values" => heating_only,
                                                               "expected_values" => { "cooling_cap_95f_kw" => 6.4 }))
    rows = preflight_rows
    assert_equal [annex, main].sort, rows.map { |row| row.fetch("object_id") }.sort,
                 "on with a blend that does not cool"
    assert(rows.none? { |row| row.fetch("blocks_export") })
    assert_match(/Building Segment Main has mechanical cooling switched on/, rows.find { |row|
      row.fetch("object_id") == main
    }.fetch("message"))
    assert_equal [annex, main].sort, notes(extract).map(&:last).sort
  end

  def test_without_the_climate_no_blend_exports_so_only_a_switch_on_is_warned
    reference(:climate => false)
    assert_empty preflight_rows, "off, and no blend exports"
    completed(save("Main", NAMESPACE => MAIN))
    rows = preflight_rows
    assert_equal [[MISMATCH, SECTION, segment_id("Main"), false]],
                 rows.map { |row| row.values_at("code", "section", "object_id", "blocks_export") }
    found = extract.findings.select { |row| row.fetch("section") == SECTION }
    assert_equal rows.map { |row| row.values_at("code", "object_id", "message") },
                 found.map { |row| row.values_at("code", "object_id", "message") }, "the export notes the same row"
  end

  def test_an_invalid_stored_payload_blocks_the_preflight_and_the_export_on_any_segment
    reference
    %w[Main Spare].each do |name|
      id = segment_id(name)
      stored = O::SEGMENTS.store.read(@model, id)
      envelope = S::EXTENSION.envelope(MAIN.merge("summer_bypass_mode" => "sometimes"))
      O::SEGMENTS.store.write(@model, stored.merge("extension_data" => { NAMESPACE => envelope }))
      assert_equal({ "id" => id, "values" => S::DEFAULTS, "stored" => false, "extension_status" => "invalid" },
                   query(READ, "id" => id))

      blocking = completed(API.export_preflight(:context => @context)).fetch("findings")
                                                                      .select { |row| row.fetch("blocks_export") }
      assert_equal [[id, "extension.invalid"]], blocking.map { |row| row.values_at("object_id", "code") }, name
      refute_includes preflight_rows.map { |row| row.fetch("object_id") }, id,
                      "a payload that cannot be read gives no cooling warning"
      assert_equal "extension.invalid", assert_raises(PhComposer::Export::Blocked) { extract }.code
      O::SEGMENTS.store.write(@model, stored)
    end
  end

  private

  # Zone A in Main, served by HP-1.1 on ODU-A, and Zone B in Annex, served by no heat pump; Spare names no Zone.
  def reference(climate: true)
    @model.entities << box(1000, "A", "Zone A", "Main", [0, 5, 0, 4]) <<
      box(2000, "B", "Zone B", "Annex", [6, 10, 0, 4])
    adopt_zone_options
    create_zone_option("building_segment", "Spare")
    enter_climate if climate
    create("#{HEAT_PUMPS}.outdoor_equipment", ODU_A)
    create("#{HEAT_PUMPS}.indoor_equipment", "name" => "IDU-1")
    create("#{HEAT_PUMPS}.outdoor_units", "name" => "HP-1", "outdoor_equipment_id" => @ids.fetch("ODU-A"))
    create("#{HEAT_PUMPS}.indoor_units", "name" => "HP-1.1", "indoor_equipment_id" => @ids.fetch("IDU-1"),
                                         "outdoor_unit_id" => @ids.fetch("HP-1"))
    zones = query("ph_composer.mechanical.serves.all").fetch("zones")
    row = zones.find { |zone| zone.fetch("zone_id") == "zon_#{'A' * 12}" }
    completed(invoke("ph_composer.mechanical.serves.assign",
                     "zones" => [{ "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }],
                     "slot" => "hp_indoor_unit_ids", "item_id" => @ids.fetch("HP-1.1")))
  end

  # The residential default Program at 19 °C heating and 26 °C cooling, so the set points Programs writes on both
  # Segments are not honeybee-ph's 20 °C and 25 °C.
  def programs
    id = P::DefaultProgram::PROGRAM_ID
    setpoint = query("#{P::FEATURE_ID}.programs.all").fetch("records").find { |row| row.fetch("id") == id }
                                                     .dig("values", "setpoint")
    completed(invoke("#{P::FEATURE_ID}.programs.update",
                     "id" => id, "values" => { "setpoint" => setpoint.merge("heating_c" => 19.0, "cooling_c" => 26.0) },
                     "expected_values" => {}))
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

  def save(name, payloads)
    all = query("#{O::PREFIX}.all")
    row = all.fetch("building_segments").find { |candidate| candidate.dig("values", "name") == name }
    default_id = all.fetch("default_segment_id")
    values = row.fetch("values").slice("name", "colour")
    invoke(O::SegmentSettings::SAVE, "id" => row.fetch("id"), "values" => values, "expected_values" => values,
                                     "default" => default_id == row.fetch("id"),
                                     "expected_default_segment_id" => default_id, "extension_payloads" => payloads,
                                     "expected_extension_data" => row.fetch("extension_data", {}))
  end

  def segment_id(name)
    query("#{O::PREFIX}.all").fetch("building_segments").find { |row| row.dig("values", "name") == name }.fetch("id")
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "segment-mechanical")
  end

  # This section's notes, as `[code, object_id]`.
  def notes(extraction)
    rows = extraction.findings.select { |row| row.fetch("section") == SECTION }
    rows.map { |row| row.values_at("code", "object_id") }
  end

  # This section's rows of the mechanical preflight.
  def preflight_rows
    rows = completed(API.query(:context => @context, :name => M::Preflight::NAME, :params => {})).fetch("findings")
    rows.select { |row| row.fetch("section") == SECTION }
  end

  # The document with the ids each run mints renumbered by name: Building Segments, Programs and heat pump records,
  # so the golden compares.
  def stable(document)
    segments = query("#{O::PREFIX}.all").fetch("building_segments").map do |row|
      [row.dig("values", "name"), row.fetch("id")]
    end
    fixed = (segments + @ids.to_a).sort.each_with_index.to_h do |(_name, id), index|
      [id, format("#{id[0, 3]}_FIXED%<number>07d", :number => index + 1)]
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
