# frozen_string_literal: true

require_relative "test_helper"

# Programs, Schedules and Equipment Sets: the three record kinds, the PH Schedule forms and their
# profile, rule loads, device editing, the residential default Program and default Equipment Set that reads answer
# until a write stores them, the Model's defaults and guarded deletes, each write one Undo step.
class ProgramRecordsTest < PhComposerTestCase
  include FixtureFiles

  API = PhComposer::API
  P = PhComposer::Programs
  PREFIX = P::FEATURE_ID
  DEFAULT_PROGRAM = P::DefaultProgram::PROGRAM_ID
  DEFAULT_SET = P::DefaultEquipmentSet::SET_ID

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  # ---------------------------------------------------------------- kinds

  def test_each_kind_round_trips_and_an_unknown_key_or_another_version_is_unreadable
    schedule = id_of(invoke!("schedules.create", "values" => { "name" => "Office", "start_h" => 7, "end_h" => 18 }))
    program = id_of(invoke!("programs.create", "values" => { "name" => "Office program" }))
    set = id_of(invoke!("equipment_sets.create", "values" => { "name" => "Kitchen" }))
    { P::SCHEDULE_KIND => schedule, P::PROGRAM_KIND => program, P::EQUIPMENT_SET_KIND => set }.each do |kind, id|
      engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
      record = engine.find(kind, id)
      store = engine.kind(kind).store
      assert_equal record, JSON.parse(JSON.generate(record)), "#{kind} is plain JSON"
      store.write(@model, record.merge("colour_of_the_day" => "red"))
      assert_equal "record.unreadable", refusal { engine.find(kind, id) }
      store.write(@model, record.merge("schema_version" => 2))
      assert_equal "record.unreadable", refusal { engine.find(kind, id) }
      store.write(@model, record)
    end
  end

  def test_every_frozen_default_is_a_valid_record_and_every_default_device_fits_its_type
    assert_empty P::Program::KIND.problems(P::DefaultProgram::PROGRAM)
    P::DefaultProgram::SCHEDULES.each { |record| assert_empty P::Schedule::KIND.problems(record), record["name"] }
    assert_empty P::EquipmentSet::KIND.problems(P::DefaultEquipmentSet::SET)
    assert_equal 8, P::DefaultEquipmentSet::DEVICES.length
    P::EquipmentTypes::NAMES.each do |type|
      assert_empty P::EquipmentTypes.problems(P::EquipmentTypes.device(type, "dev_AAAAAAAAAAAA")), type
    end
    assert_equal 14, P::EquipmentTypes::NAMES.length
  end

  # ---------------------------------------------------------------- Schedules

  def test_a_ventilation_schedule_whose_hours_do_not_total_24_refuses_and_writes_nothing
    periods = [["high", 2, 1.0], ["standard", 14, 0.77], ["basic", 6, 0.54], ["minimum", 1, 0.4]]
    revision = @session.revision
    outcome = invoke("schedules.create", "values" => { "type" => "ventilation", "periods" => rows(periods) })
    assert_equal "validation.failed", outcome["code"], outcome.inspect
    assert_equal revision, @session.revision
    periods[3][1] = 2
    id = id_of(invoke!("schedules.create", "values" => { "type" => "ventilation", "periods" => rows(periods) }))
    row = schedule_row(id)
    assert_equal [1.0, 1.0] + ([0.77] * 14) + ([0.54] * 6) + [0.4, 0.4], row.dig("profile", "hours")
    assert_in_delta 2 + (14 * 0.77) + (6 * 0.54) + 0.8, row.dig("profile", "daily_full_load_hours"), 1e-9
    reordered = rows(periods).rotate
    assert_equal "validation.failed", invoke("schedules.create", "values" => { "type" => "ventilation",
                                                                               "periods" => reordered })["code"]
  end

  def test_each_form_draws_its_profile_and_full_load_hours
    office = profile("type" => "fractional", "start_h" => 7, "end_h" => 18, "fraction_on" => 0.5,
                     "fraction_off" => 0.1, "days_per_week" => 5, "weeks_per_year" => 50)
    assert_equal ([0.1] * 7) + ([0.5] * 11) + ([0.1] * 6), office.fetch("hours")
    assert_in_delta (11 * 0.5) + (13 * 0.1), office.fetch("daily_full_load_hours"), 1e-9
    assert_in_delta 6.8 * 5 * 50, office.fetch("annual_full_load_hours"), 1e-9
    assert_equal %w[monday tuesday wednesday thursday friday], office.fetch("weekdays"), "Monday first, as exported"
    night = profile("type" => "fractional", "start_h" => 22, "end_h" => 6, "fraction_on" => 1.0,
                    "fraction_off" => 0.0)
    assert_equal ([1.0] * 6) + ([0.0] * 16) + ([1.0] * 2), night.fetch("hours"), "an end before the start wraps"
    assert_in_delta 8 * 7 * 52, night.fetch("annual_full_load_hours"), 1e-9
    activity = profile("type" => "activity", "start_h" => 0, "end_h" => 24, "watts_on" => 120.0, "watts_off" => 80.0)
    assert_equal [120.0] * 24, activity.fetch("hours")
    assert_nil activity.fetch("daily_full_load_hours"), "a level has no full-load hours"
    temperature = profile("type" => "temperature", "value_c" => 21.0, "days_per_week" => 5)
    assert_equal [[21.0] * 24, 7], [temperature.fetch("hours"), temperature.fetch("weekdays").size],
                 "a temperature Schedule applies every day"
    assert_equal "validation.failed", query_outcome("schedules.profile",
                                                    "values" => { "type" => "temperature", "start_h" => 1 })["code"]
  end

  def test_a_new_type_swaps_the_form_and_a_program_refuses_a_schedule_of_the_wrong_type
    id = id_of(invoke!("schedules.create", "values" => { "name" => "Setback" }))
    invoke!("schedules.update", "id" => id, "values" => { "type" => "temperature", "value_c" => 18.0 },
                                "expected_values" => { "type" => "fractional" })
    values = schedule_row(id).fetch("values")
    assert_equal [18.0, false], [values.fetch("value_c"), values.key?("start_h")]
    outcome = invoke("programs.create", "values" => { "name" => "Wrong", "lighting" => lighting("schedule_id" => id) })
    assert_equal "validation.failed", outcome["code"], outcome.inspect
  end

  def test_a_schedule_a_program_uses_keeps_its_type
    revision = @session.revision
    outcome = invoke("schedules.update", "id" => P::DefaultProgram::LIGHTS,
                                         "values" => { "type" => "temperature" }, "expected_values" => {})
    assert_equal "validation.failed", outcome["code"], outcome.inspect
    assert_equal revision, @session.revision
    assert_equal "validation.failed", invoke("schedules.update", "id" => P::DefaultProgram::LIGHTS,
                                                                 "values" => { "type" => nil },
                                                                 "expected_values" => {})["code"]
  end

  # ---------------------------------------------------------------- Programs

  def test_a_rule_load_keeps_its_inputs_across_a_switch_to_a_value_and_back
    id = id_of(invoke!("programs.duplicate", "id" => DEFAULT_PROGRAM, "name" => "House"))
    before = program_row(id).dig("values", "lighting")
    assert_equal ["phius_interior", 1.0], before.values_at("rule", "high_efficacy_fraction")
    ruled = before.merge("high_efficacy_fraction" => 0.8)
    invoke!("programs.update", "id" => id, "values" => { "lighting" => ruled }, "expected_values" => {})
    fixed = ruled.merge("rule" => nil, "watts_per_area" => 2.5)
    invoke!("programs.update", "id" => id, "values" => { "lighting" => fixed },
                               "expected_values" => { "lighting" => ruled })
    invoke!("programs.update", "id" => id, "values" => { "lighting" => fixed.merge("rule" => "phius_interior") },
                               "expected_values" => { "lighting" => fixed })
    after = program_row(id).dig("values", "lighting")
    assert_equal ["phius_interior", 0.8, 2.5], after.values_at("rule", "high_efficacy_fraction", "watts_per_area")
  end

  def test_a_new_program_takes_a_free_name_and_names_are_unique
    assert_equal "Program 1", program_row(id_of(invoke!("programs.create", {}))).dig("values", "name")
    assert_equal "Program 2", program_row(id_of(invoke!("programs.create", {}))).dig("values", "name")
    assert_equal "validation.failed", invoke("programs.create", "values" => { "name" => "program 1" })["code"]
    assert_equal "validation.failed", invoke("programs.create", "values" => { "name" => "Residential default" })["code"]
  end

  # ---------------------------------------------------------------- the residential default

  def test_a_fresh_model_reads_the_defaults_without_writing
    revision = @session.revision
    programs = query("programs.all").fetch("records")
    assert_equal [[DEFAULT_PROGRAM, false, true]], programs.map { |row| row.values_at("id", "stored", "default") }
    assert_equal 6, query("schedules.all").fetch("records").count { |row| row["stored"] == false }
    sets = query("equipment_sets.all").fetch("records")
    assert_equal [[DEFAULT_SET, false, true, 8]],
                 sets.map { |row| row.values_at("id", "stored", "default") + [row.dig("values", "devices").length] }
    assert_equal({ "default_program_id" => DEFAULT_PROGRAM, "default_equipment_set_id" => DEFAULT_SET },
                 query("settings.get"))
    assert_equal revision, @session.revision
    assert_empty P::Program::KIND.store.ids(@model)
    assert_nil P::Settings::SERVICE.store.read(@model)
  end

  def test_the_first_edit_writes_the_default_with_its_schedules_once_and_undo_returns_to_the_definition
    operations = @model.operations.length
    invoke!("programs.update", "id" => DEFAULT_PROGRAM, "values" => { "name" => "Our house" },
                               "expected_values" => { "name" => "Residential default" })
    assert_equal operations + 1, @model.operations.length
    assert_equal [DEFAULT_PROGRAM], P::Program::KIND.store.ids(@model)
    assert_equal P::DefaultProgram::SCHEDULES.map { |row| row["id"] }.sort, P::Schedule::KIND.store.ids(@model).sort
    stored = program_row(DEFAULT_PROGRAM)
    assert_equal ["Our house", true, "ph_composer_default"],
                 [stored.dig("values", "name"), stored["stored"], stored.dig("values", "source", "kind")]
    invoke!("programs.update", "id" => DEFAULT_PROGRAM, "values" => { "notes" => "Edited" }, "expected_values" => {})
    assert_equal 1, P::Program::KIND.store.ids(@model).length, "a second edit edits the stored record"
    @model.undo
    @model.undo
    assert_empty P::Schedule::KIND.store.ids(@model)
    restored = program_row(DEFAULT_PROGRAM)
    assert_equal ["Residential default", false], [restored.dig("values", "name"), restored.fetch("stored")]
  end

  def test_reset_restores_the_default_program_and_writes_back_a_missing_schedule
    edited = P::DefaultProgram::PROGRAM.fetch("infiltration").merge("flow_per_exterior_area" => 0.0009)
    invoke!("programs.update", "id" => DEFAULT_PROGRAM, "values" => { "infiltration" => edited },
                               "expected_values" => {})
    other = id_of(invoke!("schedules.create", "values" => { "name" => "Always" }))
    invoke!("schedules.delete", "id" => P::DefaultProgram::ALWAYS_ON, "replacement_id" => other)
    refute_includes P::Schedule::KIND.store.ids(@model), P::DefaultProgram::ALWAYS_ON
    operations = @model.operations.length
    invoke!("reset_default", "kind" => "program")
    assert_equal operations + 1, @model.operations.length
    values = program_row(DEFAULT_PROGRAM).fetch("values")
    assert_equal P::Program::KIND.values(P::DefaultProgram::PROGRAM), values
    assert_includes P::Schedule::KIND.store.ids(@model), P::DefaultProgram::ALWAYS_ON
  end

  def test_an_unwritten_default_schedule_deletes_with_a_replacement_from_its_own_bundle
    always_on = P::DefaultProgram::ALWAYS_ON
    occupancy = P::DefaultProgram::OCCUPANCY
    invoke!("schedules.delete", "id" => always_on, "replacement_id" => occupancy)
    stored = P::Schedule::KIND.store.ids(@model)
    assert_equal [false, true], [stored.include?(always_on), stored.include?(occupancy)]
    program = program_row(DEFAULT_PROGRAM).fetch("values")
    assert_equal [occupancy, occupancy], [program.dig("infiltration", "schedule_id"),
                                          program.dig("electric_equipment", "schedule_id")]
  end

  def test_reset_refuses_to_write_back_a_schedule_whose_name_another_took
    always_on = P::DefaultProgram::ALWAYS_ON
    invoke!("schedules.update", "id" => always_on, "values" => { "name" => "Old always on" }, "expected_values" => {})
    other = id_of(invoke!("schedules.create", "values" => { "name" => "Always on" }))
    invoke!("schedules.delete", "id" => always_on, "replacement_id" => other)
    revision = @session.revision
    assert_equal "validation.failed", invoke("reset_default", "kind" => "program")["code"]
    assert_equal revision, @session.revision
  end

  def test_reset_refuses_a_name_another_record_took_and_reports_a_dropped_devices_map
    invoke!("programs.update", "id" => DEFAULT_PROGRAM, "values" => { "name" => "Mine" }, "expected_values" => {})
    invoke!("programs.create", "values" => { "name" => "Residential default" })
    assert_equal "validation.failed", invoke("reset_default", "kind" => "program")["code"]
    added = invoke!("equipment_sets.add_device", "id" => DEFAULT_SET, "type" => "freezer")
    metadata!(P::EQUIPMENT_SET_KIND, DEFAULT_SET, [added.dig("value", "device_id")], { "tag" => "chest" })
    reset = invoke!("reset_default", "kind" => "equipment_set").fetch("value")
    assert_equal [{ "id" => DEFAULT_SET, "part_ids" => [added.dig("value", "device_id")], "user_data_keys" => ["tag"],
                    "user_data_key_total" => 1 }], reset.fetch("removed_user_data")
    assert_equal 8, set_row(DEFAULT_SET).dig("values", "devices").length
  end

  def test_the_default_refuses_delete_until_a_replacement_takes_over
    outcome = invoke("programs.delete", "id" => DEFAULT_PROGRAM)
    assert_equal "programs.default_in_use", outcome["code"], outcome.inspect
    office = id_of(invoke!("programs.create", "values" => { "name" => "Office" }))
    invoke!("programs.delete", "id" => DEFAULT_PROGRAM, "replacement_id" => office)
    assert_equal office, query("settings.get").fetch("default_program_id")
    assert_equal [office], query("programs.all").fetch("records").map { |row| row["id"] }
    assert_empty query("schedules.all").fetch("records"), "the unwritten default's Schedules go with it"
    assert_equal "programs.default_in_use", invoke("programs.delete", "id" => office)["code"]
    invoke!("reset_default", "kind" => "program")
    assert_equal [DEFAULT_PROGRAM, office].sort, P::Program::KIND.store.ids(@model).sort
  end

  def test_a_stored_default_moves_with_a_replacement_and_a_settings_change_keeps_the_residential_default
    office = id_of(invoke!("programs.create", "values" => { "name" => "Office" }))
    invoke!("settings.update", "values" => { "default_program_id" => office },
                               "expected_values" => { "default_program_id" => DEFAULT_PROGRAM })
    assert_includes P::Program::KIND.store.ids(@model), DEFAULT_PROGRAM, "the displaced default is stored"
    assert_equal({ "default_program_id" => office, "default_equipment_set_id" => nil }, P::Settings.stored(@model))
    stale = invoke("settings.update", "values" => { "default_equipment_set_id" => DEFAULT_SET },
                                      "expected_values" => { "default_equipment_set_id" => "eqs_Ab12Cd34Ef56" })
    assert_equal "target.changed", stale["code"]
    unchanged = invoke("settings.update", "values" => { "default_equipment_set_id" => DEFAULT_SET },
                                          "expected_values" => { "default_equipment_set_id" => DEFAULT_SET })
    assert_equal "none", unchanged["effect"], "naming the current default writes nothing"
    invoke!("programs.delete", "id" => office, "replacement_id" => DEFAULT_PROGRAM)
    assert_equal DEFAULT_PROGRAM, query("settings.get").fetch("default_program_id")
    assert_nil P::Settings.stored(@model).fetch("default_program_id"), "the reserved id is never stored"
    @model.undo
    assert_equal office, query("settings.get").fetch("default_program_id")
  end

  def test_the_default_equipment_set_writes_once_on_a_device_change_resets_and_refuses_delete
    first = query("equipment_sets.all").fetch("records").first.dig("values", "devices").first
    operations = @model.operations.length
    invoke!("equipment_sets.update_device", "id" => DEFAULT_SET, "device_id" => first["id"],
                                            "values" => { "quantity" => 2 }, "expected_values" => { "quantity" => 1 })
    assert_equal operations + 1, @model.operations.length
    assert_equal [DEFAULT_SET], P::EquipmentSet::KIND.store.ids(@model)
    assert_equal "programs.default_in_use", invoke("equipment_sets.delete", "id" => DEFAULT_SET)["code"]
    invoke!("reset_default", "kind" => "equipment_set")
    assert_equal P::DefaultEquipmentSet::DEVICES, set_row(DEFAULT_SET).dig("values", "devices")
  end

  # ---------------------------------------------------------------- devices

  def test_device_types_say_which_fields_apply_only_under_another_fields_values
    types = query("equipment_sets.device_types", {}).fetch("types")
    assert_equal 14, types.size
    conditional = types.flat_map do |type|
      type.fetch("fields").filter_map { |field| [type.fetch("type"), field.fetch("key")] if field["applies_when"] }
    end
    assert_equal [%w[clothes_dryer gas_consumption], %w[clothes_dryer gas_efficiency_factor]], conditional
    dryer = types.find { |type| type.fetch("type") == "clothes_dryer" }
    gas = dryer.fetch("fields").find { |field| field.fetch("key") == "gas_consumption" }
    assert_equal({ "dryer_type" => ["gas_exhaust_air"] }, gas.fetch("applies_when"))
    # The panel preview answers this read from the golden, so its device dialog lays out what Ruby declares.
    write_or_compare(File.expand_path("fixtures/programs/device_types.json", __dir__), types)
  end

  def test_device_add_edit_and_delete_are_each_one_undo_step_with_each_types_fields
    set = id_of(invoke!("equipment_sets.create", "values" => { "name" => "Laundry" }))
    operations = @model.operations.length
    added = invoke!("equipment_sets.add_device", "id" => set, "type" => "clothes_dryer",
                                                 "values" => { "dryer_type" => "heat_pump" })
    device_id = added.dig("value", "device_id")
    device = set_row(set).dig("values", "devices").first
    assert_equal ["clothes_dryer", "heat_pump", 3.93, false],
                 [device["type"], device["dryer_type"], device["combined_energy_factor"], device.key?("energy_demand")]
    rule = invoke("equipment_sets.add_device", "id" => set, "type" => "phius_mel",
                                               "values" => { "energy_demand" => 5.0 })
    assert_equal "validation.failed", rule["code"], "a Phius-rule device has no energy demand"
    code = invoke("equipment_sets.add_device", "id" => set, "type" => "refrigerator",
                                               "values" => { "reference_quantity" => 1 })
    assert_equal "validation.failed", code["code"], "a refrigerator allows reference quantity 4 or 5"
    invoke!("equipment_sets.update_device", "id" => set, "device_id" => device_id, "values" => { "quantity" => 2 },
                                            "expected_values" => { "quantity" => 1 })
    assert_equal "params.invalid", invoke("equipment_sets.update_device", "id" => set, "device_id" => device_id,
                                                                          "values" => { "type" => "dishwasher" },
                                                                          "expected_values" => {})["code"]
    stale = invoke("equipment_sets.update_device", "id" => set, "device_id" => device_id,
                                                   "values" => { "quantity" => 3 },
                                                   "expected_values" => { "quantity" => 1 })
    assert_equal "target.changed", stale["code"]
    invoke!("equipment_sets.delete_device", "id" => set, "device_id" => device_id)
    assert_equal operations + 3, @model.operations.length
    assert_empty set_row(set).dig("values", "devices")
    @model.undo
    assert_equal 2, set_row(set).dig("values", "devices").first["quantity"]
    @model.undo
    assert_equal 1, set_row(set).dig("values", "devices").first["quantity"]
  end

  def test_an_equipment_set_update_cannot_replace_its_devices
    set = id_of(invoke!("equipment_sets.create", "values" => { "name" => "Kitchen" }))
    device = invoke!("equipment_sets.add_device", "id" => set, "type" => "cooktop").dig("value", "device_id")
    swapped = P::EquipmentTypes.device("dishwasher", device)
    outcome = invoke("equipment_sets.update", "id" => set, "values" => { "devices" => [swapped] },
                                              "expected_values" => {})
    assert_equal "params.invalid", outcome["code"], outcome.inspect
    assert_equal "cooktop", set_row(set).dig("values", "devices", 0, "type")
  end

  # ---------------------------------------------------------------- deletes

  def test_a_used_schedule_refuses_delete_and_a_replacement_rewrites_every_use_in_one_undo_step
    occupancy = id_of(invoke!("schedules.create", "values" => { "name" => "Occupied" }))
    replacement = id_of(invoke!("schedules.create", "values" => { "name" => "Occupied, late" }))
    people = P::Program::EMPTY.fetch("people").merge("occupancy_schedule_id" => occupancy)
    first = id_of(invoke!("programs.create", "values" => { "name" => "A", "people" => people,
                                                           "lighting" => lighting("schedule_id" => occupancy) }))
    second = id_of(invoke!("programs.create", "values" => { "name" => "B", "people" => people }))
    assert_equal 3, schedule_row(occupancy).fetch("use_count")
    assert_equal "reference.in_use", invoke("schedules.delete", "id" => occupancy)["code"]
    temperature = id_of(invoke!("schedules.create", "values" => { "name" => "Warm", "type" => "temperature" }))
    assert_equal "validation.failed",
                 invoke("schedules.delete", "id" => occupancy, "replacement_id" => temperature)["code"]
    operations = @model.operations.length
    invoke!("schedules.delete", "id" => occupancy, "replacement_id" => replacement)
    assert_equal operations + 1, @model.operations.length
    assert_equal [replacement, replacement], [program_row(first).dig("values", "lighting", "schedule_id"),
                                              program_row(second).dig("values", "people", "occupancy_schedule_id")]
    @model.undo
    assert_equal occupancy, program_row(first).dig("values", "people", "occupancy_schedule_id")
  end

  def test_a_new_program_naming_a_default_schedule_writes_the_default_bundle
    invoke!("programs.create", "values" => { "name" => "Warehouse",
                                             "lighting" => lighting("schedule_id" => P::DefaultProgram::ALWAYS_ON) })
    assert_includes P::Program::KIND.store.ids(@model), DEFAULT_PROGRAM
    assert_includes P::Schedule::KIND.store.ids(@model), P::DefaultProgram::ALWAYS_ON
  end

  # ---------------------------------------------------------------- user_data

  def test_user_data_survives_edit_duplicate_undo_redo_and_reopen_on_each_kind_and_on_devices
    ids = {
      P::PROGRAM_KIND => id_of(invoke!("programs.create", "values" => { "name" => "Kept" },
                                                          "user_data" => { "firm" => { "k" => 1 } })),
      P::SCHEDULE_KIND => id_of(invoke!("schedules.create", "values" => { "name" => "Kept" },
                                                            "user_data" => { "firm" => { "k" => 1 } })),
      P::EQUIPMENT_SET_KIND => id_of(invoke!("equipment_sets.create", "values" => { "name" => "Kept" },
                                                                      "user_data" => { "firm" => { "k" => 1 } }))
    }
    set = ids.fetch(P::EQUIPMENT_SET_KIND)
    device_id = invoke!("equipment_sets.add_device", "id" => set, "type" => "cooktop").dig("value", "device_id")
    metadata!(P::EQUIPMENT_SET_KIND, set, [device_id], { "tag" => "range" })
    ids.each do |kind, id|
      collection = kind.split(".").last + "s"
      invoke!("#{collection}.update", "id" => id, "values" => { "notes" => "Edited" }, "expected_values" => {})
    end
    invoke!("equipment_sets.update_device", "id" => set, "device_id" => device_id,
                                            "values" => { "cooktop_type" => "natural_gas" }, "expected_values" => {})
    copies = ids.to_h do |kind, id|
      collection = kind.split(".").last + "s"
      [kind, id_of(invoke!("#{collection}.duplicate", "id" => id))]
    end
    @model.undo
    @model.redo
    path = File.join(Dir.tmpdir, "ph-composer-program-records.skp")
    @model.save(path)
    Sketchup.open_file(path)
    engine = PhComposer::Records::Engine.new(Sketchup.active_model, PhComposer::Registry.current.catalog)
    (ids.to_a + copies.to_a).each do |kind, id|
      assert_equal({ "firm" => { "k" => 1 } }, engine.find(kind, id)["user_data"], "#{kind} #{id}")
    end
    [set, copies.fetch(P::EQUIPMENT_SET_KIND)].each do |id|
      assert_equal({ "tag" => "range" }, engine.find(P::EQUIPMENT_SET_KIND, id).dig("devices", 0, "user_data"))
    end
    refute_equal device_id, engine.find(P::EQUIPMENT_SET_KIND, copies.fetch(P::EQUIPMENT_SET_KIND))
                                  .dig("devices", 0, "id"), "a copied device takes a new id"
  end

  # ---------------------------------------------------------------- helpers

  def rows(periods)
    periods.map { |period, hours, fraction| { "period" => period, "hours" => hours, "fraction" => fraction } }
  end

  # ---------------------------------------------------------------- the Programs tab's reads

  # The tab reads each collection from the snapshot, and a Program row names each value its ProgramType would lack,
  # by load and field, as the export preflight words it.
  def test_the_snapshot_carries_each_collection_and_a_program_row_names_its_missing_values
    sections = PhComposer::Snapshot.build(@context).fetch("sections")
    %w[programs schedules equipment_sets].each do |collection|
      assert_equal query("#{collection}.all"), sections.dig("#{PREFIX}.#{collection}", "value"), collection
    end
    refute sections.key?("#{PREFIX}.dwellings")
    assert_empty program_row(DEFAULT_PROGRAM).fetch("missing")

    empty = id_of(invoke!("programs.create", "values" => { "name" => "Lab" }))
    missing = program_row(empty).fetch("missing").map { |gap| gap.values_at("load", "field") }
    assert_equal [%w[people people_per_area], %w[lighting watts_per_area], %w[electric_equipment watts_per_area],
                  %w[gas_equipment watts_per_area], %w[service_hot_water flow_per_area],
                  %w[infiltration flow_per_exterior_area], %w[ventilation flow_per_person], %w[setpoint heating_c],
                  %w[setpoint cooling_c]], missing
  end

  def lighting(changes)
    P::Program::EMPTY.fetch("lighting").merge(changes)
  end

  def profile(values)
    query("schedules.profile", "values" => values)
  end

  def row(collection, id)
    query("#{collection}.all").fetch("records").find { |entry| entry["id"] == id } || flunk("no #{collection} #{id}")
  end

  def program_row(id)
    row("programs", id)
  end

  def schedule_row(id)
    row("schedules", id)
  end

  def set_row(id)
    row("equipment_sets", id)
  end

  def metadata!(kind, id, part_ids, map)
    @sequence += 1
    outcome = API.invoke(:context => @context, :name => "ph_composer.records.update_metadata",
                         :params => { "updates" => [{
                           "reference" => { "kind" => kind, "id" => id, "part_ids" => part_ids },
                           "user_data" => map, "expected_metadata" => { "user_data" => {}, "extension_data" => {} }
                         }] },
                         :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
    assert_equal "committed", outcome["effect"], outcome.inspect
  end

  def refusal
    yield
    nil
  rescue PhComposer::CodedError => error
    error.code
  end

  def id_of(outcome)
    outcome.dig("value", "id")
  end

  def query(name, params = {})
    outcome = query_outcome(name, params)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def query_outcome(name, params = {})
    API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
  end

  def invoke!(name, params)
    outcome = invoke(name, params)
    assert_equal "committed", outcome["effect"], "#{name}: #{outcome.inspect}"
    outcome
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{PREFIX}.#{name}", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
