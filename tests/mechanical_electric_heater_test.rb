# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The Electric Heater catalog with the panel closed (context/CONTRACTS.md, "Mechanical equipment"): the kind and its
# defaults, the guarded edit, Duplicate with its metadata, the `heater_ids` list slot on the Zone, and the guarded
# delete with a replacement or none. Apt 1 and Apt 2 are Zones in the Apartments Building Segment. Every write goes
# through the public actions, one Undo step each.
class MechanicalElectricHeaterTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  PREFIX = "ph_composer.mechanical"
  HEATERS = "#{PREFIX}.electric_heaters".freeze
  SERVES = "#{PREFIX}.serves".freeze
  SLOT = "heater_ids"
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

  def test_a_heater_covers_the_whole_load_by_default_and_a_coverage_outside_0_to_1_refuses
    id = create("name" => " EH-1 ")
    assert_match(/\Aehr_[A-Za-z0-9]{12}\z/, id)
    assert_equal COMMON.merge("name" => "EH-1", "percent_coverage" => 1.0), values(id)
    row = rows.fetch("EH-1")
    assert_equal [true, [], []], row.values_at("export_ready", "export_blockers", "zones")
    assert_equal ["mechanical.item_unserved"], codes(row)

    [-0.1, 1.5].each do |bad|
      assert_equal %w[refused params.invalid],
                   invoke("#{HEATERS}.create", "values" => { "name" => "EH-X", "percent_coverage" => bad })
                     .values_at("status", "code"), bad.to_s
      assert_equal %w[refused params.invalid],
                   invoke("#{HEATERS}.update", "id" => id, "values" => { "percent_coverage" => bad },
                                               "expected_values" => {}).values_at("status", "code"), bad.to_s
    end
    assert_equal %w[refused validation.failed],
                 invoke("#{HEATERS}.create", "values" => { "name" => "eh-1" }).values_at("status", "code"),
                 "a taken Tag, in any case"
    assert_equal %w[refused params.invalid],
                 invoke("#{HEATERS}.create", "values" => { "name" => "EH-X", "in_conditioned_space" => true })
                   .values_at("status", "code"), "PhHeatingDirectElectric has no such value"
    assert_equal ["EH-1"], rows.keys
  end

  def test_a_guarded_edit_and_a_duplicate_keep_their_values_and_metadata
    id = create({ "name" => "EH-1", "manufacturer" => "Kaltwerk" }, { "firm" => { "tag" => "a" } })
    operations = @model.operations.length
    completed(invoke("#{HEATERS}.update", "id" => id, "values" => { "percent_coverage" => 0.25, "model" => "R-2" },
                                          "expected_values" => { "percent_coverage" => 1.0 }))
    assert_equal operations + 1, @model.operations.length
    assert_equal [0.25, "R-2"], values(id).values_at("percent_coverage", "model")
    assert_equal %w[refused target.changed],
                 invoke("#{HEATERS}.update", "id" => id, "values" => { "percent_coverage" => 0.5 },
                                             "expected_values" => { "percent_coverage" => 1.0 })
                   .values_at("status", "code")
    assert_equal 0.25, values(id).fetch("percent_coverage"), "a stale edit writes nothing"
    @model.undo
    assert_equal 1.0, values(id).fetch("percent_coverage")
    @model.redo

    copy = completed(invoke("#{HEATERS}.duplicate", "id" => id)).fetch("id")
    copied = rows.fetch("EH-1 (copy)")
    assert_equal copy, copied.fetch("id")
    assert_equal [0.25, "Kaltwerk", "R-2", { "kind" => "derived" }],
                 copied.fetch("values").values_at("percent_coverage", "manufacturer", "model", "source")
    assert_equal({ "firm" => { "tag" => "a" } }, copied.fetch("user_data"))
  end

  def test_the_list_slot_holds_several_heaters_and_a_heater_serves_several_zones
    one = create("name" => "EH-1")
    two = create("name" => "EH-2", "percent_coverage" => 1.0)
    completed(assign(["Apt 1", "Apt 2"], one))
    completed(assign(["Apt 1"], two))
    assert_equal [one, two].sort, slots("Apt 1").fetch(SLOT).sort
    assert_equal [one], slots("Apt 2").fetch(SLOT)
    assert_equal ["Apt 1", "Apt 2"], rows.fetch("EH-1").fetch("zones").map { |zone| zone.fetch("name") }.sort
    assert_empty codes(rows.fetch("EH-2")), "two heaters at 100% on one Zone: no coverage check"
    assert_equal %w[EH-1 EH-2], serves_rows.fetch("Apt 1").fetch("items").map { |item| item.fetch("name") }.sort

    completed(assign(["Apt 1"], one))
    assert_equal 2, slots("Apt 1").fetch(SLOT).length, "a list holds a heater once"
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 1")], "slot" => SLOT, "item_id" => one))
    assert_equal [two], slots("Apt 1").fetch(SLOT)
    assert_equal %w[refused params.invalid],
                 invoke("#{SERVES}.assign", "zones" => [target("Apt 2")], "slot" => SLOT,
                                            "item_id" => "hiu_ZZZZZZZZZZZZ").values_at("status", "code"),
                 "an id of another kind"
  end

  def test_a_delete_refuses_in_use_and_a_replacement_or_null_rewrites_every_zones_list
    one = create("name" => "EH-1")
    two = create("name" => "EH-2")
    spare = create("name" => "EH-3")
    completed(assign(["Apt 1", "Apt 2"], one))
    completed(assign(["Apt 1"], two))

    refusal = invoke("#{HEATERS}.delete", "id" => one)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code")
    assert_includes refusal.fetch("message"), "Apt 1, Apt 2"

    operations = @model.operations.length
    completed(invoke("#{HEATERS}.delete", "id" => one, "replacement_id" => two))
    assert_equal operations + 1, @model.operations.length
    assert_equal [two], slots("Apt 1").fetch(SLOT), "a list already holding the replacement keeps it once"
    assert_equal [two], slots("Apt 2").fetch(SLOT)
    refute rows.key?("EH-1")
    @model.undo
    assert_equal [one, two].sort, slots("Apt 1").fetch(SLOT).sort
    assert_equal [one], slots("Apt 2").fetch(SLOT)
    assert rows.key?("EH-1"), "Undo restores the heater and every Zone's list"

    completed(invoke("#{HEATERS}.delete", "id" => one, "replacement_id" => spare))
    assert_equal [spare, two].sort, slots("Apt 1").fetch(SLOT).sort
    completed(invoke("#{HEATERS}.delete", "id" => two, "replacement_id" => nil))
    assert_equal [spare], slots("Apt 1").fetch(SLOT), "null takes it out of each Zone's list"
    completed(invoke("#{HEATERS}.delete", "id" => spare, "replacement_id" => nil))
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
    completed(invoke("#{HEATERS}.create", params)).fetch("id")
  end

  def values(id)
    query("#{HEATERS}.all").fetch("records").find { |row| row.fetch("id") == id }.fetch("values")
  end

  def rows
    query("#{HEATERS}.all").fetch("records").to_h { |row| [row.dig("values", "name"), row] }
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
