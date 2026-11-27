# frozen_string_literal: true

require_relative "test_helper"

# The Pipe Type catalog with the panel closed (context/CONTRACTS.md, "Hot water piping"): the kind and honeybee-ph's
# defaults, the eight nominal diameters, the range refusals, the guarded edit, Duplicate with its metadata, the delete,
# each one Undo step, and the type's export blocker. Every write goes through the public actions.
class PipingPipeTypeTest < PhComposerTestCase
  API = PhComposer::API
  P = PhComposer::Piping
  KIND = P::PipeType::KIND
  PREFIX = "ph_composer.piping.pipe_types"
  COMMON = { "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" } }.freeze
  # The shared categorical ramp, as each new type takes its next unused colour.
  RAMP = %w[#1F77B4 #FF7F0E #2CA02C #D62728].freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_a_type_created_with_a_tag_takes_honeybee_phs_pipe_segment_defaults
    id = create("name" => " PT-1 ")
    assert_match(/\Appt_[A-Za-z0-9]{12}\z/, id)
    assert_equal COMMON.merge("name" => "PT-1", "material" => 2, "diameter_mm" => 12.7,
                              "insulation_thickness_mm" => 12.7, "insulation_conductivity_w_mk" => 0.04,
                              "insulation_reflective" => true, "insulation_quality" => 1,
                              "assigned_color" => RAMP[0]), values(id)
    row = rows.fetch("PT-1")
    assert_equal [true, []], row.values_at("export_ready", "export_blockers")
    assert_equal RAMP[0], row.dig("display", "color")
    assert_empty KIND.problems(JSON.parse(JSON.generate(KIND.store.read(@model, id))))
  end

  # METr's eight nominal sizes, each the inch size in millimetres, and honeybee-ph's eight materials.
  NOMINAL = { 9.525 => "3/8 in", 12.7 => "1/2 in", 15.875 => "5/8 in", 19.05 => "3/4 in", 25.4 => "1 in",
              31.75 => "1 1/4 in", 38.1 => "1 1/2 in", 50.8 => "2 in" }.freeze
  MATERIALS = ["Copper M", "Copper L", "Copper K", "CPVC CTS SDR", "CPVC Sch 40", "PEX", "PE", "PEX CTS SDR"].freeze

  def test_each_nominal_diameter_and_material_is_stored_as_given
    NOMINAL.keys.each_with_index do |diameter, index|
      material = index + 1
      id = create("name" => "D-#{index}", "diameter_mm" => diameter, "material" => material)
      assert_equal [diameter, material], values(id).values_at("diameter_mm", "material")
    end
    assert_equal NOMINAL, P::PipeType::DIAMETERS_MM
    assert_equal MATERIALS, P::PipeType::MATERIALS.values_at(*1..8)
  end

  def test_a_value_out_of_range_or_off_the_nominal_list_refuses_and_writes_nothing
    id = create("name" => "PT-1")
    [{ "material" => 0 }, { "material" => 9 }, { "diameter_mm" => 22.0 }, { "diameter_mm" => 12.7001 },
     { "diameter_mm" => 0.375 * 25.4 },
     { "insulation_thickness_mm" => -1.0 }, { "insulation_conductivity_w_mk" => 0.0 },
     { "insulation_conductivity_w_mk" => -0.04 }, { "insulation_quality" => 0 }, { "insulation_quality" => 4 },
     { "insulation_reflective" => "yes" }, { "color" => "blue" }].each do |bad|
      assert_equal %w[refused params.invalid none],
                   invoke("create", "values" => { "name" => "PT-X" }.merge(bad)).values_at("status", "code", "effect"),
                   bad.inspect
      assert_equal %w[refused params.invalid none],
                   invoke("update", "id" => id, "values" => bad, "expected_values" => {})
                     .values_at("status", "code", "effect"), bad.inspect
    end
    assert_equal %w[refused validation.failed],
                 invoke("create", "values" => { "name" => "pt-1" }).values_at("status", "code"),
                 "a taken Tag, in any case"
    other = create("name" => "PT-2")
    assert_equal %w[refused validation.failed none],
                 invoke("update", "id" => other, "values" => { "name" => " PT-1" }, "expected_values" => {})
                   .values_at("status", "code", "effect"), "a rename onto a taken Tag"
    completed(invoke("delete", "id" => other))
    assert_equal ["PT-1"], rows.keys
    assert_equal COMMON.merge("name" => "PT-1", "assigned_color" => RAMP[0]).merge(P::PipeType::DEFAULTS), values(id)
  end

  # Each new type, and each copy, takes the ramp's next unused colour; a colour set and then cleared returns the type
  # to the one it took.
  def test_each_new_type_takes_the_next_unused_colour_and_a_cleared_colour_returns_to_it
    first, = %w[PT-1 PT-2].map { |name| create("name" => name) }
    assert_equal RAMP.first(2), rows.values_at("PT-1", "PT-2").map { |row| row.dig("display", "color") }
    reassigned = invoke("update", "id" => first, "values" => { "assigned_color" => "#123456" }, "expected_values" => {})
    assert_equal %w[refused params.invalid], reassigned.values_at("status", "code"), "the assigned colour is no edit"
    named = invoke("create", "values" => { "name" => "PT-9", "assigned_color" => RAMP[0] })
    assert_equal %w[refused params.invalid], named.values_at("status", "code"), "nor a create input"
    completed(invoke("update", "id" => first, "values" => { "color" => "#123456" }, "expected_values" => {}))
    assert_equal "#123456", rows.fetch("PT-1").dig("display", "color")
    copy = completed(invoke("duplicate", "id" => first)).fetch("id")
    assert_equal ["#123456", RAMP[2]], values(copy).values_at("color", "assigned_color"),
                 "a copy keeps the colour it was given and takes the next unused one as its own"
    completed(invoke("update", "id" => first, "values" => { "color" => nil }, "expected_values" => {}))
    assert_equal [RAMP[0], RAMP[3]], [rows.fetch("PT-1").dig("display", "color"),
                                      values(create("name" => "PT-3")).fetch("assigned_color")]
  end

  # Past the ramp's ten colours, new types keep cycling through it rather than repeating its first.
  def test_types_past_the_ramp_keep_cycling_its_colours
    ids = (1..12).map { |number| create("name" => "PT-#{number}") }
    colours = ids.map { |id| values(id).fetch("assigned_color") }
    assert_equal [10, colours.first(2)], [colours.first(10).uniq.length, colours.last(2)]
  end

  def test_insulation_with_no_conductivity_blocks_the_type_and_a_bare_pipe_needs_none
    blocked = create("name" => "Unknown", "insulation_conductivity_w_mk" => nil)
    refute values(blocked).key?("insulation_conductivity_w_mk"), "a null on create leaves it absent"
    assert_equal [false, ["piping.insulation_conductivity_missing"]],
                 rows.fetch("Unknown").values_at("export_ready", "export_blockers")
    bare = create("name" => "Bare", "insulation_thickness_mm" => 0.0, "insulation_conductivity_w_mk" => nil)
    assert_equal [true, []], rows.fetch("Bare").values_at("export_ready", "export_blockers")

    edited = create("name" => "Edited")
    completed(invoke("update", "id" => edited, "values" => { "insulation_conductivity_w_mk" => nil },
                               "expected_values" => { "insulation_conductivity_w_mk" => 0.04 }))
    refute values(edited).key?("insulation_conductivity_w_mk"), "null removes the conductivity"
    assert_equal ["piping.insulation_conductivity_missing"], rows.fetch("Edited").fetch("export_blockers")
    completed(invoke("update", "id" => blocked, "values" => { "insulation_thickness_mm" => 0.0 },
                               "expected_values" => { "insulation_thickness_mm" => 12.7 }))
    assert_equal [], rows.fetch("Unknown").fetch("export_blockers"), "thickness 0 clears the blocker"
    assert values(bare).fetch("insulation_conductivity_w_mk", nil).nil?
  end

  def test_a_guarded_edit_is_one_undo_step_and_a_stale_one_writes_nothing
    operations = @model.operations.length
    id = create("name" => "PT-1")
    assert_equal operations + 1, @model.operations.length
    @model.undo
    assert_empty rows, "Undo takes the create back"
    @model.redo
    assert_equal ["PT-1"], rows.keys
    operations = @model.operations.length
    completed(invoke("update", "id" => id, "values" => { "material" => 6, "diameter_mm" => 19.05 },
                               "expected_values" => { "material" => 2 }))
    assert_equal operations + 1, @model.operations.length
    assert_equal [6, 19.05], values(id).values_at("material", "diameter_mm")
    assert_equal %w[refused target.changed none],
                 invoke("update", "id" => id, "values" => { "material" => 7 }, "expected_values" => { "material" => 2 })
                   .values_at("status", "code", "effect")
    assert_equal 6, values(id).fetch("material"), "a stale edit writes nothing"
    @model.undo
    assert_equal [2, 12.7], values(id).values_at("material", "diameter_mm")
    @model.redo
    assert_equal 6, values(id).fetch("material")
  end

  def test_duplicate_keeps_the_values_and_user_data_under_a_new_id
    id = create({ "name" => "PT-1", "material" => 6, "insulation_quality" => 3 }, { "firm" => { "tag" => "a" } })
    copy = completed(invoke("duplicate", "id" => id)).fetch("id")
    copied = rows.fetch("PT-1 (copy)")
    assert_equal copy, copied.fetch("id")
    refute_equal id, copy
    assert_equal [6, 3, { "kind" => "derived" }],
                 copied.fetch("values").values_at("material", "insulation_quality", "source")
    assert_equal({ "firm" => { "tag" => "a" } }, copied.fetch("user_data"))
  end

  def test_the_bounded_list_pages_filters_and_projects_and_the_snapshot_section_is_the_all_read
    first = create("name" => "PT-1")
    second = create("name" => "PT-2", "insulation_conductivity_w_mk" => nil)
    assert_equal query("all"), PhComposer::Snapshot.build(@context).fetch("sections").dig(PREFIX, "value")
    page = query("list", "limit" => 1, "fields" => ["export_ready"])
    rest = query("list", "limit" => 1, "fields" => ["export_ready"], "cursor" => page.fetch("next_cursor"))
    rows = (page.fetch("records") + rest.fetch("records")).to_h { |row| [row.fetch("id"), row] }
    assert_equal [first, second].sort, rows.keys.sort
    assert_equal [[KIND.id, 1, true], [KIND.id, 1, false]],
                 [first, second].map { |id| rows.fetch(id).values_at("kind", "schema_version", "export_ready") }
    refute rows.fetch(first).key?("values"), "fields leaves the values out"
    assert_equal [second], query("list", "ids" => [second]).fetch("records").map { |row| row.fetch("id") }
    assert_empty query("list", "ids" => ["ppt_AAAAAAAAAAAA"]).fetch("records"), "a well-formed absent id"
    wrong = API.query(:context => @context, :name => "#{PREFIX}.list", :params => { "ids" => ["fan_AAAAAAAAAAAA"] })
    assert_equal %w[refused params.invalid], wrong.values_at("status", "code"), "another kind's id"
  end

  def test_user_data_is_written_through_the_guarded_core_route
    id = create("name" => "PT-1")
    row = rows.fetch("PT-1")
    update = { "reference" => { "kind" => KIND.id, "id" => id }, "user_data" => { "firm" => { "riser" => 3 } },
               "expected_metadata" => row.slice("user_data", "extension_data") }
    completed(invoke("ph_composer.records.update_metadata", { "updates" => [update] }, nil))
    assert_equal({ "firm" => { "riser" => 3 } }, rows.fetch("PT-1").fetch("user_data"))
    stale = invoke("ph_composer.records.update_metadata", { "updates" => [update] }, nil)
    assert_equal %w[refused target.changed], stale.values_at("status", "code")
  end

  def test_delete_removes_the_type_and_undo_restores_it
    id = create({ "name" => "PT-1" }, { "firm" => { "tag" => "a" } })
    spare = create("name" => "PT-2")
    assert_equal %w[refused params.invalid none],
                 invoke("delete", "id" => id, "replacement_id" => id).values_at("status", "code", "effect"),
                 "a type cannot replace itself"
    assert_equal %w[refused target.not_found none],
                 invoke("delete", "id" => id, "replacement_id" => "ppt_ZZZZZZZZZZZZ")
                   .values_at("status", "code", "effect"),
                 "a replacement must exist"
    operations = @model.operations.length
    deleted = completed(invoke("delete", "id" => id))
    assert_equal operations + 1, @model.operations.length
    assert_equal ["PT-2"], rows.keys
    assert_equal [{ "id" => id, "user_data_keys" => ["firm"], "user_data_key_total" => 1 }],
                 deleted.fetch("removed_user_data")
    @model.undo
    assert_equal({ "firm" => { "tag" => "a" } }, rows.fetch("PT-1").fetch("user_data"), "Undo restores it")
    @model.redo
    completed(invoke("delete", "id" => spare, "replacement_id" => nil))
    assert_empty rows
    @model.undo
    @model.undo
    completed(invoke("delete", "id" => id, "replacement_id" => spare))
    assert_equal ["PT-2"], rows.keys, "an existing replacement is accepted while no pipe uses the type"
  end

  private

  def create(values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    completed(invoke("create", params)).fetch("id")
  end

  def values(id)
    query("all").fetch("records").find { |row| row.fetch("id") == id }.fetch("values")
  end

  def rows
    query("all").fetch("records").to_h { |row| [row.dig("values", "name"), row] }
  end

  def query(name, params = {})
    completed(API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params))
  end

  def completed(outcome)
    assert_includes %w[completed], outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def invoke(name, params, prefix = PREFIX)
    API.invoke(:context => @context, :name => prefix ? "#{prefix}.#{name}" : name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
