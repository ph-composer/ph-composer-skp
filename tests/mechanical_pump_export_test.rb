# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/box_zone_fixtures"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The Pump export over ACCEPTANCE's reference model: Zone A (5 x 4 m) and Zone B (4 x 4 m), 3 m boxes in one Building
# Segment, each with one Space. P-1 (two heating circulation pumps, 45 W, 5 kh, half its energy a gain, with
# user_data) serves both Zones and P-2 (a hot water circulation pump, 20 W, outside the envelope, its gain in summer)
# serves Zone A beside it. The golden feeds the Python section and the PHX round trip
# (tests/python/test_pump_sections.py, test_pumps_phx_round_trip.py).
class MechanicalPumpExportTest < PhComposerTestCase
  include BoxZoneFixtures
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  X = M::PumpExport
  SERVES = "ph_composer.mechanical.serves"
  PUMPS = "ph_composer.mechanical.pumps"
  SLOT = "pump_ids"
  FIXTURES = File.join(TESTS_ROOT, "fixtures", "mechanical")
  GOLDEN = File.join(FIXTURES, "pump_extraction.json")
  # The result fields the contributor declares, for the Python section's test to hold its rows to.
  RESULT_FIELDS = File.join(FIXTURES, "pump_result_fields.json")
  USER_DATA = { "maker_ref" => "P-1-A" }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @ids = {}
    @assembly_id = seed_export_construction
  end

  def test_the_reference_exports_one_pair_per_pump_and_served_zone_and_owns_the_golden
    reference
    extraction = extract
    one, two = @ids.values_at("P-1", "P-2")
    pairs = pumps(extraction)
    assert_equal [[one, zone_id("A")], [one, zone_id("B")], [two, zone_id("A")]].sort,
                 pairs.map { |row| row.values_at("item_id", "zone_id") }.sort
    a = pairs.find { |row| row.values_at("item_id", "zone_id") == [one, zone_id("A")] }
    assert_equal ["#{one}_#{zone_id('A')}", one, "P-1", 4, 2, true, 45.0, 5.0, 0.5, 2, USER_DATA],
                 a.values_at("id", "identifier", "display_name", "device_type", "quantity", "in_conditioned_space",
                             "norm_energy_demand_w", "annual_period_operation_khrs", "ihg_utilization_factor",
                             "ihg_usage_profile", "user_data"),
                 "a heating circulation pump's gain lands in winter"
    b = pairs.find { |row| row.values_at("item_id", "zone_id") == [one, zone_id("B")] }
    assert_equal a.reject { |key, _| %w[id zone_id].include?(key) }, b.reject { |key, _| %w[id zone_id].include?(key) },
                 "every pair of one pump is equal"
    second = pairs.find { |row| row.fetch("item_id") == two }
    assert_equal [two, 6, false, 3, false],
                 [second.fetch("identifier"), second.fetch("device_type"), second.fetch("in_conditioned_space"),
                  second.fetch("ihg_usage_profile"), second.key?("user_data")], "the profile P-2 names"
    assert_empty notes(extraction)
    assert_empty preflight_rows
    write_or_compare(GOLDEN, stable(extraction.document))
    write_or_compare(RESULT_FIELDS, X::RESULT_FIELDS)
  end

  def test_a_pump_on_a_zone_with_no_spaces_is_noted_and_still_written
    reference(:zone_c => :none)
    completed(assign(%w[C], @ids.fetch("P-2")))
    extraction = extract
    assert_includes pumps(extraction).map { |row| row.values_at("item_id", "zone_id") },
                    [@ids.fetch("P-2"), zone_id("C")]
    assert_equal [["mechanical.zone_without_spaces", @ids.fetch("P-2")]], notes(extraction)
    assert_match(/P-2 serves Zone Zone C, which has no Spaces\. PHX reads a Pump through a Room's Spaces/,
                 extraction.findings.find { |row| row["code"] == "mechanical.zone_without_spaces" }.fetch("message"))
    assert_equal [["mechanical.zone_without_spaces", @ids.fetch("P-2"), false]],
                 preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
  end

  def test_a_space_with_no_volume_is_a_space_and_gives_no_finding
    reference(:zone_c => :empty)
    completed(assign(%w[C], @ids.fetch("P-2")))
    extraction = extract
    assert_includes pumps(extraction).map { |row| row.values_at("item_id", "zone_id") },
                    [@ids.fetch("P-2"), zone_id("C")]
    assert_empty notes(extraction)
    assert_empty preflight_rows
  end

  def test_a_spaces_read_that_refuses_skips_the_no_spaces_finding_and_keeps_the_pump_rows
    zone = M::ExportZones::Zone.new(:id => zone_id("C"), :name => "Zone C", :segment => "Main",
                                    :segment_id => "bsg_AAAAAAAAAAAA", :exported => true,
                                    :values => M::Serves::EMPTY.merge(SLOT => ["pmp_AAAAAAAAAAAA"]))
    refusing = Object.new
    refusing.define_singleton_method(:query) { |_name| raise PhComposer::CodedError.new("record.unreadable", "x") }
    assert_nil X.spaced(refusing, [zone])
    pumps = { "pmp_AAAAAAAAAAAA" => { "name" => "P-1", "device_type" => 6 } }
    assert_equal ["mechanical.zone_without_spaces"],
                 M::PumpPlan.call(:zones => [zone], :pumps => pumps, :spaced => []).findings.map(&:code)
    assert_empty M::PumpPlan.call(:zones => [zone], :pumps => pumps, :spaced => nil).findings,
                 "unknown Spaces give no finding, and the pair stands"
    assert_equal 1, M::PumpPlan.call(:zones => [zone], :pumps => pumps, :spaced => nil).pairs.length
  end

  def test_an_unserved_pump_a_left_out_zone_and_two_segments_are_noted_and_never_block
    reference(:segment_b => "Annex")
    spare = create("name" => "P-9")
    extraction = extract
    assert_equal [zone_id("A"), zone_id("B")],
                 pumps(extraction).select { |row| row.fetch("item_id") == @ids.fetch("P-1") }
                                  .map { |row| row.fetch("zone_id") }.sort, "P-1 is written to both Segments' Rooms"
    found = notes(extraction)
    assert_includes found, ["mechanical.item_unserved", spare]
    assert_includes found, ["mechanical.item_across_segments", @ids.fetch("P-1")]
    assert_match(/in 2 Building Segments \(Annex, Main\); each Segment's model carries the whole Pump/,
                 extraction.findings.find { |row| row["code"] == "mechanical.item_across_segments" }.fetch("message"))
    assert_equal found.sort, preflight_rows.map { |row| row.values_at("code", "object_id") }.sort
    assert(preflight_rows.none? { |row| row.fetch("blocks_export") })
    locate = preflight_rows.find { |row| row.fetch("object_id") == spare }.fetch("locate")
    assert_equal({ "name" => M::Locate::NAME, "params" => { "pump_ids" => [spare] } }, locate)

    completed(invoke("ph_composer.zones.update_field", "field" => "building_segment", "value" => nil,
                                                       "targets" => [zone_target("Zone B")]))
    extraction = extract
    assert_equal [zone_id("A")], pumps(extraction).map { |row| row.fetch("zone_id") }.uniq
    assert_includes notes(extraction), ["mechanical.zone_left_out", @ids.fetch("P-1")]
    refute_includes notes(extraction).map(&:first), "mechanical.item_across_segments"
  end

  def test_a_zone_naming_a_missing_pump_blocks_the_export_and_the_preflight
    reference
    group = box_group("Zone B")
    record = PhComposer::Zones::ZONE_STORE.read(group)
    envelope = M::Serves::Payload::EXTENSION.envelope(M::Serves::EMPTY.merge(SLOT => ["pmp_ZZZZZZZZZZZZ"]))
    PhComposer::Zones::ZONE_STORE.write(group, record.merge("extension_data" => { M::Serves::NAMESPACE => envelope }))
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_equal "mechanical.item_missing", error.code
    assert_match(/pump_ids on Zone Zone B names pmp_ZZZZZZZZZZZZ, which is not in the Model/, error.message)
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    ["mechanical.item_missing", zone_id("B"), true]
  end

  def test_an_unreadable_pump_blocks_as_unreadable_and_its_zones_are_not_missing_one
    reference
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    two = @ids.fetch("P-2")
    engine.kind(M::PUMP_KIND).store.write(@model, engine.find(M::PUMP_KIND, two).merge("device_type" => 5))
    assert_equal "record.unreadable", assert_raises(PhComposer::CodedError) { extract }.code
    rows = preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    assert_includes rows, ["record.unreadable", two, true]
    refute(rows.any? { |code, _id, _blocks| code == "mechanical.item_missing" }, rows.inspect)
  end

  def test_the_locate_command_opens_the_pumps_table_narrowed_to_the_named_pump
    reference
    opened = []
    @session.define_singleton_method(:open_in_panel) { |owner, intent| opened << [owner, intent] }
    one = @ids.fetch("P-1")
    completed(API.view(:context => @context, :name => M::Locate::NAME, :params => { "pump_ids" => [one] }))
    assert_equal [["ph_composer.mechanical", { "pump_ids" => [one] }]], opened
  end

  def test_a_reserved_user_data_key_blocks_the_export_and_the_preflight
    reference
    one = @ids.fetch("P-1")
    completed(metadata(one, "ph_composer" => { "x" => 1 }))
    assert_equal "export.blocked", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_includes preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") },
                    ["export.blocked", one, true], "the preflight refuses what extraction refuses"
  end

  def test_the_privacy_allowlist_admits_only_the_declared_rows
    row = X::RESULT_FIELDS.fetch("pumps").to_h { |key| [key, "x"] }
    result = { "schema_version" => 1, "run_id" => "r", "state" => "complete",
               "summary" => { "objects" => 1, "unavailable" => 0, "findings" => 0, "publishable" => true },
               "sections" => [], "findings" => [], X::SECTION => { "pumps" => [row] } }
    assert PhComposer::Export::Privacy.validate!(result)
    error = assert_raises(PhComposer::CodedError) do
      PhComposer::Export::Privacy.validate!(result.merge(X::SECTION => { "pumps" => [row.merge("model" => "x")] }))
    end
    assert_equal "export.privacy_undeclared", error.code
  end

  private

  # With `zone_c`, Zone C beside them in the Main Segment: `:none` with no Space, `:empty` with one Space that holds
  # no Volume.
  def reference(segment_b: "Main", zone_c: nil)
    @model.entities << box(1000, "A", "Zone A", "Main", [0, 5, 0, 4]) <<
      box(2000, "B", "Zone B", segment_b, [6, 10, 0, 4])
    @model.entities << zone_c_group(zone_c == :empty) if zone_c
    adopt_zone_options
    create({ "name" => "P-1", "device_type" => 4, "quantity" => 2, "norm_energy_demand_w" => 45.0,
             "annual_period_operation_khrs" => 5.0, "ihg_utilization_factor" => 0.5 }, USER_DATA)
    create("name" => "P-2", "norm_energy_demand_w" => 20.0, "in_conditioned_space" => false, "ihg_usage_profile" => 3)
    completed(assign(%w[A B], @ids.fetch("P-1")))
    completed(assign(%w[A], @ids.fetch("P-2")))
  end

  def zone_c_group(empty_space)
    group = box(3000, "C", "Zone C", "Main", [11, 15, 0, 4], :space => false)
    return group unless empty_space

    empty = space_group(3050, space_record("C", :number => "1", :name => "Zone C"), [])
    group.entities << empty
    host_children([empty], zone_id("C"))
    group
  end

  def create(values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    @ids[values.fetch("name")] = completed(invoke("#{PUMPS}.create", params)).fetch("id")
  end

  def zone_id(letter)
    "zon_#{letter * 12}"
  end

  def assign(letters, item_id)
    invoke("#{SERVES}.assign", "zones" => letters.map { |letter| target(letter) }, "slot" => SLOT,
                               "item_id" => item_id)
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
    record = query("#{PUMPS}.all").fetch("records").find { |row| row.fetch("id") == id }
    invoke("ph_composer.records.update_metadata",
           "updates" => [{ "reference" => { "kind" => M::PUMP_KIND, "id" => id }, "user_data" => user_data,
                           "expected_metadata" => record.slice("user_data", "extension_data") }])
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "mechanical-pump-export")
  end

  def pumps(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  # This section's notes, as `[code, object_id]`.
  def notes(extraction)
    extraction.findings.select do |row|
      row.fetch("section") == X::SECTION && row.fetch("code").start_with?("mechanical.")
    end.map { |row| row.values_at("code", "object_id") }
  end

  # The Pump export's rows of the mechanical preflight.
  def preflight_rows
    rows = completed(API.query(:context => @context, :name => M::Preflight::NAME, :params => {})).fetch("findings")
    rows.select { |row| row.fetch("section") == X::SECTION }
  end

  # The document with the ids each run mints renumbered by name: Building Segments and every pump, so the golden
  # compares.
  def stable(document)
    fixed = {}
    segments = query("ph_composer.zones.options.all").fetch("building_segments").map do |row|
      [row.dig("values", "name"), row.fetch("id")]
    end
    (segments + @ids.to_a).sort.each_with_index do |(_name, id), index|
      fixed[id] = format("#{id[0, 3]}_FIXED%<number>07d", :number => index + 1)
    end
    pattern = /(?<![A-Za-z0-9])(?:bsg|pmp)_[A-Za-z0-9]{12}(?![A-Za-z0-9])/
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
