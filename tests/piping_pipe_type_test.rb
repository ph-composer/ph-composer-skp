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
                              "insulation_reflective" => true, "insulation_quality" => 1), values(id)
    row = rows.fetch("PT-1")
    assert_equal [true, []], row.values_at("export_ready", "export_blockers")
    assert_includes P::PipeType::RAMP, row.dig("display", "color")
    assert_empty KIND.problems(JSON.parse(JSON.generate(KIND.store.read(@model, id))))
  end

  def test_each_nominal_diameter_and_material_is_stored_as_given
    P::PipeType::DIAMETERS_MM.keys.each_with_index do |diameter, index|
      material = index + 1
      id = create("name" => "D-#{index}", "diameter_mm" => diameter, "material" => material)
      assert_equal [diameter, material], values(id).values_at("diameter_mm", "material")
    end
    assert_equal ["3/8 in", "2 in"], P::PipeType::DIAMETERS_MM.values_at(9.525, 50.8)
    assert_equal 8, P::PipeType::MATERIALS.length
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
    assert_equal COMMON.merge("name" => "PT-1").merge(P::PipeType::DEFAULTS), values(id)
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
