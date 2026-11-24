# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The Pump catalog with the panel closed (context/CONTRACTS.md, "Mechanical equipment"): the kind and its defaults, the
# usage profile its type gives until it names one, the guarded edit, Duplicate with its metadata, the `pump_ids` list
# slot on the Zone, and the guarded delete with a replacement or none. Apt 1 and Apt 2 are Zones in the Apartments
# Building Segment. Every write goes through the public actions, one Undo step each.
class MechanicalPumpTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  PREFIX = "ph_composer.mechanical"
  PUMPS = "#{PREFIX}.pumps".freeze
  SERVES = "#{PREFIX}.serves".freeze
  SLOT = "pump_ids"
  COMMON = { "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" } }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @model.entities << zone(1000, "A", "Apt 1", [0, 0, 5, 5]) << zone(2000, "B", "Apt 2", [10, 0, 5, 5])
    adopt_zone_options
  end

  def test_a_pump_takes_honeybee_phs_values_by_default_and_a_value_outside_its_range_refuses
    id = create("name" => " P-1 ")
    assert_match(/\Apmp_[A-Za-z0-9]{12}\z/, id)
    assert_equal COMMON.merge("name" => "P-1", "device_type" => 6, "quantity" => 1, "in_conditioned_space" => true,
                              "norm_energy_demand_w" => 0.0, "annual_period_operation_khrs" => 8.76,
                              "ihg_utilization_factor" => 1.0), values(id)
    row = rows.fetch("P-1")
    assert_equal [true, [], [], 4],
                 row.values_at("export_ready", "export_blockers", "zones", "ihg_usage_profile_default")
    assert_equal ["mechanical.item_unserved"], codes(row)

    [{ "device_type" => 5 }, { "ihg_usage_profile" => 0 }, { "ihg_usage_profile" => 5 },
     { "ihg_utilization_factor" => 1.5 }, { "ihg_utilization_factor" => -0.1 }, { "quantity" => 0 },
     { "norm_energy_demand_w" => -1.0 }, { "annual_period_operation_khrs" => -1.0 }].each do |bad|
      assert_equal %w[refused params.invalid],
                   invoke("#{PUMPS}.create", "values" => { "name" => "P-X" }.merge(bad)).values_at("status", "code"),
                   bad.inspect
      assert_equal %w[refused params.invalid],
                   invoke("#{PUMPS}.update", "id" => id, "values" => bad, "expected_values" => {})
                     .values_at("status", "code"), bad.inspect
    end
    assert_equal %w[refused validation.failed],
                 invoke("#{PUMPS}.create", "values" => { "name" => "p-1" }).values_at("status", "code"),
                 "a taken Tag, in any case"
    assert_equal ["P-1"], rows.keys
  end

  def test_the_usage_profile_follows_the_type_until_the_pump_names_one
    id = create("name" => "P-1")
    assert_equal 4, M::Pumps.ihg_usage_profile(values(id)), "hot water circulation: no gain"
    completed(invoke("#{PUMPS}.update", "id" => id, "values" => { "device_type" => 4 },
                                        "expected_values" => { "device_type" => 6 }))
    assert_equal [2, nil], [rows.fetch("P-1").fetch("ihg_usage_profile_default"), values(id)["ihg_usage_profile"]]
    assert_equal 2, M::Pumps.ihg_usage_profile(values(id)), "heating circulation: winter"

    completed(invoke("#{PUMPS}.update", "id" => id, "values" => { "ihg_usage_profile" => 3 },
                                        "expected_values" => { "ihg_usage_profile" => nil }))
    completed(invoke("#{PUMPS}.update", "id" => id, "values" => { "device_type" => 10 },
                                        "expected_values" => { "device_type" => 4 }))
    assert_equal [1, 3], [rows.fetch("P-1").fetch("ihg_usage_profile_default"), M::Pumps.ihg_usage_profile(values(id))],
                 "a profile the pump names stays through a type change"
    completed(invoke("#{PUMPS}.update", "id" => id, "values" => { "ihg_usage_profile" => nil },
                                        "expected_values" => { "ihg_usage_profile" => 3 }))
    assert_equal 1, M::Pumps.ihg_usage_profile(values(id)), "null follows the type again"
    refute values(id).key?("ihg_usage_profile")
  end

  def test_a_guarded_edit_and_a_duplicate_keep_their_values_and_metadata
    id = create({ "name" => "P-1", "manufacturer" => "Kaltwerk" }, { "firm" => { "tag" => "a" } })
    operations = @model.operations.length
    completed(invoke("#{PUMPS}.update", "id" => id, "values" => { "norm_energy_demand_w" => 25.0, "model" => "R-2" },
                                        "expected_values" => { "norm_energy_demand_w" => 0.0 }))
    assert_equal operations + 1, @model.operations.length
    assert_equal [25.0, "R-2"], values(id).values_at("norm_energy_demand_w", "model")
    assert_equal %w[refused target.changed],
                 invoke("#{PUMPS}.update", "id" => id, "values" => { "norm_energy_demand_w" => 40.0 },
                                           "expected_values" => { "norm_energy_demand_w" => 0.0 })
                   .values_at("status", "code")
    assert_equal 25.0, values(id).fetch("norm_energy_demand_w"), "a stale edit writes nothing"
    @model.undo
    assert_equal 0.0, values(id).fetch("norm_energy_demand_w")
    @model.redo

    copy = completed(invoke("#{PUMPS}.duplicate", "id" => id)).fetch("id")
    copied = rows.fetch("P-1 (copy)")
    assert_equal copy, copied.fetch("id")
    assert_equal [25.0, "Kaltwerk", "R-2", { "kind" => "derived" }],
                 copied.fetch("values").values_at("norm_energy_demand_w", "manufacturer", "model", "source")
    assert_equal({ "firm" => { "tag" => "a" } }, copied.fetch("user_data"))
  end

  def test_the_list_slot_holds_several_pumps_and_a_pump_serves_several_zones
    one = create("name" => "P-1")
    two = create("name" => "P-2", "device_type" => 4)
    completed(assign(["Apt 1", "Apt 2"], one))
    completed(assign(["Apt 1"], two))
    assert_equal [one, two].sort, slots("Apt 1").fetch(SLOT).sort
    assert_equal [one], slots("Apt 2").fetch(SLOT)
    assert_equal ["Apt 1", "Apt 2"], rows.fetch("P-1").fetch("zones").map { |zone| zone.fetch("name") }.sort
    assert_equal %w[P-1 P-2], serves_rows.fetch("Apt 1").fetch("items").map { |item| item.fetch("name") }.sort

    completed(assign(["Apt 1"], one))
    assert_equal 2, slots("Apt 1").fetch(SLOT).length, "a list holds a pump once"
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 1")], "slot" => SLOT, "item_id" => one))
    assert_equal [two], slots("Apt 1").fetch(SLOT)
    assert_equal %w[refused params.invalid],
                 invoke("#{SERVES}.assign", "zones" => [target("Apt 2")], "slot" => SLOT,
                                            "item_id" => "ehr_ZZZZZZZZZZZZ").values_at("status", "code"),
                 "an id of another kind"
  end

  def test_a_delete_refuses_in_use_and_a_replacement_or_null_rewrites_every_zones_list
    one = create("name" => "P-1")
    two = create("name" => "P-2")
    spare = create("name" => "P-3")
    completed(assign(["Apt 1", "Apt 2"], one))
    completed(assign(["Apt 1"], two))

    refusal = invoke("#{PUMPS}.delete", "id" => one)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code")
    assert_includes refusal.fetch("message"), "Apt 1, Apt 2"

    operations = @model.operations.length
    completed(invoke("#{PUMPS}.delete", "id" => one, "replacement_id" => two))
    assert_equal operations + 1, @model.operations.length
    assert_equal [two], slots("Apt 1").fetch(SLOT), "a list already holding the replacement keeps it once"
    assert_equal [two], slots("Apt 2").fetch(SLOT)
    refute rows.key?("P-1")
    @model.undo
    assert_equal [one, two].sort, slots("Apt 1").fetch(SLOT).sort
    assert_equal [one], slots("Apt 2").fetch(SLOT)
    assert rows.key?("P-1"), "Undo restores the pump and every Zone's list"

    completed(invoke("#{PUMPS}.delete", "id" => one, "replacement_id" => spare))
    assert_equal [spare, two].sort, slots("Apt 1").fetch(SLOT).sort
    completed(invoke("#{PUMPS}.delete", "id" => two, "replacement_id" => nil))
    assert_equal [spare], slots("Apt 1").fetch(SLOT), "null takes it out of each Zone's list"
    completed(invoke("#{PUMPS}.delete", "id" => spare, "replacement_id" => nil))
    assert_empty slots("Apt 1").fetch(SLOT)
    assert_empty slots("Apt 2").fetch(SLOT)
    assert_empty rows
  end

  private

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

  def create(values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    completed(invoke("#{PUMPS}.create", params)).fetch("id")
  end

  def values(id)
    query("#{PUMPS}.all").fetch("records").find { |row| row.fetch("id") == id }.fetch("values")
  end

  def rows
    query("#{PUMPS}.all").fetch("records").to_h { |row| [row.dig("values", "name"), row] }
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
