# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/box_zone_fixtures"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The hot water export over ACCEPTANCE's reference model: Zone A (5 x 4 m) and Zone B (4 x 4 m), 3 m boxes in one
# Building Segment, each with one detailed Space, ERV-1 serving A and ERV-2 serving B, and HWS-1 serving both with
# 8 tap points, storage Tanks T1 (300 L) and T2 (200 L), the buffer Tank T3 (80 L), an electric Heater H-E covering
# 0.3 and an annual heat pump H-HP covering 0.7. The golden feeds the Python section and the PHX round trip
# (tests/python/test_hot_water_sections.py, test_hot_water_phx_round_trip.py).
class MechanicalHotWaterExportTest < PhComposerTestCase
  include BoxZoneFixtures
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  X = M::HotWaterExport
  PREFIX = "ph_composer.mechanical"
  SERVES = "#{PREFIX}.serves".freeze
  SYSTEMS = "#{PREFIX}.hot_water_systems".freeze
  HEATERS = "#{PREFIX}.hot_water_heaters".freeze
  TANKS = "#{PREFIX}.hot_water_tanks".freeze
  FIXTURES = File.join(TESTS_ROOT, "fixtures", "mechanical")
  GOLDEN = File.join(FIXTURES, "hot_water_extraction.json")
  # The result fields the contributor declares, for the Python section's test to hold its rows to.
  RESULT_FIELDS = File.join(FIXTURES, "hot_water_result_fields.json")
  # Whether the System rows say the export writes a piping calculation method, for the Python section's test to
  # hold equal to what the pinned honeybee-ph does.
  METHOD = File.join(FIXTURES, "hot_water_method.json")
  ERVS = [{ "name" => "ERV-1", "sensible_heat_recovery" => 0.85 }, { "name" => "ERV-2" }].freeze
  TANKS_OF = [["T1", { "storage_capacity_l" => 300.0, "standby_losses_w_k" => 4.0 }],
              ["T2", { "storage_capacity_l" => 200.0, "standby_losses_w_k" => 3.0 }],
              ["T3", { "role" => "buffer", "tank_type" => "1-DHW AND HEATING", "storage_capacity_l" => 80.0,
                       "standby_losses_w_k" => 1.5 }]].freeze
  HEATERS_OF = [["H-E", { "percent_coverage" => 0.3 }],
                ["H-HP", { "variant" => "heat_pump_annual", "percent_coverage" => 0.7,
                           "total_system_perf_ratio" => 2.5 }]].freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @ids = {}
    @assembly_id = seed_export_construction
  end

  # ---------------------------------------------------------------- the pairs

  def test_the_reference_exports_one_pair_per_served_zone_with_its_slots_and_heaters_and_owns_the_golden
    reference
    extraction = extract
    pairs = hot_water(extraction)
    hws = @ids.fetch("HWS-1")
    assert_equal [["#{hws}_#{zone_id('A')}", zone_id("A")], ["#{hws}_#{zone_id('B')}", zone_id("B")]],
                 pairs.map { |row| row.values_at("id", "zone_id") }
    a, b = pairs
    assert_equal [hws, "HWS-1", 8, nil], a.values_at("system_identifier", "display_name", "number_tap_points",
                                                     "piping_calc_method")
    assert_equal [@ids.fetch("T1"), @ids.fetch("T2"), @ids.fetch("T3"), nil],
                 M::HotWater::Slotting::SLOTS.map { |slot| a.dig(slot, "identifier") }
    assert_equal [300.0, 200.0, 80.0], %w[tank_1 tank_2 tank_buffer].map { |slot| a.dig(slot, "storage_capacity_l") }
    heaters = a.fetch("heaters").map do |row|
      row.values_at("display_name", "variant", "percent_coverage", "total_system_perf_ratio")
    end
    assert_equal [["H-E", "electric", 0.3, nil], ["H-HP", "heat_pump_annual", 0.7, 2.5]], heaters
    assert_equal a.reject { |key, _| %w[id zone_id].include?(key) }, b.reject { |key, _| %w[id zone_id].include?(key) },
                 "every pair of one System is equal"
    assert_empty notes(extraction)
    assert_empty preflight_rows
    write_or_compare(GOLDEN, stable(extraction.document))
    write_or_compare(RESULT_FIELDS, X::RESULT_FIELDS)
    write_or_compare(METHOD, { "method_exported" => M::HotWater::Systems::METHOD_EXPORTED })
  end

  # The Ventilator export claims the Serves payload for the feature; with no Ventilator at all, it still hands the
  # hot water section every Zone's slots.
  def test_a_model_with_no_ventilators_still_exports_its_hot_water
    reference(:ventilators => false)
    extraction = extract
    assert_empty extraction.document.dig("sections", M::VentilationExport::SECTION, "records")
    assert_equal [zone_id("A"), zone_id("B")], hot_water(extraction).map { |row| row.fetch("zone_id") }
    assert_empty notes(extraction)
  end

  def test_a_tank_with_no_free_slot_is_left_out_with_a_finding_and_the_pair_is_written
    reference
    t4 = create(TANKS, "name" => "T4", "hot_water_system_id" => @ids.fetch("HWS-1"), "storage_capacity_l" => 150.0)
    extraction = extract
    assert_equal 2, hot_water(extraction).length
    identifiers = hot_water(extraction).flat_map do |row|
      M::HotWater::Slotting::SLOTS.map { |slot| row.dig(slot, "identifier") }
    end
    refute_includes identifiers, t4
    assert_equal [["mechanical.tank_unslotted", t4]], notes(extraction)
    assert_equal [["mechanical.tank_unslotted", t4, false]],
                 preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    assert_equal({ "name" => M::Locate::NAME, "params" => { "hot_water_tank_ids" => [t4] } },
                 preflight_rows.first.fetch("locate"), "the Tank's row opens the Tanks table on it")
  end

  def test_an_unserved_system_is_noted_alone_and_two_served_systems_in_one_segment_are_pooled
    reference
    two = create(SYSTEMS, "name" => "HWS-2")
    assert_equal [["mechanical.item_unserved", two]], notes(extract)
    completed(assign(%w[B], two, :replace => true))
    extraction = extract
    hws = @ids.fetch("HWS-1")
    assert_equal [["mechanical.hot_water_pooled", hws], ["mechanical.hot_water_pooled", two]].sort,
                 notes(extraction).sort
    assert_match(/HWS-1, HWS-2 serve Building Segment Main/,
                 extraction.findings.find { |row| row["code"] == "mechanical.hot_water_pooled" }.fetch("message"))
    assert_equal [[hws, zone_id("A")], [two, zone_id("B")]],
                 hot_water(extraction).map { |row| row.values_at("item_id", "zone_id") }.sort_by(&:last)
    assert_equal [false, false], preflight_rows.map { |row| row.fetch("blocks_export") }
  end

  # A hot water item's row opens its own Mechanical table on it, and the Locate command takes each item's ids.
  def test_hot_water_rows_locate_their_item_and_the_locate_command_opens_its_table
    reference
    two = create(SYSTEMS, "name" => "HWS-2")
    row = preflight_rows.find { |found| found.fetch("code") == "mechanical.item_unserved" }
    assert_equal({ "name" => M::Locate::NAME, "params" => { "hot_water_system_ids" => [two] } }, row.fetch("locate"))
    opened = []
    @session.define_singleton_method(:open_in_panel) { |owner, intent| opened << [owner, intent] }
    heater = @ids.fetch("H-E")
    [{ "hot_water_system_ids" => [two] },
     { "hot_water_heater_ids" => [heater], "ventilator_ids" => [] }].each do |params|
      completed(API.view(:context => @context, :name => M::Locate::NAME, :params => params))
    end
    assert_equal [["ph_composer.mechanical", { "hot_water_system_ids" => [two] }],
                  ["ph_composer.mechanical", { "hot_water_heater_ids" => [heater] }]], opened
    mixed = API.view(:context => @context, :name => M::Locate::NAME,
                     :params => { "hot_water_system_ids" => [two], "hot_water_tank_ids" => [@ids.fetch("T1")] })
    assert_equal %w[refused params.invalid], mixed.values_at("status", "code"), "one table opens at a time"
    assert_equal 2, opened.length, "nothing opened for the mixed request"
  end

  def test_a_served_zone_in_no_building_segment_is_left_out_and_a_zone_with_no_system_is_the_preflights_alone
    reference
    completed(invoke("ph_composer.zones.update_field", "field" => "building_segment", "value" => nil,
                                                       "targets" => [zone_target("Zone B")]))
    extraction = extract
    assert_equal [zone_id("A")], hot_water(extraction).map { |row| row.fetch("zone_id") }
    assert_equal [["mechanical.zone_left_out", @ids.fetch("HWS-1")]], notes(extraction)
    refute(preflight_rows.any? { |row| row.fetch("code") == "mechanical.zone_no_hot_water" })

    completed(invoke("#{SERVES}.clear", "zones" => [target("A")], "slot" => "hot_water_system_id"))
    extraction = extract
    assert_empty hot_water(extraction)
    refute(notes(extraction).any? { |code, _id| code == "mechanical.zone_no_hot_water" }, "a Room written as it is")
    rows = preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    assert_includes rows, ["mechanical.zone_no_hot_water", zone_id("A"), false]
    zone_row = preflight_rows.find { |row| row.fetch("code") == "mechanical.zone_no_hot_water" }
    assert_equal M::Locate::NAME, zone_row.dig("locate", "name")
  end

  def test_a_system_serving_zones_in_two_building_segments_is_noted_and_written_to_both
    reference("Annex")
    extraction = extract
    assert_equal [@ids.fetch("HWS-1")] * 2, hot_water(extraction).map { |row| row.fetch("item_id") }
    across = extraction.findings.find do |row|
      row["code"] == "mechanical.item_across_segments" && row["section"] == X::SECTION
    end
    assert_match(/in 2 Building Segments \(Annex, Main\).*whole Hot Water System/, across.fetch("message"))
  end

  def test_a_zone_naming_a_missing_system_blocks_the_export_and_the_preflight
    reference
    group = box_group("Zone B")
    record = PhComposer::Zones::ZONE_STORE.read(group)
    payload = record.dig("extension_data", M::Serves::NAMESPACE, "payload")
                    .merge("hot_water_system_id" => "hws_ZZZZZZZZZZZZ")
    envelope = M::Serves::Payload::EXTENSION.envelope(payload)
    PhComposer::Zones::ZONE_STORE.write(group, record.merge("extension_data" => { M::Serves::NAMESPACE => envelope }))
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_equal "mechanical.item_missing", error.code
    assert_match(/hot_water_system_id on Zone “Zone B” names hws_ZZZZZZZZZZZZ/, error.message)
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    ["mechanical.item_missing", zone_id("B"), true]
  end

  # A Tank's and a Heater's user_data ride on their honeybee-ph objects; a System's is left out, since
  # PhHotWaterSystem has no user_data; a reserved key on a Tank blocks, in the export and the preflight alike.
  def test_tank_and_heater_user_data_ride_a_systems_is_left_out_and_a_reserved_key_blocks
    reference
    completed(metadata(TANKS, @ids.fetch("T1"), "maker_ref" => "T-300"))
    completed(metadata(HEATERS, @ids.fetch("H-HP"), "maker_ref" => "HP-1"))
    completed(metadata(SYSTEMS, @ids.fetch("HWS-1"), "firm" => { "job" => 1 }))
    extraction = extract
    pair = hot_water(extraction).first
    assert_equal({ "maker_ref" => "T-300" }, pair.dig("tank_1", "user_data"))
    assert_equal [nil, { "maker_ref" => "HP-1" }], pair.fetch("heaters").map { |row| row["user_data"] }
    refute pair.key?("user_data")
    omitted = extraction.findings.select { |row| row["code"] == "export.metadata_omitted" }
    assert_equal [[X::SECTION, @ids.fetch("HWS-1")]], omitted.map { |row| row.values_at("section", "object_id") }

    completed(metadata(TANKS, @ids.fetch("T1"), "ph_composer" => { "x" => 1 }))
    assert_equal "export.blocked", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    ["export.blocked", @ids.fetch("T1"), true]
  end

  def test_an_unreadable_tank_blocks_the_preflight
    reference
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    store = engine.kind(M::HOT_WATER_TANK_KIND).store
    store.write(@model, engine.find(M::HOT_WATER_TANK_KIND, @ids.fetch("T2")).merge("schema_version" => 9))
    assert_raises(PhComposer::CodedError) { extract }
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    ["record.unreadable", @ids.fetch("T2"), true]
  end

  def test_the_privacy_allowlist_admits_only_the_declared_rows
    row = X::RESULT_FIELDS.fetch("hot_water").to_h { |key| [key, key == "heater_identifiers" ? %w[a b] : "x"] }
    result = { "schema_version" => 1, "run_id" => "r", "state" => "complete",
               "summary" => { "objects" => 1, "unavailable" => 0, "findings" => 0, "publishable" => true },
               "sections" => [], "findings" => [], X::SECTION => { "hot_water" => [row] } }
    assert PhComposer::Export::Privacy.validate!(result)
    error = assert_raises(PhComposer::CodedError) do
      PhComposer::Export::Privacy.validate!(result.merge(X::SECTION => { "hot_water" => [row.merge("tank_1" => {})] }))
    end
    assert_equal "export.privacy_undeclared", error.code
  end

  private

  def reference(segment_b = "Main", ventilators: true)
    @model.entities << box(1000, "A", "Zone A", "Main", [0, 5, 0, 4],
                           :airflows => { "v_sup_m3h" => 60.0, "v_eta_m3h" => 50.0, "v_tran_m3h" => 0.0 }) <<
      box(2000, "B", "Zone B", segment_b, [6, 10, 0, 4],
          :airflows => { "v_sup_m3h" => 40.0, "v_eta_m3h" => 40.0, "v_tran_m3h" => 0.0 })
    adopt_zone_options
    if ventilators
      ERVS.each { |values| create("#{PREFIX}.ventilators", values) }
      completed(assign(%w[A], @ids.fetch("ERV-1"), :slot => "ventilator_id"))
      completed(assign(%w[B], @ids.fetch("ERV-2"), :slot => "ventilator_id"))
    end
    hws = create(SYSTEMS, "name" => "HWS-1", "number_tap_points" => 8)
    TANKS_OF.each { |name, values| create(TANKS, values.merge("name" => name, "hot_water_system_id" => hws)) }
    HEATERS_OF.each { |name, values| create(HEATERS, values.merge("name" => name, "hot_water_system_id" => hws)) }
    completed(assign(%w[A B], hws))
  end

  def create(prefix, values)
    @ids[values.fetch("name")] = completed(invoke("#{prefix}.create", "values" => values)).fetch("id")
  end

  def zone_id(letter)
    "zon_#{letter * 12}"
  end

  def assign(letters, item_id, slot: "hot_water_system_id", replace: nil)
    params = { "zones" => letters.map { |letter| target(letter) }, "slot" => slot, "item_id" => item_id }
    params["replace"] = replace unless replace.nil?
    invoke("#{SERVES}.assign", params)
  end

  def target(letter)
    row = query("#{SERVES}.all").fetch("zones").find { |zone| zone.fetch("zone_id") == zone_id(letter) }
    { "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }
  end

  def zone_target(name)
    row = query("ph_composer.zones.all").fetch("zones").find { |zone| zone.dig("values", "name") == name }
    { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") }
  end

  def metadata(prefix, id, user_data)
    record = query("#{prefix}.all").fetch("records").find { |row| row.fetch("id") == id }
    invoke("ph_composer.records.update_metadata", "updates" => [{
      "reference" => { "kind" => record.fetch("kind"), "id" => id }, "user_data" => user_data,
      "expected_metadata" => record.slice("user_data", "extension_data")
    }])
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "mechanical-hot-water-export")
  end

  def hot_water(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  # This section's notes, as `[code, object_id]`.
  def notes(extraction)
    extraction.findings.select { |row|
      row.fetch("section") == X::SECTION && row.fetch("code").start_with?("mechanical.")
    }
              .map { |row| row.values_at("code", "object_id") }
  end

  # The hot water export's rows of the mechanical preflight.
  def preflight_rows
    rows = completed(API.query(:context => @context, :name => M::Preflight::NAME, :params => {})).fetch("findings")
    rows.select { |row| row.fetch("section") == X::SECTION }
  end

  # The document with the ids each run mints renumbered by name: Building Segments and every mechanical record, so the
  # golden compares.
  def stable(document)
    fixed = {}
    segments = query("ph_composer.zones.options.all").fetch("building_segments").map do |row|
      [row.dig("values", "name"), row.fetch("id")]
    end
    named = segments + @ids.to_a
    named.sort.each_with_index do |(_name, id), index|
      fixed[id] = format("#{id[0, 3]}_FIXED%<number>07d", :number => index + 1)
    end
    pattern = /(?<![A-Za-z0-9])(?:bsg|vnt|hws|hwh|hwt)_[A-Za-z0-9]{12}(?![A-Za-z0-9])/
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
