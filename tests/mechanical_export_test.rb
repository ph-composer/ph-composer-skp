# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/box_zone_fixtures"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The Ventilator export over ACCEPTANCE's reference model: Zone A (5 x 4 m) and Zone B (4 x 4 m), 3 m boxes in one
# Building Segment, each with one detailed Space (60 / 50 m³/h in Zone A, 40 / 40 in Zone B), and two Ventilators.
# The base case serves A with ERV-1 and B with ERV-2; the shared case serves both with ERV-1 and leaves ERV-2
# serving nothing. The boxes stand 1 m apart, as the Program export's do, so no Face pairs with another. The goldens
# feed the Python section and the PHX round trip (tests/python/test_ventilation_sections.py,
# test_ventilation_phx_round_trip.py).
class MechanicalExportTest < PhComposerTestCase
  include BoxZoneFixtures
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  X = M::VentilationExport
  SERVES = "ph_composer.mechanical.serves"
  VENTILATORS = "ph_composer.mechanical.ventilators"
  FIXTURES = File.join(TESTS_ROOT, "fixtures", "mechanical")
  BASE = File.join(FIXTURES, "extraction.json")
  SHARED = File.join(FIXTURES, "shared_extraction.json")
  # The result fields the contributor declares, for the Python section's test to hold its rows to.
  RESULT_FIELDS = File.join(FIXTURES, "result_fields.json")
  ERV1 = { "name" => "ERV-1", "sensible_heat_recovery" => 0.85, "latent_heat_recovery" => 0.6,
           "electric_efficiency_wh_m3" => 0.45, "frost_protection_reqd" => true,
           "temperature_below_defrost_used_c" => -5.0, "in_conditioned_space" => true, "quantity" => 1 }.freeze
  ERV2 = { "name" => "ERV-2", "sensible_heat_recovery" => 0.75, "latent_heat_recovery" => 0.0,
           "electric_efficiency_wh_m3" => 0.35, "frost_protection_reqd" => false,
           "temperature_below_defrost_used_c" => -5.0, "in_conditioned_space" => false, "quantity" => 1,
           "subsoil_heat_exchange_efficiency" => 0.2 }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @assembly_id = seed_export_construction
  end

  # ---------------------------------------------------------------- the pairs

  def test_the_reference_exports_one_pair_per_served_zone_and_owns_the_goldens
    reference
    base = extract
    pairs = ventilation(base)
    erv1, erv2 = @erv.values_at("ERV-1", "ERV-2")
    assert_equal [["#{erv1}_#{zone_id('A')}", erv1, zone_id("A")], ["#{erv2}_#{zone_id('B')}", erv2, zone_id("B")]]
      .sort, pairs.map { |row| row.values_at("id", "item_id", "zone_id") }
    a = pairs.find { |row| row.fetch("item_id") == erv1 }
    assert_equal [erv1, "#{erv1}_unit", "ERV-1"], a.values_at("system_identifier", "unit_identifier", "display_name")
    assert_equal ERV1.reject { |key, _| key == "name" }, a.slice(*ERV1.keys - ["name"])
    assert_equal [nil, nil], a.values_at("subsoil_heat_exchange_efficiency", "preheated_intake_temperature_c")
    b = pairs.find { |row| row.fetch("item_id") == erv2 }
    assert_equal [0.2, nil], b.values_at("subsoil_heat_exchange_efficiency", "preheated_intake_temperature_c")
    assert_empty mechanical_notes(base)
    assert_empty preflight_rows
    write_or_compare(BASE, stable(base.document))

    completed(assign(%w[B], "ERV-1", :replace => true))
    shared = extract
    pairs = ventilation(shared)
    assert_equal [erv1], pairs.map { |row| row.fetch("system_identifier") }.uniq, "one identifier on both Rooms"
    assert_equal [zone_id("A"), zone_id("B")], pairs.map { |row| row.fetch("zone_id") }.sort
    assert_equal pairs.first.reject { |key, _| %w[id zone_id].include?(key) },
                 pairs.last.reject { |key, _| %w[id zone_id].include?(key) }, "every pair of one item is equal"
    assert_equal [["mechanical.item_unserved", erv2]], mechanical_notes(shared)
    assert_equal [["mechanical.item_unserved", erv2, false]],
                 preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    write_or_compare(SHARED, stable(shared.document))
    write_or_compare(RESULT_FIELDS, X::RESULT_FIELDS)
  end

  def test_a_cleared_zone_is_unventilated_and_its_item_unserved_and_the_export_proceeds
    reference
    completed(invoke("#{SERVES}.clear", "zones" => [target("B")], "slot" => "ventilator_id"))
    extraction = extract
    assert_equal [zone_id("A")], ventilation(extraction).map { |row| row.fetch("zone_id") }
    assert_equal [["mechanical.item_unserved", @erv.fetch("ERV-2")]], mechanical_notes(extraction)
    # The unventilated Zone is written as it is, so the preflight alone reports it; the run carries that warning
    # into the result. The unserved item is reported where the export notes it, so the run lists it once.
    assert_equal [["mechanical.item_unserved", @erv.fetch("ERV-2"), false],
                  ["mechanical.zone_unventilated", zone_id("B"), false]],
                 preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }.sort
  end

  # Each preflight row says where it is fixed: a Ventilator's on the Mechanical tab, a Zone's on the Zones tab.
  def test_the_preflight_rows_locate_their_object_and_the_locate_command_opens_it
    reference
    completed(invoke("#{SERVES}.clear", "zones" => [target("B")], "slot" => "ventilator_id"))
    locates = preflight_rows.to_h { |row| [row.fetch("code"), row.fetch("locate")] }
    assert_equal({ "name" => X::LOCATE, "params" => { "ventilator_ids" => [@erv.fetch("ERV-2")] } },
                 locates.fetch("mechanical.item_unserved"))
    zone_b = locates.fetch("mechanical.zone_unventilated")
    assert_equal [zone_id("B")], zone_b.dig("params", "zones").map { |zone| zone.fetch("zone_id") }

    opened = []
    @session.define_singleton_method(:open_in_panel) { |owner, intent| opened << [owner, intent] }
    [locates.fetch("mechanical.item_unserved"), zone_b].each do |locate|
      completed(API.view(:context => @context, :name => locate.fetch("name"), :params => locate.fetch("params")))
    end
    assert_equal [["ph_composer.mechanical", { "ventilator_ids" => [@erv.fetch("ERV-2")] }],
                  ["ph_composer.zones", { "zones" => zone_b.dig("params", "zones") }]], opened
  end

  def test_a_served_zone_in_no_building_segment_is_left_out_with_its_room
    reference
    completed(invoke("ph_composer.zones.update_field", "field" => "building_segment", "value" => nil,
                                                       "targets" => [zone_target("Zone B")]))
    extraction = extract
    rooms = extraction.document.dig("sections", PhComposer::Zones::ExportProjection::SECTION, "records")
    assert_equal [zone_id("A")], rooms.map { |row| row.fetch("id") }, "Room B is absent"
    assert_equal [zone_id("A")], ventilation(extraction).map { |row| row.fetch("zone_id") }
    assert_equal [["mechanical.zone_left_out", @erv.fetch("ERV-2")]], mechanical_notes(extraction),
                 "no unventilated or unserved finding for what leaves with Zone B"
    assert_match(/ERV-2 serves Zone Zone B, which is in no Building Segment/,
                 extraction.findings.find { |row| row["code"] == "mechanical.zone_left_out" }.fetch("message"))
    assert_equal [["mechanical.zone_left_out", @erv.fetch("ERV-2"), false]],
                 preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
  end

  def test_an_item_serving_zones_in_two_building_segments_is_noted_and_written_to_both
    reference("Annex")
    completed(assign(%w[B], "ERV-1", :replace => true))
    extraction = extract
    assert_equal [@erv.fetch("ERV-1")] * 2, ventilation(extraction).map { |row| row.fetch("item_id") }
    across = extraction.findings.find { |row| row["code"] == "mechanical.item_across_segments" }
    assert_equal @erv.fetch("ERV-1"), across.fetch("object_id")
    assert_match(/in 2 Building Segments \(Annex, Main\)/, across.fetch("message"))
    assert_includes preflight_rows.map { |row| row.values_at("code", "blocks_export") },
                    ["mechanical.item_across_segments", false]
  end

  def test_an_unreadable_ventilator_blocks_as_unreadable_and_its_zone_is_not_missing_one
    reference
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    erv2 = @erv.fetch("ERV-2")
    engine.kind(M::VENTILATOR_KIND).store.write(@model, engine.find(M::VENTILATOR_KIND, erv2).merge("quantity" => 0))
    assert_equal "record.unreadable", assert_raises(PhComposer::CodedError) { extract }.code
    rows = preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    assert_includes rows, ["record.unreadable", erv2, true]
    refute(rows.any? { |code, _id, _blocks| code == "mechanical.item_missing" }, rows.inspect)
  end

  def test_a_serves_payload_this_version_does_not_understand_blocks_the_export_and_the_preflight
    reference
    group = box_group("Zone B")
    record = PhComposer::Zones::ZONE_STORE.read(group)
    envelope = record.dig("extension_data", M::Serves::NAMESPACE).merge("schema_version" => 99)
    PhComposer::Zones::ZONE_STORE.write(group, record.merge("extension_data" => { M::Serves::NAMESPACE => envelope }))
    assert_equal "extension.schema_unsupported", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    ["extension.schema_unsupported", zone_id("B"), true]
  end

  # Two occurrences of a copy not yet made independent share Zone B's id: the plan reads the Zone once. Spaces
  # refuses such a copy, so the whole export stops on it; the Zones and ventilation sections alone show the read.
  def test_a_zone_with_two_occurrences_gives_one_pair
    reference
    original = box_group("Zone B")
    moved = Geom::Transformation.translation([0, 400, 0])
    copy = Sketchup::Group.new(9000, original.entities, :name => "Zone B", :transformation => moved)
    Array(original.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    extraction = extract([PhComposer::Zones::ExportProjection::SECTION, X::SECTION])
    rooms = extraction.document.dig("sections", PhComposer::Zones::ExportProjection::SECTION, "records")
    assert_equal 2, rooms.count { |row| row.fetch("id") == zone_id("B") }, "the Zones section writes both"
    assert_equal [zone_id("A"), zone_id("B")], ventilation(extraction).map { |row| row.fetch("zone_id") }.sort
    assert_empty mechanical_notes(extraction)
    assert_empty preflight_rows
  end

  # A Zone record written outside the engine, as one pasted from another Model arrives, can name a Ventilator that
  # is not stored (context/CONTRACTS.md, "Mechanical equipment").
  def test_a_zone_naming_a_missing_ventilator_blocks_the_export_and_the_preflight
    reference
    group = box_group("Zone B")
    record = PhComposer::Zones::ZONE_STORE.read(group)
    envelope = M::Serves::Payload::EXTENSION.envelope(M::Serves::EMPTY.merge("ventilator_id" => "vnt_ZZZZZZZZZZZZ"))
    PhComposer::Zones::ZONE_STORE.write(group, record.merge("extension_data" => { M::Serves::NAMESPACE => envelope }))
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_equal "mechanical.item_missing", error.code
    assert_match(/names vnt_ZZZZZZZZZZZZ, which is not in the Model/, error.message)
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    ["mechanical.item_missing", zone_id("B"), true]
  end

  # ---------------------------------------------------------------- metadata and privacy

  def test_a_ventilators_user_data_rides_on_its_pairs_and_a_reserved_key_blocks
    reference
    erv1 = @erv.fetch("ERV-1")
    completed(metadata(erv1, "maker_ref" => "ERV-1-A"))
    assert_equal [{ "maker_ref" => "ERV-1-A" }],
                 ventilation(extract).select { |row| row.fetch("item_id") == erv1 }.map { |row| row["user_data"] }
    assert(ventilation(extract).none? { |row| row.fetch("item_id") != erv1 && row.key?("user_data") })

    completed(metadata(erv1, "ph_composer" => { "x" => 1 }))
    assert_equal "export.blocked", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    ["export.blocked", erv1, true], "the preflight refuses what extraction refuses"
  end

  # An extension payload on a Ventilator that no contributor exports and that declares itself required.
  def test_a_required_extension_payload_on_a_ventilator_blocks_the_export_and_the_preflight
    reference
    erv1 = @erv.fetch("ERV-1")
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    store = engine.kind(M::VENTILATOR_KIND).store
    envelope = { "schema_version" => 1, "payload" => { "x" => 1 }, "references" => [],
                 "export_relevance" => "required" }
    store.write(@model, engine.find(M::VENTILATOR_KIND, erv1).merge("extension_data" => { "acme.rating" => envelope }))
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    [error.code, erv1, true]
  end

  def test_the_privacy_allowlist_admits_only_the_declared_rows_and_the_metadata_guard_passes_user_data
    row = X::RESULT_FIELDS.fetch("ventilation").to_h { |key| [key, key.end_with?("_id") ? "x" : 1] }
    result = { "schema_version" => 1, "run_id" => "r", "state" => "complete",
               "summary" => { "objects" => 1, "unavailable" => 0, "findings" => 0, "publishable" => true },
               "sections" => [], "findings" => [], X::SECTION => { "ventilation" => [row] } }
    assert PhComposer::Export::Privacy.validate!(result)
    error = assert_raises(PhComposer::CodedError) do
      undeclared = { "ventilation" => [row.merge("rated_flow" => 1)] }
      PhComposer::Export::Privacy.validate!(result.merge(X::SECTION => undeclared))
    end
    assert_equal "export.privacy_undeclared", error.code

    declared = PhComposer::Export::Privacy.user_data_keys
    system = { "type" => "PhVentilationSystem", "ventilation_unit" => { "user_data" => { "maker_ref" => "ERV-1-A" } } }
    assert PhComposer::Export::HbjsonMetadata.validate!(JSON.generate(system), declared)
    system["ventilation_unit"]["user_data"] = { "ph_composer" => { "ventilator" => "x" } }
    assert_raises(PhComposer::CodedError) do
      PhComposer::Export::HbjsonMetadata.validate!(JSON.generate(system), declared)
    end
  end

  # ---------------------------------------------------------------- the report

  def test_the_report_lists_each_ventilator_with_its_zones_and_one_line_for_those_serving_none
    rows = %w[A B].map { |letter| report_row("vnt_1_zon_#{letter}", "vnt_1", "Zone #{letter}", "ERV-1") }
    findings = [{ "code" => "mechanical.item_unserved", "section" => X::SECTION, "object_id" => "vnt_2",
                  "message" => "ERV-2 serves no Zone, so nothing exports it.", "blocks_export" => false },
                { "code" => "mechanical.item_unserved", "section" => "another.section", "object_id" => "vnt_3",
                  "message" => "Not this section's.", "blocks_export" => false }]
    contributor = PhComposer::Registry.current.export_contributors.fetch(X::SECTION)
    view = PhComposer::Export::ResultView.new({ "findings" => findings, X::SECTION => { "ventilation" => rows } },
                                              contributor)
    html = X.report(view, "SI").join
    assert_includes html, "Mechanical: Ventilators"
    assert_includes html, "Electric efficiency (Wh/m³)"
    assert_includes html, "<td>ERV-1</td><td>Zone A, Zone B</td><td>1</td><td>0.85</td><td>0.60</td><td>0.45</td>"
    # Under IP the efficiency is in W/cfm: 0.45 Wh/m³ moves 1.699 m³/h for each cfm, 0.76 W/cfm.
    html = X.report(view, "IP").join
    assert_includes html, "Electric efficiency (W/cfm)"
    assert_includes html, "<td>0.60</td><td>0.76</td>"
    assert_includes html, "ERV-2 serves no Zone, so nothing exports it."
    refute_includes html, "Not this section's."
    assert_empty X.report(PhComposer::Export::ResultView.new({ "findings" => [] }, contributor), "SI")
  end

  private

  # ACCEPTANCE's reference model, base case; Zone B in Building Segment `segment_b`.
  def reference(segment_b = "Main")
    @model.entities << box(1000, "A", "Zone A", "Main", [0, 5, 0, 4],
                           :airflows => { "v_sup_m3h" => 60.0, "v_eta_m3h" => 50.0, "v_tran_m3h" => 0.0 }) <<
      box(2000, "B", "Zone B", segment_b, [6, 10, 0, 4],
          :airflows => { "v_sup_m3h" => 40.0, "v_eta_m3h" => 40.0, "v_tran_m3h" => 0.0 })
    adopt_zone_options
    @erv = [ERV1, ERV2].to_h do |values|
      [values.fetch("name"), completed(invoke("#{VENTILATORS}.create", "values" => values)).fetch("id")]
    end
    completed(assign(%w[A], "ERV-1"))
    completed(assign(%w[B], "ERV-2"))
  end

  def report_row(id, item, zone, name)
    X::RESULT_FIELDS.fetch("ventilation").to_h { |key| [key, nil] }
                    .merge("id" => id, "item_id" => item, "zone_name" => zone, "display_name" => name)
                    .merge(ERV1.reject { |key, _| key == "name" })
  end

  def zone_id(letter)
    "zon_#{letter * 12}"
  end

  def assign(letters, item, replace: nil)
    params = { "zones" => letters.map { |letter| target(letter) }, "slot" => "ventilator_id",
               "item_id" => @erv.fetch(item) }
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

  def metadata(id, user_data)
    record = query("#{VENTILATORS}.all").fetch("records").find { |row| row.fetch("id") == id }
    invoke("ph_composer.records.update_metadata",
           "updates" => [{ "reference" => { "kind" => M::VENTILATOR_KIND, "id" => id }, "user_data" => user_data,
                           "expected_metadata" => record.slice("user_data", "extension_data") }])
  end

  def extract(contributors = nil)
    PhComposer::Export::Collection.build(@model, :run_id => "mechanical-export", :contributors => contributors)
  end

  def ventilation(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  def mechanical_notes(extraction)
    extraction.findings.select { |row| row.fetch("code").start_with?("mechanical.") }
              .map { |row| row.values_at("code", "object_id") }
  end

  # The Ventilator export's rows of the mechanical preflight; the hot water rows are the hot water export test's.
  def preflight_rows
    rows = completed(API.query(:context => @context, :name => M::Preflight::NAME, :params => {})).fetch("findings")
    rows.select { |row| row.fetch("section") == X::SECTION }
  end

  # The document with the ids each run mints renumbered: Building Segments and Ventilators by name, so the golden
  # compares.
  def stable(document)
    fixed = {}
    segments = query("ph_composer.zones.options.all").fetch("building_segments").map do |row|
      [row.dig("values", "name"), row.fetch("id")]
    end
    { "bsg" => segments, "vnt" => @erv.to_a }.each do |prefix, rows|
      rows.sort.each_with_index do |(_name, id), index|
        fixed[id] = format("#{prefix}_FIXED%<number>07d", :number => index + 1)
      end
    end
    pattern = /(?<![A-Za-z0-9])(?:bsg|vnt)_[A-Za-z0-9]{12}(?![A-Za-z0-9])/
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
