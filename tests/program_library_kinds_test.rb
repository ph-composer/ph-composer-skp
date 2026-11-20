# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/library_provider_fixtures"

# The programs, schedules and equipment_sets library kinds: a library Program copies with the Schedules it names,
# a second copy reuses them, a Schedule missing from the library refuses the copy and writes nothing, each kind's
# wire mapping and fingerprint round trip, and copy plus the Model-default assignment is one Undo step.
class ProgramLibraryKindsTest < PhComposerTestCase
  include LibraryProviderFixtures

  API = PhComposer::API
  P = PhComposer::Programs
  L = "ph_composer.library"
  PROVIDER = "synthetic.programs"
  KINDS = %w[schedules programs equipment_sets].freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id, :capabilities => %w[read view model_write setup])
    @sequence = 0
    @directory = Dir.mktmpdir("program-libraries")
    @path = File.join(@directory, "programs.json")
    write_programs(rows)
    PhComposer::Library::Setup.add_file(:id => PROVIDER, :label => "Synthetic programs", :path => @path)
    @generations = {}
    KINDS.each { |kind| load_kind(kind) }
  end

  def teardown
    FileUtils.rm_rf(@directory)
    super
  end

  def rows
    { "schedules" => [
        { "id" => "office-hours", "name" => "Office hours", "type" => "fractional", "start_h" => 8, "end_h" => 18,
          "fraction_on" => 1, "fraction_off" => 0.1, "days_per_week" => 5 },
        { "id" => "office-air", "name" => "Office ventilation", "type" => "ventilation",
          "periods" => [{ "period" => "high", "hours" => 2, "fraction" => 1 },
                        { "period" => "standard", "hours" => 8, "fraction" => 0.77 },
                        { "period" => "basic", "hours" => 4, "fraction" => 0.5 },
                        { "period" => "minimum", "hours" => 10, "fraction" => 0.3 }] }
      ],
      "programs" => [
        { "id" => "office", "name" => "Office", "notes" => "Synthetic.",
          "people" => { "people_per_area" => 0.05, "occupancy_schedule_id" => "office-hours" },
          "lighting" => { "watts_per_area" => 7, "schedule_id" => "office-hours", "source" => "2019::Office" },
          "ventilation" => { "flow_per_person" => 0.0085, "schedule_id" => "office-air" } }
      ],
      "equipment_sets" => [
        { "id" => "kitchen", "name" => "Kitchen", "devices" => [
          { "type" => "dishwasher", "display_name" => "Dishwasher", "energy_demand" => 269 },
          { "type" => "cooktop", "cooktop_type" => "natural_gas" }
        ] }
      ] }
  end

  def write_programs(kinds)
    write_library(@path, envelope(:kinds => kinds).merge("kind_schema_versions" => KINDS.to_h { |kind| [kind, 1] }))
  end

  def load_kind(kind)
    loaded = API.setup(:context => @context, :name => "#{L}.load",
                       :params => { "provider_id" => PROVIDER, "kind" => kind })
    assert_equal "completed", loaded["status"], loaded.inspect
    @generations[kind] = loaded.dig("value", "generation")
    loaded.fetch("value")
  end

  def copy_params(kind, record_id, choice = "create")
    { "provider_id" => PROVIDER, "kind" => kind, "generation" => @generations.fetch(kind),
      "library_id" => "synthetic.one", "record_id" => record_id, "choice" => choice }
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => name, :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def stored(kind)
    P::Store::KINDS.fetch(kind).store.ids(@model).map { |id| P::Store::KINDS.fetch(kind).store.read(@model, id) }
  end

  def resolution(kind, record_id)
    query("#{L}.in_file", copy_params(kind, record_id).slice("provider_id", "kind", "generation"))
      .fetch("rows").find { |row| row.fetch("record_id") == record_id }.fetch("resolution")
  end

  def adapter(kind)
    PhComposer::Library::State.kind(kind, PhComposer::Registry.current).adapter
  end

  def test_a_program_copies_with_its_schedules_once_and_a_second_copy_reuses_them
    copied = invoke("#{L}.copy", copy_params("programs", "office"))
    assert_equal "committed", copied["effect"], copied.inspect
    dependencies = copied.dig("value", "dependencies")
    assert_equal [%w[schedules office-hours created], %w[schedules office-air created]],
                 dependencies.map { |row| row.values_at("kind", "record_id", "outcome") }
    schedules = stored(P::SCHEDULE_KIND).to_h { |record| [record.dig("source", "record_id"), record] }
    assert_equal %w[office-air office-hours], schedules.keys.sort
    hours = schedules.fetch("office-hours").fetch("id")
    program = stored(P::PROGRAM_KIND).find { |record| record.fetch("id") == copied.dig("value", "local_id") }
    assert_equal [hours, hours, schedules.fetch("office-air").fetch("id")],
                 [program.dig("people", "occupancy_schedule_id"), program.dig("lighting", "schedule_id"),
                  program.dig("ventilation", "schedule_id")]
    assert_equal "office-hours", program.dig("source", "snapshot", "people", "occupancy_schedule_id"),
                 "the attribution keeps the library row as it was"
    assert_equal "2019::Office", program.dig("lighting", "source")
    [P::PROGRAM_KIND, P::SCHEDULE_KIND].each do |kind|
      stored(kind).each { |record| assert_empty P::Store::KINDS.fetch(kind).problems(record), record.inspect }
    end
    assert_equal %w[reuse reuse reuse], [resolution("programs", "office"), resolution("schedules", "office-hours"),
                                         resolution("schedules", "office-air")].map { |row| row.fetch("outcome") }
    assert_equal [false], resolution("programs", "office").fetch("candidates").map { |row| row["source_changed"] }

    count = [stored(P::PROGRAM_KIND).length, stored(P::SCHEDULE_KIND).length]
    reused = invoke("#{L}.copy", copy_params("programs", "office", "keep_local"))
    assert_equal [program.fetch("id"), "none", []],
                 [reused.dig("value", "local_id"), reused["effect"], reused.dig("value", "dependencies")]
    assert_equal count, [stored(P::PROGRAM_KIND).length, stored(P::SCHEDULE_KIND).length]
  end

  def test_a_second_program_naming_copied_schedules_reuses_them_by_source
    invoke("#{L}.copy", copy_params("schedules", "office-hours"))
    copied = invoke("#{L}.copy", copy_params("programs", "office"))
    assert_equal [%w[office-hours reused], %w[office-air created]],
                 copied.dig("value", "dependencies").map { |row| row.values_at("record_id", "outcome") }
    assert_equal 2, stored(P::SCHEDULE_KIND).length
  end

  def test_a_schedule_missing_from_the_library_or_unloaded_refuses_and_writes_nothing
    write_programs(rows.merge("schedules" => rows.fetch("schedules").take(1)))
    load_kind("schedules")
    revision = @session.revision
    refused = invoke("#{L}.copy", copy_params("programs", "office"))
    assert_equal "library.dependency_missing", refused["code"], refused.inspect
    assert_equal({ "kind" => "schedules", "library_id" => "synthetic.one", "record_id" => "office-air",
                   "catalog_state" => "loaded" }, refused["detail"])
    assert_equal revision, @session.revision
    assert_empty stored(P::SCHEDULE_KIND) + stored(P::PROGRAM_KIND)
    PhComposer::Library::Setup.remove(PROVIDER)
    PhComposer::Library::Setup.add_file(:id => PROVIDER, :label => "Synthetic programs", :path => @path)
    load_kind("programs")
    unloaded = invoke("#{L}.copy", copy_params("programs", "office"))
    assert_equal ["library.dependency_missing", "unloaded"], [unloaded["code"], unloaded.dig("detail", "catalog_state")]
    assert_empty stored(P::SCHEDULE_KIND)
  end

  # The conflict is the second Schedule, so the first is staged before the copy refuses.
  def test_a_local_schedule_of_the_same_name_and_other_values_refuses_until_it_is_resolved
    local = invoke("ph_composer.programs.schedules.create", "values" => { "name" => "Office ventilation",
                                                                          "type" => "ventilation" })
    revision = @session.revision
    refused = invoke("#{L}.copy", copy_params("programs", "office"))
    assert_equal ["library.review_required", "office-air", "review_required"],
                 [refused["code"], refused.dig("detail", "id"), refused.dig("detail", "outcome")], refused.inspect
    assert_equal revision, @session.revision
    assert_equal [local.dig("value", "id")], stored(P::SCHEDULE_KIND).map { |record| record.fetch("id") }
    assert_empty stored(P::PROGRAM_KIND)
  end

  def test_a_schedule_of_the_wrong_type_for_its_load_refuses_the_copy
    program = rows.fetch("programs").first
    write_programs(rows.merge("programs" => [program.merge("lighting" => { "schedule_id" => "office-air" })]))
    load_kind("programs")
    refused = invoke("#{L}.copy", copy_params("programs", "office"))
    assert_equal ["validation.failed", "lighting.schedule_id"], [refused["code"], refused.dig("detail", "field")]
    assert_empty stored(P::SCHEDULE_KIND) + stored(P::PROGRAM_KIND)
  end

  def test_each_kind_maps_round_trips_and_fingerprints_canonically
    rows.each do |kind, wire|
      row = wire.first
      mapped = adapter(kind).map.call(row)
      assert_empty PhComposer::JsonSchema.validate(mapped, adapter(kind).mapped_schema), kind
      refute mapped.key?("id")
      assert_equal mapped, adapter(kind).map.call(adapter(kind).reverse.call(mapped.merge("id" => row.fetch("id"))))
    end
    schedule = rows.fetch("schedules").first
    assert_equal adapter("schedules").fingerprint.call(schedule),
                 adapter("schedules").fingerprint.call(schedule.merge("fraction_on" => 1.0, "notes" => ""))
    program = adapter("programs").map.call(rows.fetch("programs").first)
    assert_equal P::Program::EMPTY.fetch("setpoint"), program.fetch("setpoint"), "an absent load takes a new one's"
    assert_equal 0.3, program.dig("people", "radiant_fraction"), "an absent value takes a new load's"
    lighting = program.fetch("lighting").merge("schedule_id" => "other")
    refute_equal adapter("programs").fingerprint.call(program),
                 adapter("programs").fingerprint.call(program.merge("lighting" => lighting))
    devices = adapter("equipment_sets").map.call(rows.fetch("equipment_sets").first).fetch("devices")
    cooktop = P::EquipmentTypes.fetch("cooktop").fetch("defaults").fetch("energy_demand")
    assert_equal [["dishwasher", 269.0, nil], ["cooktop", cooktop, "natural_gas"]],
                 devices.map { |row| row.values_at("type", "energy_demand", "cooktop_type") },
                 "each device keeps its type and fields, the type's defaults filling the rest"
    assert_empty devices.flat_map { |row| P::EquipmentTypes.problems(row.merge("id" => "dev_000000000001")) }
    bad = rows.fetch("schedules").first.merge("type" => "temperature")
    assert_raises(PhComposer::CodedError) { adapter("schedules").map.call(bad) }
  end

  def test_an_equipment_set_copies_with_new_device_ids_and_a_replacement_keeps_matching_devices
    copied = invoke("#{L}.copy", copy_params("equipment_sets", "kitchen"))
    assert_equal "committed", copied["effect"], copied.inspect
    set = stored(P::EQUIPMENT_SET_KIND).first
    assert_equal %w[dishwasher cooktop], set.fetch("devices").map { |row| row.fetch("type") }
    assert(set.fetch("devices").all? { |row| row.fetch("id").match?(/\Adev_[A-Za-z0-9]{12}\z/) })
    assert_empty P::EquipmentSet::KIND.problems(set)
    dishwasher, cooktop = set.fetch("devices").map { |row| row.fetch("id") }
    edited = set.merge("devices" => set.fetch("devices").map do |row|
      row.fetch("id") == dishwasher ? row.merge("user_data" => { "firm.note" => "keep" }) : row
    end)
    P::EquipmentSet::KIND.store.write(@model, edited)
    changed = rows.fetch("equipment_sets").first
    changed = changed.merge("devices" => [changed.fetch("devices").first.merge("energy_demand" => 250)])
    write_programs(rows.merge("equipment_sets" => [changed]))
    load_kind("equipment_sets")
    candidate = resolution("equipment_sets", "kitchen").fetch("candidates").first
    replaced = invoke("#{L}.copy", copy_params("equipment_sets", "kitchen", "use_library")
      .merge("local_id" => set.fetch("id"), "expected_values" => candidate.fetch("expected_values")))
    assert_equal "committed", replaced["effect"], replaced.inspect
    after = stored(P::EQUIPMENT_SET_KIND).first
    assert_equal [[dishwasher, 250.0, { "firm.note" => "keep" }]],
                 after.fetch("devices").map { |row| row.values_at("id", "energy_demand", "user_data") }
    refute_includes after.fetch("devices").map { |row| row.fetch("id") }, cooktop
    write_programs(rows.merge("equipment_sets" => [changed.merge("devices" => [])]))
    load_kind("equipment_sets")
    candidate = resolution("equipment_sets", "kitchen").fetch("candidates").first
    refused = invoke("#{L}.copy", copy_params("equipment_sets", "kitchen", "use_library")
      .merge("local_id" => set.fetch("id"), "expected_values" => candidate.fetch("expected_values")))
    assert_equal ["validation.failed", dishwasher], [refused["code"], refused.dig("detail", "device_id")]
  end

  def test_copy_and_model_default_assignment_are_one_undo_step
    operations = @model.operations.length
    settings = query("ph_composer.programs.settings.get")
    copied = invoke("#{L}.copy", copy_params("programs", "office")
      .merge("assignment" => { "mode" => "model_default", "expected_settings" => settings }))
    assert_equal [true, "committed"], [copied.dig("value", "assigned"), copied["effect"]], copied.inspect
    assert_equal operations + 1, @model.operations.length
    assert_equal copied.dig("value", "local_id"), query("ph_composer.programs.settings.get").fetch("default_program_id")
    assert_equal [P::DefaultProgram::PROGRAM_ID], stored(P::PROGRAM_KIND).map { |row| row.fetch("id") } -
                                                  [copied.dig("value", "local_id")],
                 "the residential default is written before another becomes the default"
    @model.undo
    assert_empty stored(P::PROGRAM_KIND) + stored(P::SCHEDULE_KIND)
    assert_equal settings, query("ph_composer.programs.settings.get")
    @model.redo
    assert_equal copied.dig("value", "local_id"), query("ph_composer.programs.settings.get").fetch("default_program_id")
    stale = invoke("#{L}.copy", copy_params("equipment_sets", "kitchen")
      .merge("assignment" => { "mode" => "model_default", "expected_settings" => settings }))
    assert_equal "target.changed", stale["code"], stale.inspect
    assert_empty stored(P::EQUIPMENT_SET_KIND)
    set = invoke("#{L}.copy", copy_params("equipment_sets", "kitchen")
      .merge("assignment" => { "mode" => "model_default", "expected_settings" => {} }))
    assert_equal set.dig("value", "local_id"),
                 query("ph_composer.programs.settings.get").fetch("default_equipment_set_id")
  end

  def test_describe_names_the_dependency_and_the_assignment
    described = API.describe(:name => "#{P::FEATURE_ID}.library_programs")
    assert_equal [["schedules"], true],
                 [described.dig("dependencies", "kinds"), described.dig("assignment", "supported")]
    schedules = API.describe(:name => "#{P::FEATURE_ID}.library_schedules")
    assert_equal [[], false], [schedules.dig("dependencies", "kinds"), schedules.dig("assignment", "supported")]
  end

  # The published fixture reads with no warning but the Schedules' own: a row gives only its type's form.
  def test_the_published_programs_fixture_reads_each_kind
    PhComposer::Library::Setup.add_file(:id => "example.programs", :label => "Fixture",
                                        :path => File.expand_path("../tools/examples/library/programs.json", __dir__))
    counts = KINDS.to_h do |kind|
      loaded = API.setup(:context => @context, :name => "#{L}.load",
                         :params => { "provider_id" => "example.programs", "kind" => kind }).fetch("value")
      assert_empty loaded.fetch("unavailable"), kind
      [kind, [loaded.fetch("warnings").map { |row| row.fetch("code") }.uniq,
              query("#{L}.catalog", "provider_id" => "example.programs", "kind" => kind).fetch("total")]]
    end
    assert_equal({ "schedules" => [["library.row_optional_absent"], 2], "programs" => [[], 1],
                   "equipment_sets" => [[], 1] }, counts)
  end
end
