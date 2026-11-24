# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The Fan catalog with the panel closed (context/CONTRACTS.md, "Mechanical equipment"): the kind and its defaults, the
# operation its runtime gives until it names one, the guarded edit, Duplicate with its metadata, the `fan_ids` list
# slot on the Zone, and the guarded delete with a replacement or none. Apt 1 and Apt 2 are Zones in the Apartments
# Building Segment. Every write goes through the public actions, one Undo step each.
class MechanicalFanTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  PREFIX = "ph_composer.mechanical"
  FANS = "#{PREFIX}.fans".freeze
  SERVES = "#{PREFIX}.serves".freeze
  SLOT = "fan_ids"
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

  def test_a_fan_takes_honeybee_phs_values_by_default_and_a_value_outside_its_range_refuses
    id = create("name" => " F-1 ")
    assert_match(/\Afan_[A-Za-z0-9]{12}\z/, id)
    assert_equal COMMON.merge("name" => "F-1", "exhaust_type" => "user_defined", "quantity" => 1,
                              "exhaust_flow_rate_m3h" => 0.0, "annual_runtime_minutes" => 0.0,
                              "in_conditioned_space" => true), values(id)
    refute values(id).key?("norm_energy_demand_w"), "no Power, so no supportive device"
    row = rows.fetch("F-1")
    assert_equal [true, [], [], 0.0],
                 row.values_at("export_ready", "export_blockers", "zones", "annual_period_operation_khrs_default")
    assert_equal ["mechanical.item_unserved"], codes(row)

    [{ "exhaust_type" => "range_hood" }, { "quantity" => 0 }, { "exhaust_flow_rate_m3h" => -1.0 },
     { "annual_runtime_minutes" => -1.0 }, { "norm_energy_demand_w" => -1.0 },
     { "annual_period_operation_khrs" => -1.0 }, { "in_conditioned_space" => "yes" }].each do |bad|
      assert_equal %w[refused params.invalid],
                   invoke("#{FANS}.create", "values" => { "name" => "F-X" }.merge(bad)).values_at("status", "code"),
                   bad.inspect
      assert_equal %w[refused params.invalid],
                   invoke("#{FANS}.update", "id" => id, "values" => bad, "expected_values" => {})
                     .values_at("status", "code"), bad.inspect
    end
    assert_equal %w[refused validation.failed],
                 invoke("#{FANS}.create", "values" => { "name" => "f-1" }).values_at("status", "code"),
                 "a taken Tag, in any case"
    assert_equal ["F-1"], rows.keys
  end

  def test_the_operation_follows_the_runtime_until_the_fan_names_one
    id = create("name" => "F-1", "exhaust_type" => "kitchen_hood", "norm_energy_demand_w" => 120.0)
    completed(invoke("#{FANS}.update", "id" => id, "values" => { "annual_runtime_minutes" => 60_000.0 },
                                       "expected_values" => { "annual_runtime_minutes" => 0.0 }))
    assert_equal [1.0, nil],
                 [rows.fetch("F-1").fetch("annual_period_operation_khrs_default"),
                  values(id)["annual_period_operation_khrs"]]
    assert_equal 1.0, M::Fans.annual_period_operation_khrs(values(id)), "60,000 minutes a year is 1 kh"

    completed(invoke("#{FANS}.update", "id" => id, "values" => { "annual_period_operation_khrs" => 2.5 },
                                       "expected_values" => { "annual_period_operation_khrs" => nil }))
    completed(invoke("#{FANS}.update", "id" => id, "values" => { "annual_runtime_minutes" => 30_000.0 },
                                       "expected_values" => { "annual_runtime_minutes" => 60_000.0 }))
    assert_equal [0.5, 2.5], [rows.fetch("F-1").fetch("annual_period_operation_khrs_default"),
                              M::Fans.annual_period_operation_khrs(values(id))],
                 "an operation the fan names stays through a runtime change"
    completed(invoke("#{FANS}.update", "id" => id, "values" => { "annual_period_operation_khrs" => nil },
                                       "expected_values" => { "annual_period_operation_khrs" => 2.5 }))
    assert_equal 0.5, M::Fans.annual_period_operation_khrs(values(id)), "null follows the runtime again"
    refute values(id).key?("annual_period_operation_khrs")
    completed(invoke("#{FANS}.update", "id" => id, "values" => { "norm_energy_demand_w" => nil },
                                       "expected_values" => { "norm_energy_demand_w" => 120.0 }))
    refute values(id).key?("norm_energy_demand_w"), "a blank Power takes the supportive device away"
  end

  def test_a_guarded_edit_and_a_duplicate_keep_their_values_and_metadata
    id = create({ "name" => "F-1", "manufacturer" => "Kaltwerk" }, { "firm" => { "tag" => "a" } })
    operations = @model.operations.length
    completed(invoke("#{FANS}.update", "id" => id, "values" => { "exhaust_flow_rate_m3h" => 250.0, "model" => "R-2" },
                                       "expected_values" => { "exhaust_flow_rate_m3h" => 0.0 }))
    assert_equal operations + 1, @model.operations.length
    assert_equal [250.0, "R-2"], values(id).values_at("exhaust_flow_rate_m3h", "model")
    assert_equal %w[refused target.changed],
                 invoke("#{FANS}.update", "id" => id, "values" => { "exhaust_flow_rate_m3h" => 300.0 },
                                          "expected_values" => { "exhaust_flow_rate_m3h" => 0.0 })
                   .values_at("status", "code")
    assert_equal 250.0, values(id).fetch("exhaust_flow_rate_m3h"), "a stale edit writes nothing"
    @model.undo
    assert_equal 0.0, values(id).fetch("exhaust_flow_rate_m3h")
    @model.redo

    copy = completed(invoke("#{FANS}.duplicate", "id" => id)).fetch("id")
    copied = rows.fetch("F-1 (copy)")
    assert_equal copy, copied.fetch("id")
    assert_equal [250.0, "Kaltwerk", "R-2", { "kind" => "derived" }],
                 copied.fetch("values").values_at("exhaust_flow_rate_m3h", "manufacturer", "model", "source")
    assert_equal({ "firm" => { "tag" => "a" } }, copied.fetch("user_data"))
  end

  def test_the_list_slot_holds_several_fans_and_a_fan_serves_several_zones
    one = create("name" => "F-1")
    two = create("name" => "F-2", "exhaust_type" => "dryer")
    completed(assign(["Apt 1", "Apt 2"], one))
    completed(assign(["Apt 1"], two))
    assert_equal [one, two].sort, slots("Apt 1").fetch(SLOT).sort
    assert_equal [one], slots("Apt 2").fetch(SLOT)
    assert_equal ["Apt 1", "Apt 2"], rows.fetch("F-1").fetch("zones").map { |zone| zone.fetch("name") }.sort
    assert_equal %w[F-1 F-2], serves_rows.fetch("Apt 1").fetch("items").map { |item| item.fetch("name") }.sort

    completed(assign(["Apt 1"], one))
    assert_equal 2, slots("Apt 1").fetch(SLOT).length, "a list holds a fan once"
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 1")], "slot" => SLOT, "item_id" => one))
    assert_equal [two], slots("Apt 1").fetch(SLOT)
    assert_equal %w[refused params.invalid],
                 invoke("#{SERVES}.assign", "zones" => [target("Apt 2")], "slot" => SLOT,
                                            "item_id" => "ehr_ZZZZZZZZZZZZ").values_at("status", "code"),
                 "an id of another kind"
  end

  def test_a_delete_refuses_in_use_and_a_replacement_or_null_rewrites_every_zones_list
    one = create("name" => "F-1")
    two = create("name" => "F-2")
    spare = create("name" => "F-3")
    completed(assign(["Apt 1", "Apt 2"], one))
    completed(assign(["Apt 1"], two))

    refusal = invoke("#{FANS}.delete", "id" => one)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code")
    assert_includes refusal.fetch("message"), "Apt 1, Apt 2"

    operations = @model.operations.length
    completed(invoke("#{FANS}.delete", "id" => one, "replacement_id" => two))
    assert_equal operations + 1, @model.operations.length
    assert_equal [two], slots("Apt 1").fetch(SLOT), "a list already holding the replacement keeps it once"
    assert_equal [two], slots("Apt 2").fetch(SLOT)
    refute rows.key?("F-1")
    @model.undo
    assert_equal [one, two].sort, slots("Apt 1").fetch(SLOT).sort
    assert_equal [one], slots("Apt 2").fetch(SLOT)
    assert rows.key?("F-1"), "Undo restores the fan and every Zone's list"

    completed(invoke("#{FANS}.delete", "id" => one, "replacement_id" => spare))
    assert_equal [spare, two].sort, slots("Apt 1").fetch(SLOT).sort
    completed(assign(["Apt 2"], two))
    operations = @model.operations.length
    completed(invoke("#{FANS}.delete", "id" => two, "replacement_id" => nil))
    assert_equal operations + 1, @model.operations.length
    assert_equal [spare], slots("Apt 1").fetch(SLOT), "null takes it out of each Zone's list"
    assert_equal [spare], slots("Apt 2").fetch(SLOT)
    @model.undo
    assert_equal [spare, two].sort, slots("Apt 1").fetch(SLOT).sort
    assert_equal [spare, two].sort, slots("Apt 2").fetch(SLOT).sort
    assert rows.key?("F-2"), "one Undo restores the fan and both Zones' lists"
    @model.redo
    assert_equal [spare], slots("Apt 1").fetch(SLOT)
    completed(invoke("#{FANS}.delete", "id" => spare, "replacement_id" => nil))
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
    completed(invoke("#{FANS}.create", params)).fetch("id")
  end

  def values(id)
    query("#{FANS}.all").fetch("records").find { |row| row.fetch("id") == id }.fetch("values")
  end

  def rows
    query("#{FANS}.all").fetch("records").to_h { |row| [row.dig("values", "name"), row] }
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
