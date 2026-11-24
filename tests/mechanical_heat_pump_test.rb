# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"
require_relative "support/climate_fixtures"

# The heat pump catalogs with the panel closed (context/CONTRACTS.md, "Mechanical equipment"): outdoor and indoor
# models, outdoor and indoor units, the guarded deletes from model to unit to Zone, the Serves list slot, and the
# Blended result with and without the Model's climate. Apt 1 and Apt 2 are Zones in the Apartments Building Segment.
# Every write goes through the public actions, one Undo step each.
class MechanicalHeatPumpTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  HP = M::HeatPumps
  PREFIX = "ph_composer.mechanical"
  SERVES = "#{PREFIX}.serves".freeze
  OUTDOOR = "#{PREFIX}.heat_pumps.outdoor_equipment".freeze
  INDOOR = "#{PREFIX}.heat_pumps.indoor_equipment".freeze
  OUTDOOR_UNITS = "#{PREFIX}.heat_pumps.outdoor_units".freeze
  INDOOR_UNITS = "#{PREFIX}.heat_pumps.indoor_units".freeze
  BLENDED = "#{PREFIX}.heat_pumps.blended".freeze
  SLOT = "hp_indoor_unit_ids"
  COMMON = { "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" } }.freeze
  RATED = { "heating_cap_17f_kw" => 6.4, "heating_cap_47f_kw" => 7.3, "cop_17f" => 2.4, "cop_47f" => 3.9 }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @model.entities << zone(1000, "A", "Apt 1", [0, 0, 5, 5]) << zone(2000, "B", "Apt 2", [10, 0, 5, 5])
    adopt_zone_options
  end

  # ---------------------------------------------------------------- the kinds

  def test_the_four_kinds_round_trip_with_their_defaults_and_an_indoor_model_is_identity_only
    odu = create(OUTDOOR, "name" => " ODU-A ")
    assert_match(/\Ahpo_[A-Za-z0-9]{12}\z/, odu)
    assert_equal COMMON.merge("name" => "ODU-A").merge(HP::OutdoorEquipment::DEFAULTS), values(OUTDOOR, odu)
    row = rows(OUTDOOR).fetch("ODU-A")
    assert_equal [false, ["mechanical.hp_equipment_incomplete"], 0],
                 row.values_at("export_ready", "export_blockers", "unit_count"), "no capacities yet"
    completed(invoke("#{OUTDOOR}.update", "id" => odu, "values" => RATED, "expected_values" => {}))
    assert rows(OUTDOOR).fetch("ODU-A").fetch("export_ready")

    idu = create(INDOOR, "name" => "IDU-W09", "manufacturer" => "Kaltwerk")
    assert_equal COMMON.merge("name" => "IDU-W09", "manufacturer" => "Kaltwerk"), values(INDOOR, idu)
    assert_equal %w[refused params.invalid],
                 invoke("#{INDOOR}.create", "values" => { "name" => "X", "cop_17f" => 2.0 }).values_at("status", "code")
    hou = create(OUTDOOR_UNITS, "name" => "HP-1", "outdoor_equipment_id" => odu)
    assert_equal({ "quantity" => 1, "in_conditioned_space" => false, "outdoor_equipment_id" => odu },
                 values(OUTDOOR_UNITS, hou).slice("quantity", "in_conditioned_space", "outdoor_equipment_id"))
    hiu = create(INDOOR_UNITS, { "name" => "HP-1.1", "indoor_equipment_id" => idu, "outdoor_unit_id" => hou },
                 { "firm" => { "tag" => "a" } })
    assert_equal({ "quantity" => 1, "in_conditioned_space" => true },
                 values(INDOOR_UNITS, hiu).slice("quantity", "in_conditioned_space"))
    assert_equal [1, 1], [rows(OUTDOOR).fetch("ODU-A").fetch("unit_count"),
                          rows(OUTDOOR_UNITS).fetch("HP-1").fetch("indoor_unit_count")]
    assert_equal ["mechanical.hp_unit_unpaired"], codes(rows(INDOOR_UNITS).fetch("HP-1.1")),
                 "an indoor unit serving no Zone is left out of the blend, and said once"
    assert_equal ["mechanical.hp_unit_unpaired"], codes(rows(OUTDOOR_UNITS).fetch("HP-1"))
    sections = PhComposer::Snapshot.build(@context).fetch("sections")
    [OUTDOOR, INDOOR, OUTDOOR_UNITS, INDOOR_UNITS].each do |prefix|
      assert_equal query("#{prefix}.all"), sections.dig(prefix, "value")
    end
    assert_equal query(BLENDED), sections.dig("#{PREFIX}.heat_pumps_blended", "value")
  end

  def test_a_unit_naming_a_missing_model_or_none_refuses_and_a_rating_mode_reads_only_its_values
    [[OUTDOOR_UNITS, { "outdoor_equipment_id" => "hpo_ZZZZZZZZZZZZ" }, "reference.invalid"],
     [OUTDOOR, { "heating_rating_mode" => "cop" }, "params.invalid"],
     [OUTDOOR, { "cop_17f" => 0 }, "params.invalid"],
     [OUTDOOR, { "cooling_rating_mode" => "seer" }, "params.invalid"]].each do |prefix, extra, code|
      outcome = invoke("#{prefix}.create", "values" => { "name" => "X" }.merge(extra))
      assert_equal ["refused", code], outcome.values_at("status", "code"), extra.inspect
    end
    refute_equal "committed", invoke("#{INDOOR_UNITS}.create", "values" => { "name" => "X" })["effect"]
    hspf = RATED.merge("name" => "ODU-B", "heating_rating_mode" => "hspf")
    odu = create(OUTDOOR, hspf)
    assert_equal ["HSPF"], HP::OutdoorEquipment.missing_inputs(values(OUTDOOR, odu)),
                 "the COP pair it keeps is not read in HSPF mode"
    completed(invoke("#{OUTDOOR}.update", "id" => odu, "values" => { "hspf_value" => 10.0,
                                                                     "cooling_rating_mode" => "ieer" },
                                          "expected_values" => { "hspf_value" => nil }))
    assert_equal ["cooling capacity at 95 F", "IEER"], HP::OutdoorEquipment.missing_inputs(values(OUTDOOR, odu))
  end

  # ---------------------------------------------------------------- Serves and deletes

  def test_the_list_slot_holds_several_indoor_units_and_clear_takes_out_one
    one, two = served_units(%w[HP-1.1 HP-1.2])
    operations = @model.operations.length
    completed(assign(["Apt 1"], one))
    completed(assign(["Apt 1"], two))
    assert_equal operations + 2, @model.operations.length
    assert_equal [one, two].sort, slots("Apt 1").fetch(SLOT).sort
    completed(assign(["Apt 1"], one))
    assert_equal 2, slots("Apt 1").fetch(SLOT).length, "a list holds an item once"
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 1")], "slot" => SLOT, "item_id" => one))
    assert_equal [two], slots("Apt 1").fetch(SLOT)
    assert_equal %w[Apt\ 1], rows(INDOOR_UNITS).fetch("HP-1.2").fetch("zones").map { |zone| zone.fetch("name") }
    refusal = invoke("#{SERVES}.clear", "zones" => [target("Apt 1")], "item_id" => two)
    assert_equal %w[refused params.invalid], refusal.values_at("status", "code"), "item_id needs its slot"
    refusal = invoke("#{SERVES}.clear", "zones" => [target("Apt 1")], "slot" => SLOT, "item_id" => "vnt_ZZZZZZZZZZZZ")
    assert_equal %w[refused params.invalid], refusal.values_at("status", "code"), "an id of another kind"
  end

  def test_deletes_refuse_in_use_down_the_chain_and_a_replacement_moves_what_names_them
    odu = create(OUTDOOR, RATED.merge("name" => "ODU-A"))
    spare = create(OUTDOOR, RATED.merge("name" => "ODU-B"))
    idu = create(INDOOR, "name" => "IDU-1")
    idu2 = create(INDOOR, "name" => "IDU-2")
    completed(invoke("#{OUTDOOR}.update", "id" => odu, "values" => { "paired_indoor_equipment_id" => idu },
                                          "expected_values" => {}))
    hou = create(OUTDOOR_UNITS, "name" => "HP-1", "outdoor_equipment_id" => odu)
    hou2 = create(OUTDOOR_UNITS, "name" => "HP-2", "outdoor_equipment_id" => spare)
    hiu = create(INDOOR_UNITS, "name" => "HP-1.1", "indoor_equipment_id" => idu, "outdoor_unit_id" => hou)
    hiu2 = create(INDOOR_UNITS, "name" => "HP-2.1", "indoor_equipment_id" => idu, "outdoor_unit_id" => hou2)
    completed(assign(["Apt 1"], hiu))

    [[OUTDOOR, odu], [INDOOR, idu], [OUTDOOR_UNITS, hou], [INDOOR_UNITS, hiu]].each do |prefix, id|
      assert_equal %w[refused reference.in_use], invoke("#{prefix}.delete", "id" => id).values_at("status", "code"),
                   prefix
    end
    assert_equal %w[refused reference.in_use],
                 invoke("#{INDOOR}.delete", "id" => idu, "replacement_id" => nil).values_at("status", "code"),
                 "null empties the pairing, and the indoor units still name it"
    assert_equal idu, values(OUTDOOR, odu).fetch("paired_indoor_equipment_id"), "a refused delete writes nothing"

    operations = @model.operations.length
    completed(invoke("#{INDOOR}.delete", "id" => idu, "replacement_id" => idu2))
    assert_equal operations + 1, @model.operations.length
    assert_equal [idu2, idu2, idu2], [values(OUTDOOR, odu).fetch("paired_indoor_equipment_id"),
                                      values(INDOOR_UNITS, hiu).fetch("indoor_equipment_id"),
                                      values(INDOOR_UNITS, hiu2).fetch("indoor_equipment_id")]
    @model.undo
    assert_equal idu, values(INDOOR_UNITS, hiu).fetch("indoor_equipment_id")

    completed(invoke("#{INDOOR_UNITS}.delete", "id" => hiu, "replacement_id" => hiu2))
    assert_equal [hiu2], slots("Apt 1").fetch(SLOT)
    completed(invoke("#{OUTDOOR_UNITS}.delete", "id" => hou2, "replacement_id" => hou))
    assert_equal hou, values(INDOOR_UNITS, hiu2).fetch("outdoor_unit_id")
    completed(invoke("#{OUTDOOR}.delete", "id" => odu, "replacement_id" => spare))
    assert_equal spare, values(OUTDOOR_UNITS, hou).fetch("outdoor_equipment_id")
    completed(invoke("#{INDOOR_UNITS}.delete", "id" => hiu2, "replacement_id" => nil))
    assert_empty slots("Apt 1").fetch(SLOT), "null takes it out of each Zone's list"
  end

  # ---------------------------------------------------------------- the Blended result

  def test_the_blended_result_needs_the_climate_and_then_blends_each_segment
    unit = served_units(["HP-1.1"]).first
    completed(assign(%w[Apt\ 1 Apt\ 2], unit))
    blended = query(BLENDED)
    assert_equal "missing", blended.dig("climate", "state")
    assert_empty blended.fetch("segments")
    assert_equal ["mechanical.hp_climate_missing"], codes(blended)

    enter_climate
    blended = query(BLENDED)
    assert_equal "complete", blended.dig("climate", "state")
    (segment,) = blended.fetch("segments")
    assert_equal ["Apartments", %w[Apt\ 1 Apt\ 2]],
                 [segment.fetch("segment"), segment.fetch("zones").map { |zone| zone.fetch("name") }]
    export = segment.dig("result", "export")
    assert_in_delta 2.4, export.fetch("cop_1"), 1e-9
    assert_in_delta 3.9, export.fetch("cop_2"), 1e-9
    assert_empty codes(blended)
    preflight = query("#{PREFIX}.preflight").fetch("findings").map { |row| row.values_at("section", "code") }
    refute_includes preflight, [M::HeatPumpExport::SECTION, "mechanical.hp_climate_missing"]
  end

  private

  # An outdoor model, one outdoor unit and an indoor model, with indoor units named `names` on that outdoor unit.
  def served_units(names)
    odu = create(OUTDOOR, RATED.merge("name" => "ODU-A"))
    idu = create(INDOOR, "name" => "IDU-1")
    hou = create(OUTDOOR_UNITS, "name" => "HP-1", "outdoor_equipment_id" => odu)
    names.map do |name|
      create(INDOOR_UNITS, "name" => name, "indoor_equipment_id" => idu, "outdoor_unit_id" => hou)
    end
  end

  def enter_climate
    values = ClimateFixtures.sparse_values
    values["monthly"]["air_c"] = [-2.0, -1.0, 3.0, 9.0, 15.0, 20.0, 23.0, 22.0, 18.0, 12.0, 6.0, 0.0]
    completed(invoke("ph_composer.climate.climate.enter_values", "values" => values))
    completed(invoke("ph_composer.climate.design_temperatures.update",
                     "values" => { "heating_99_c" => -10.0, "cooling_1_c" => 32.0 },
                     "expected_values" => { "heating_99_c" => nil, "cooling_1_c" => nil }))
  end

  def zone(base, letter, name, (x0, y0, width, depth))
    space = space_group(base + 10, space_record(letter, :number => "1", :name => name),
                        [volume_group(base + 20, volume_record(letter),
                                      [floor_face(base + 30, rectangle(x0, y0, width, depth),
                                                  segment_record(letter))])])
    group = Sketchup::Group.new(base, Sketchup::Entities.new([space]), :name => name)
    ZONES::ZONE_STORE.write(group, { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name,
                                     "building_segment" => "Apartments", "level" => "L1", "ground_depth_mm" => 0.0 })
    host_children([space], "zon_#{letter * 12}")
    group
  end

  def create(prefix, values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    completed(invoke("#{prefix}.create", params)).fetch("id")
  end

  def values(prefix, id)
    query("#{prefix}.all").fetch("records").find { |row| row.fetch("id") == id }.fetch("values")
  end

  def rows(prefix)
    query("#{prefix}.all").fetch("records").to_h { |row| [row.dig("values", "name"), row] }
  end

  def assign(names, item_id)
    invoke("#{SERVES}.assign", "zones" => names.map { |name| target(name) }, "slot" => SLOT, "item_id" => item_id)
  end

  def target(name)
    row = serves_rows.fetch(name)
    { "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }
  end

  def serves_rows
    query("#{SERVES}.all").fetch("zones").to_h { |row| [row.fetch("name"), row] }
  end

  def slots(name)
    serves_rows.fetch(name).fetch("slots")
  end

  def codes(row)
    row.fetch("findings").map { |finding| finding.fetch("code") }
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
