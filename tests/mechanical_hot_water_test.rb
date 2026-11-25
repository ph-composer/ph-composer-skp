# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The hot water catalogs with the panel closed (context/CONTRACTS.md, "Mechanical equipment"): Systems, and the
# Heaters and Tanks that name one; the variant rule, the slotting rule, a System's guarded delete over the Zones,
# Heaters and Tanks naming it, and the Serves slot. Apt 1 and Apt 2 are Zones in the Apartments Building Segment.
# Every write goes through the public actions, one Undo step each.
class MechanicalHotWaterTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  HW = M::HotWater
  PREFIX = "ph_composer.mechanical"
  SERVES = "#{PREFIX}.serves".freeze
  SYSTEMS = "#{PREFIX}.hot_water_systems".freeze
  HEATERS = "#{PREFIX}.hot_water_heaters".freeze
  TANKS = "#{PREFIX}.hot_water_tanks".freeze
  USER_DATA = { "firm" => { "tag" => ["original"] } }.freeze

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

  def test_a_system_three_tanks_and_two_heaters_round_trip_with_their_defaults
    assert_equal %w[refused params.invalid],
                 invoke("#{SYSTEMS}.create", "values" => { "name" => "X", "number_tap_points" => 0 })
                   .values_at("status", "code"), "honeybee-ph would read 0 tap points as unset"
    hws = create(SYSTEMS, "name" => " HWS-1 ", "number_tap_points" => 8)
    assert_match(/\Ahws_[A-Za-z0-9]{12}\z/, hws)
    assert_equal({ "name" => "HWS-1", "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" },
                   "number_tap_points" => 8 }, values(SYSTEMS, hws))
    t1 = create(TANKS, { "name" => "T1", "hot_water_system_id" => hws }, USER_DATA)
    assert_equal HW::Tanks::DEFAULTS.merge("name" => "T1", "notes" => "", "datasheet_links" => [],
                                           "source" => { "kind" => "manual" }, "hot_water_system_id" => hws),
                 values(TANKS, t1)
    create(TANKS, "name" => "T2", "hot_water_system_id" => hws, "storage_capacity_l" => 200, "standby_losses_w_k" => 3)
    create(TANKS, "name" => "T3", "hot_water_system_id" => hws, "role" => "buffer",
                  "tank_type" => "1-DHW AND HEATING", "storage_capacity_l" => 80, "standby_losses_w_k" => 1.5)
    electric = create(HEATERS, "name" => "H-E", "hot_water_system_id" => hws, "percent_coverage" => 0.3)
    assert_equal({ "variant" => "electric", "percent_coverage" => 0.3, "in_conditioned_space" => true },
                 values(HEATERS, electric).slice("variant", "percent_coverage", "in_conditioned_space"))
    pump = create(HEATERS, "name" => "H-HP", "hot_water_system_id" => hws, "variant" => "heat_pump_annual",
                           "percent_coverage" => 0.7, "total_system_perf_ratio" => 2.5)
    assert_equal 2.5, values(HEATERS, pump).fetch("total_system_perf_ratio")
    monthly = create(HEATERS, "name" => "H-M", "hot_water_system_id" => hws, "variant" => "heat_pump_monthly")
    assert_equal HW::Heaters::MONTHLY_DEFAULTS, values(HEATERS, monthly).slice(*HW::Heaters::MONTHLY_DEFAULTS.keys)

    system = rows(SYSTEMS).fetch("HWS-1")
    assert_equal [3, 3], system.values_at("tank_count", "heater_count")
    refute system.key?("recirculation"), "piping contributes recirculation to the Systems table; mechanical reads none"
    assert_equal ["mechanical.item_unserved"], codes(system)
    assert_equal USER_DATA, rows(TANKS).fetch("T1").fetch("user_data")
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    record = engine.find(M::HOT_WATER_TANK_KIND, t1)
    assert_equal record, JSON.parse(JSON.generate(record))
    assert_equal "ph_composer.records.#{M::HOT_WATER_TANK_KIND}", engine.kind(M::HOT_WATER_TANK_KIND).store.dictionary
    sections = PhComposer::Snapshot.build(@context).fetch("sections")
    [SYSTEMS, HEATERS, TANKS].each { |prefix| assert_equal query("#{prefix}.all"), sections.dig(prefix, "value") }
  end

  # A heater's variant picks its efficiency values: each is required for its variant and absent for
  # the others, so a change of variant gives the new and nulls the old in one edit.
  def test_a_heater_carrying_another_variants_value_or_missing_its_own_refuses
    hws = create(SYSTEMS, "name" => "HWS-1")
    revision = @session.revision
    # The variant rule is the kind's; a value out of its schema refuses at the params.
    [[{ "variant" => "electric", "cop_1" => 3.0 }, "validation.failed"],
     [{ "variant" => "heat_pump_annual" }, "validation.failed"],
     [{ "variant" => "heat_pump_annual", "total_system_perf_ratio" => 2.5, "annual_energy_factor" => 3.0 },
      "validation.failed"],
     [{ "variant" => "heat_pump_inside" }, "validation.failed"],
     [{ "variant" => "heat_pump_inside", "annual_energy_factor" => 0 }, "params.invalid"],
     [{ "variant" => "boiler" }, "params.invalid"],
     [{ "percent_coverage" => 1.2 }, "params.invalid"]].each do |extra, code|
      outcome = invoke("#{HEATERS}.create", "values" => { "name" => "H", "hot_water_system_id" => hws }.merge(extra))
      assert_equal ["refused", code], outcome.values_at("status", "code"), extra.inspect
    end
    assert_equal revision, @session.revision
    assert_equal ["A heat_pump_annual heater needs total_system_perf_ratio.",
                  "A heat_pump_annual heater takes no cop_1."],
                 HW::Heaters.variant_problems("variant" => "heat_pump_annual", "cop_1" => 2.0)

    id = create(HEATERS, "name" => "H", "hot_water_system_id" => hws, "variant" => "heat_pump_annual",
                         "total_system_perf_ratio" => 2.5)
    outcome = invoke("#{HEATERS}.update", "id" => id, "values" => { "variant" => "heat_pump_inside" },
                                          "expected_values" => {})
    assert_equal %w[refused validation.failed], outcome.values_at("status", "code")
    inside = { "variant" => "heat_pump_inside", "total_system_perf_ratio" => nil, "annual_energy_factor" => 3.2 }
    completed(invoke("#{HEATERS}.update", "id" => id, "values" => inside,
                                          "expected_values" => { "variant" => "heat_pump_annual" }))
    stored = values(HEATERS, id)
    assert_equal ["heat_pump_inside", 3.2], stored.values_at("variant", "annual_energy_factor")
    refute stored.key?("total_system_perf_ratio")
  end

  def test_a_heater_or_tank_naming_a_missing_system_or_none_refuses_and_names_are_unique
    hws = create(SYSTEMS, "name" => "HWS-1")
    [[HEATERS, "reference.invalid", { "hot_water_system_id" => "hws_ZZZZZZZZZZZZ" }],
     [TANKS, "reference.invalid", { "hot_water_system_id" => "hws_ZZZZZZZZZZZZ" }],
     [TANKS, "params.invalid", { "hot_water_system_id" => hws, "role" => "spare" }],
     [TANKS, "params.invalid", { "hot_water_system_id" => hws, "tank_type" => "2-DHW only" }]]
      .each do |prefix, code, values|
      outcome = invoke("#{prefix}.create", "values" => { "name" => "X" }.merge(values))
      assert_equal ["refused", code], outcome.values_at("status", "code"), "#{prefix} #{values.inspect}"
    end
    outcome = invoke("#{TANKS}.create", "values" => { "name" => "X" })
    refute_equal "committed", outcome["effect"], "a Tank names its System"
    create(TANKS, "name" => "T1", "hot_water_system_id" => hws)
    assert_equal %w[refused validation.failed],
                 invoke("#{TANKS}.create", "values" => { "name" => "t1 ", "hot_water_system_id" => hws })
                   .values_at("status", "code")
  end

  def test_duplicate_keeps_the_system_and_user_data_and_each_write_is_one_undo_step
    hws = create(SYSTEMS, "name" => "HWS-1")
    tank = create(TANKS, { "name" => "T1", "hot_water_system_id" => hws }, USER_DATA)
    operations = @model.operations.length
    copy = completed(invoke("#{TANKS}.duplicate", "id" => tank)).fetch("id")
    assert_equal operations + 1, @model.operations.length
    copied = rows(TANKS).fetch("T1 (copy)")
    assert_equal [copy, hws, { "kind" => "derived" }, USER_DATA],
                 [copied.fetch("id"), copied.dig("values", "hot_water_system_id"), copied.dig("values", "source"),
                  copied.fetch("user_data")]
    @model.undo
    assert_nil rows(TANKS)["T1 (copy)"]
    completed(invoke("#{TANKS}.delete", "id" => tank, "expected_values" => { "name" => "T1" }))
    assert_empty rows(TANKS)
    @model.undo
    assert_equal USER_DATA, rows(TANKS).fetch("T1").fetch("user_data")
    system_copy = completed(invoke("#{SYSTEMS}.duplicate", "id" => hws, "name" => "HWS-2")).fetch("id")
    counts = rows(SYSTEMS).transform_values { |row| row.fetch("tank_count") }
    assert_equal({ "HWS-1" => 1, "HWS-2" => 0 }, counts, "a System copy takes no Tanks: they name the original")
    assert_equal system_copy, rows(SYSTEMS).fetch("HWS-2").fetch("id")
  end

  # ---------------------------------------------------------------- slotting

  def test_slotting_by_role_on_the_reference_system_and_its_overflow
    tank = ->(name, role) { { "id" => "hwt_#{name.ljust(12, 'x')}", "name" => name, "role" => role } }
    reference = [tank.call("T3", "buffer"), tank.call("T2", "storage"), tank.call("T1", "storage")]
    result = HW::Slotting.call(reference)
    assert_equal({ "tank_1" => "T1", "tank_2" => "T2", "tank_buffer" => "T3", "tank_solar" => nil },
                 result.slots.transform_values { |row| row && row.fetch("name") })
    assert_empty result.unslotted
    assert_equal "tank_buffer", result.slot_of(tank.call("T3", "buffer").fetch("id"))

    overflow = HW::Slotting.call(reference + [tank.call("T4", "storage"), tank.call("T5", "buffer"),
                                              tank.call("S1", "solar"), tank.call("S2", "solar")])
    assert_equal %w[T4 T5 S2].sort, overflow.unslotted.map { |row| row.fetch("name") }.sort
    assert_equal "S1", overflow.slots.fetch("tank_solar").fetch("name")
    assert_equal HW::Slotting::SLOTS.to_h { |slot| [slot, nil] }, HW::Slotting.call([]).slots
    cased = HW::Slotting.call([tank.call("T3", "storage"), tank.call("T2", "storage"), tank.call("t1", "storage")])
    assert_equal [%w[t1 T2], %w[T3]], [cased.slots.values_at("tank_1", "tank_2").map { |row| row.fetch("name") },
                                       cased.unslotted.map { |row| row.fetch("name") }], "name order ignores case"

    hws = create(SYSTEMS, "name" => "HWS-1")
    %w[T3 T2 T1 T4].zip(%w[buffer storage storage storage]).each do |name, role|
      create(TANKS, "name" => name, "hot_water_system_id" => hws, "role" => role)
    end
    tanks = rows(TANKS)
    assert_equal({ "T1" => "tank_1", "T2" => "tank_2", "T3" => "tank_buffer", "T4" => nil },
                 tanks.transform_values { |row| row.fetch("slot") })
    assert_equal ["mechanical.tank_unslotted"], codes(tanks.fetch("T4"))
    assert_empty codes(tanks.fetch("T1"))
  end

  # ---------------------------------------------------------------- Serves and delete

  def test_the_serves_slot_assigns_replaces_and_clears_a_hot_water_system
    one = create(SYSTEMS, "name" => "HWS-1")
    two = create(SYSTEMS, "name" => "HWS-2")
    operations = @model.operations.length
    completed(assign(["Apt 1", "Apt 2"], one))
    assert_equal operations + 1, @model.operations.length
    assert_equal [one, one], %w[Apt\ 1 Apt\ 2].map { |name| slots(name).fetch("hot_water_system_id") }
    assert_empty codes(serves_rows.fetch("Apt 1")).grep(/hot_water/)
    refusal = assign(["Apt 2"], two)
    assert_equal %w[refused mechanical.slot_filled], refusal.values_at("status", "code")
    assert_match(/HWS-1/, refusal.fetch("message"))
    completed(assign(["Apt 2"], two, :replace => true))
    assert_equal two, slots("Apt 2").fetch("hot_water_system_id")
    assert_equal %w[Apt\ 1], rows(SYSTEMS).fetch("HWS-1").fetch("zones").map { |zone| zone.fetch("name") }
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 2")], "slot" => "hot_water_system_id"))
    assert_nil slots("Apt 2").fetch("hot_water_system_id")
    assert_includes codes(serves_rows.fetch("Apt 2")), "mechanical.zone_no_hot_water"
  end

  # Two Systems serving one Building Segment are pooled downstream: each row says so, as info.
  def test_two_served_systems_in_one_building_segment_carry_the_pooling_note
    one = create(SYSTEMS, "name" => "HWS-1")
    two = create(SYSTEMS, "name" => "HWS-2")
    completed(assign(["Apt 1"], one))
    assert_equal [], codes(rows(SYSTEMS).fetch("HWS-1"))
    assert_equal ["mechanical.item_unserved"], codes(rows(SYSTEMS).fetch("HWS-2")), "unserved, never pooled"
    completed(assign(["Apt 2"], two))
    systems = rows(SYSTEMS)
    [systems.fetch("HWS-1"), systems.fetch("HWS-2")].each do |row|
      assert_equal [["mechanical.hot_water_pooled", "info", false]],
                   row.fetch("findings").map { |found| found.values_at("code", "severity", "blocks_export") }
      assert_match(/HWS-1, HWS-2 serve Building Segment Apartments/, row.fetch("findings").first.fetch("message"))
    end

    completed(invoke("ph_composer.zones.update_field",
                     "field" => "building_segment", "value" => nil,
                     "targets" => %w[Apt\ 1 Apt\ 2].map do |name|
                       row = zone_row(name)
                       { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") }
                     end))
    rows(SYSTEMS).each_value do |row|
      assert_equal ["mechanical.zone_left_out"], codes(row), "Zones the export leaves out pool nothing"
    end
  end

  # A calculation method the pinned honeybee-ph cannot carry is noted on its System's row, as info, while it is set.
  def test_a_piping_calculation_method_is_noted_on_its_systems_row_while_set
    hws = create(SYSTEMS, "name" => "HWS-1", "piping_calc_method" => 2)
    completed(assign(["Apt 1"], hws))
    found = rows(SYSTEMS).fetch("HWS-1").fetch("findings")
    assert_equal [["mechanical.method_not_exported", "info", false]],
                 found.map { |row| row.values_at("code", "severity", "blocks_export") }
    assert_match(/HWS-1 sets piping calculation method 2, and the pinned honeybee-ph has no field/,
                 found.first.fetch("message"))
    completed(invoke("#{SYSTEMS}.update", "id" => hws, "values" => { "piping_calc_method" => nil },
                                          "expected_values" => { "piping_calc_method" => 2 }))
    assert_empty codes(rows(SYSTEMS).fetch("HWS-1"))
  end

  # By hot water system colours each Zone its System serves in that System's colour; an unserved Zone has no entry,
  # and the legend counts Zones.
  def test_by_hot_water_system_gives_one_entry_per_served_zone_and_leaves_an_unserved_zone_out
    one = create(SYSTEMS, "name" => "HWS-1")
    two = create(SYSTEMS, "name" => "HWS-2")
    completed(assign(["Apt 1"], one))
    declaration = PhComposer::Registry.current.colour_modes.fetch(M::ColourModes::BY_HOT_WATER_SYSTEM)
    assert_equal ["Hot Water System", "zone"], [declaration.label, declaration.entity_kind]
    read = PhComposer::HandlerRequest.for(@session, :owner => declaration.owner, :name => declaration.name)
    assert_equal [[[1000], one, "HWS-1"]],
                 Array(declaration.projection.call(read)).map { |entry| [entry.path, entry.value, entry.label] }
    completed(assign(["Apt 2"], two))
    service = PhComposer::ColourBy.for(@session).activate(M::ColourModes::BY_HOT_WATER_SYSTEM)
    assert_equal({ "HWS-1" => 1, "HWS-2" => 1 }, service.rows.to_h { |row| [row.label, row.count] })
  end

  def test_deleting_a_system_in_use_refuses_and_a_replacement_moves_zones_heaters_and_tanks_in_one_undo_step
    one = create(SYSTEMS, "name" => "HWS-1")
    two = create(SYSTEMS, "name" => "HWS-2")
    heater = create(HEATERS, "name" => "H-E", "hot_water_system_id" => one)
    tank = create(TANKS, "name" => "T1", "hot_water_system_id" => one)
    owners = -> { [values(HEATERS, heater), values(TANKS, tank)].map { |row| row.fetch("hot_water_system_id") } }

    refusal = invoke("#{SYSTEMS}.delete", "id" => one)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code"), "a Heater or Tank names it"
    completed(assign(["Apt 1"], one))
    refusal = invoke("#{SYSTEMS}.delete", "id" => one)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code")
    assert_match(/serves Apt 1/, refusal.fetch("message"))
    refusal = invoke("#{SYSTEMS}.delete", "id" => one, "replacement_id" => nil)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code"),
                 "null empties the Zones, and the Heater and Tank still name it"
    assert_equal one, slots("Apt 1").fetch("hot_water_system_id"), "a refused delete writes nothing"

    operations = @model.operations.length
    revision = @session.revision
    completed(invoke("#{SYSTEMS}.delete", "id" => one, "replacement_id" => two))
    assert_equal operations + 1, @model.operations.length
    assert_equal two, slots("Apt 1").fetch("hot_water_system_id")
    assert_equal [two, two], owners.call
    assert_nil rows(SYSTEMS)["HWS-1"]
    @model.undo
    assert_equal one, slots("Apt 1").fetch("hot_water_system_id")
    assert_equal [one, one], owners.call
    refute_nil rows(SYSTEMS)["HWS-1"]
    refute_equal revision, @session.revision

    completed(invoke("#{HEATERS}.delete", "id" => heater))
    completed(invoke("#{TANKS}.delete", "id" => tank))
    completed(invoke("#{SYSTEMS}.delete", "id" => one, "replacement_id" => nil))
    assert_nil slots("Apt 1").fetch("hot_water_system_id"), "with no Heater or Tank, null empties the Zone"
  end

  # A stale guard, the System itself or a missing System as replacement, and an unreadable Heater each refuse the
  # delete whole.
  def test_a_system_delete_with_a_stale_guard_a_bad_replacement_or_an_unreadable_member_refuses
    one = create(SYSTEMS, "name" => "HWS-1")
    two = create(SYSTEMS, "name" => "HWS-2")
    heater = create(HEATERS, "name" => "H-E", "hot_water_system_id" => one)
    completed(assign(["Apt 1"], one))
    [[{ "replacement_id" => two, "expected_values" => { "name" => "HWS-0" } }, "target.changed"],
     [{ "replacement_id" => one }, "params.invalid"],
     [{ "replacement_id" => "hws_ZZZZZZZZZZZZ" }, "target.not_found"]].each do |params, code|
      outcome = invoke("#{SYSTEMS}.delete", { "id" => one }.merge(params))
      assert_equal ["refused", code], outcome.values_at("status", "code"), params.inspect
    end
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    store = engine.kind(M::HOT_WATER_HEATER_KIND).store
    store.write(@model, engine.find(M::HOT_WATER_HEATER_KIND, heater).merge("schema_version" => 9))
    refusal = invoke("#{SYSTEMS}.delete", "id" => one, "replacement_id" => two)
    assert_equal %w[refused record.unreadable], refusal.values_at("status", "code")
    assert_equal one, slots("Apt 1").fetch("hot_water_system_id"), "nothing is written"
    refute_nil rows(SYSTEMS)["HWS-1"]
  end

  # Another feature's entity records naming a System: its registered retargeter moves them to the replacement, or
  # clears them with null, in the delete's one Undo step, and Mechanical names no such feature.
  def test_a_system_delete_retargets_another_features_referrer_through_the_engine
    install_foreign_referrer
    one = create(SYSTEMS, "name" => "HWS-1")
    two = create(SYSTEMS, "name" => "HWS-2")
    holder = Sketchup::Group.new(9000, Sketchup::Entities.new([]))
    holder.set_attribute(FOREIGN_DICTIONARY, "record", JSON.generate("id" => "probe_1", "hot_water_system_id" => one))
    @model.entities << holder
    assert_equal %w[refused reference.in_use], invoke("#{SYSTEMS}.delete", "id" => one).values_at("status", "code")
    assert_equal "committed", invoke("#{SYSTEMS}.delete", "id" => one, "replacement_id" => two)["effect"]
    assert_equal two, foreign_system(9000)
    @model.undo
    assert_equal one, foreign_system(9000)
    assert_equal "committed", invoke("#{SYSTEMS}.delete", "id" => one, "replacement_id" => nil)["effect"]
    assert_nil foreign_system(9000)
  end

  private

  FOREIGN_DICTIONARY = "ph_composer.test_hot_water_referrer"

  # A probe feature requiring Mechanical: a record on a root Group naming a System, its reference target and its
  # retargeter, which rewrites the record in a step of its own.
  def install_foreign_referrer
    reference = PhComposer::Records::Reference.new(:key => "hot_water_system_id",
                                                   :target_kind => M::HOT_WATER_SYSTEM_KIND, :cardinality => "one")
    entries = lambda do |model|
      model.entities.to_a.filter_map do |entity|
        text = entity.get_attribute(FOREIGN_DICTIONARY, "record")
        text && PhComposer::Records::ReferenceEntry.new(:kind => "test.referrer.entity", :key => [entity.persistent_id],
                                                        :record => JSON.parse(text))
      end
    end
    target = PhComposer::Records::ReferenceTarget.new(:id => "test.referrer.entity", :label => "Referrer",
                                                      :records => entries, :validate => ->(_record) { [] },
                                                      :references => [reference])
    probe = Module.new
    probe.define_singleton_method(:name) { "HotWaterReferrerProbe" }
    probe.define_singleton_method(:install) do |registry|
      scope = registry.feature("test.referrer", :contract_version => 1, :requires => ["ph_composer.mechanical"])
      scope.reference_target(target)
      retarget = "test.referrer.retarget"
      scope.reference_retargeter(retarget, :target_kind => M::HOT_WATER_SYSTEM_KIND) do |request, proposal, from:, to:|
        named = entries.call(request.model).select { |entry| entry.record["hot_water_system_id"] == from }
        moved = named.map do |entry|
          PhComposer::Records::ReferenceEntry.new(:kind => entry.kind, :key => entry.key,
                                                  :record => entry.record.merge("hot_water_system_id" => to))
        end
        moved.each do |entry|
          proposal.add_step(ForeignRetargetStep.new(entry.key.first, entry.record),
                            :scopes => [PhComposer::Operations::EntityScope.new([])])
        end
        PhComposer::Records::ReferencePlan.new(:entries => moved)
      end
    end
    PhComposer::Registry.install([probe])
  end

  def foreign_system(persistent_id)
    holder = @model.entities.to_a.find { |entity| entity.persistent_id == persistent_id }
    JSON.parse(holder.get_attribute(FOREIGN_DICTIONARY, "record")).fetch("hot_water_system_id")
  end

  # Writes one probe record on a root Group.
  class ForeignRetargetStep
    def initialize(persistent_id, record)
      @persistent_id = persistent_id
      @record = record
    end

    def apply(model, _slots)
      holder = model.entities.to_a.find { |entity| entity.persistent_id == @persistent_id }
      holder.set_attribute(FOREIGN_DICTIONARY, "record", JSON.generate(@record))
    end

    def descriptor
      { "persistent_id" => @persistent_id, "record" => @record }
    end

    def affected
      [{ "kind" => "test.referrer.entity", "id" => @record.fetch("id"), "change" => "updated" }]
    end
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

  def assign(names, item_id, replace: nil)
    params = { "zones" => names.map { |name| target(name) }, "slot" => "hot_water_system_id", "item_id" => item_id }
    params["replace"] = replace unless replace.nil?
    invoke("#{SERVES}.assign", params)
  end

  def target(name)
    row = serves_rows.fetch(name)
    { "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }
  end

  def zone_row(name)
    query("ph_composer.zones.all").fetch("zones").find { |row| row.dig("values", "name") == name }
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
