# frozen_string_literal: true

require_relative "test_helper"

# The Duct Type catalog with the panel closed (context/CONTRACTS.md, "ERV ducting"): the kind and honeybee-ph's
# defaults, each shape's dimensions, the refusals, the shape change, the guarded edit, Duplicate with its metadata,
# the delete, each one Undo step, and the type's export blocker. Every write goes through the public actions.
class DuctingDuctTypeTest < PhComposerTestCase
  API = PhComposer::API
  D = PhComposer::Ducting
  KIND = D::DuctType::KIND
  PREFIX = "ph_composer.ducting.duct_types"
  COMMON = { "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" } }.freeze
  # honeybee-ph's PhDuctSegment defaults (1.33.68), in millimetres: a 0.160 m round duct with 0.0254 m of reflective
  # insulation at 0.04 W/(m K).
  ROUND = { "shape" => "round", "diameter_mm" => 160.0, "insulation_thickness_mm" => 25.4,
            "insulation_conductivity_w_mk" => 0.04, "insulation_reflective" => true }.freeze
  RECTANGULAR = { "shape" => "rectangular", "width_mm" => 200.0, "height_mm" => 100.0 }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_a_type_created_with_a_tag_is_round_with_honeybee_phs_duct_segment_defaults
    id = create("name" => " DT-1 ")
    assert_match(/\Adct_[A-Za-z0-9]{12}\z/, id)
    assert_equal COMMON.merge("name" => "DT-1").merge(ROUND), values(id)
    row = rows.fetch("DT-1")
    assert_equal [true, []], row.values_at("export_ready", "export_blockers")
    ramp = %w[#4a7fb5 #b5634a #5f9a5a #8d6bb0 #c29a3a #4a9a9a]
    assert_equal ramp.fetch(id.each_byte.sum % 6), row.dig("display", "color"), "the ramp's colour for the id"
    assert_empty KIND.problems(JSON.parse(JSON.generate(KIND.store.read(@model, id))))
  end

  def test_a_rectangular_type_holds_width_and_height_and_no_diameter
    id = create(RECTANGULAR.merge("name" => "DT-2", "diameter_mm" => nil))
    assert_equal COMMON.merge("name" => "DT-2", "insulation_thickness_mm" => 25.4,
                              "insulation_conductivity_w_mk" => 0.04, "insulation_reflective" => true)
                       .merge(RECTANGULAR), values(id)
    refute values(id).key?("diameter_mm"), "a null for the other shape's dimension leaves it absent"
  end

  def test_a_missing_other_shape_or_out_of_range_value_refuses_and_writes_nothing
    round = create("name" => "DT-1")
    rectangular = create(RECTANGULAR.merge("name" => "DT-2"))
    revision = @session.revision
    operations = @model.operations.length
    [{ "shape" => "rectangular" }, { "shape" => "rectangular", "width_mm" => 200.0 },
     { "shape" => "rectangular", "height_mm" => 100.0 }, RECTANGULAR.merge("diameter_mm" => 160.0),
     { "width_mm" => 200.0 }, { "diameter_mm" => nil }, { "shape" => "oval" }, { "diameter_mm" => 0.0 },
     { "diameter_mm" => -160.0 }, RECTANGULAR.merge("height_mm" => 0.0), { "insulation_thickness_mm" => -1.0 },
     { "insulation_conductivity_w_mk" => 0.0 }, { "insulation_conductivity_w_mk" => -0.04 },
     { "insulation_reflective" => "yes" }, { "color" => "blue" }].each do |bad|
      assert_equal %w[refused params.invalid none],
                   invoke("create", "values" => { "name" => "DT-X" }.merge(bad)).values_at("status", "code", "effect"),
                   bad.inspect
    end
    # Each edit is checked on the values it would write: the stored shape with the new values.
    [[round, { "width_mm" => 200.0 }], [round, { "diameter_mm" => nil }], [round, { "diameter_mm" => 0.0 }],
     [round, { "shape" => "rectangular", "width_mm" => 200.0 }],
     [round, RECTANGULAR.merge("diameter_mm" => 160.0)], [rectangular, { "diameter_mm" => 160.0 }],
     [rectangular, { "height_mm" => nil }], [rectangular, { "shape" => "round" }],
     [rectangular, { "insulation_conductivity_w_mk" => 0.0 }]].each do |id, bad|
      assert_equal %w[refused params.invalid none],
                   invoke("update", "id" => id, "values" => bad, "expected_values" => {})
                     .values_at("status", "code", "effect"), bad.inspect
    end
    assert_equal [revision, operations], [@session.revision, @model.operations.length]
    assert_equal %w[DT-1 DT-2], rows.keys.sort
    assert_equal COMMON.merge("name" => "DT-1").merge(ROUND), values(round)
    assert_equal ["A rectangular Duct Type needs height_mm.", "A rectangular Duct Type takes no diameter_mm."],
                 D::DuctType.shape_problems("shape" => "rectangular", "width_mm" => 1.0, "diameter_mm" => 1.0)
    assert_equal %w[refused validation.failed],
                 invoke("create", "values" => { "name" => "dt-1" }).values_at("status", "code"),
                 "a taken Tag, in any case"
    assert_equal %w[refused validation.failed none],
                 invoke("update", "id" => rectangular, "values" => { "name" => " DT-1" }, "expected_values" => {})
                   .values_at("status", "code", "effect"), "a rename onto a taken Tag"
  end

  def test_a_shape_change_drops_the_old_dimensions_in_one_undo_step
    id = create("name" => "DT-1")
    operations = @model.operations.length
    completed(invoke("update", "id" => id, "values" => RECTANGULAR, "expected_values" => { "shape" => "round" }))
    assert_equal operations + 1, @model.operations.length
    stored = values(id)
    assert_equal RECTANGULAR, stored.slice("shape", "width_mm", "height_mm")
    refute stored.key?("diameter_mm"), "the round dimension goes with the shape"
    @model.undo
    assert_equal COMMON.merge("name" => "DT-1").merge(ROUND), values(id)
    @model.redo
    # A null for the other shape's dimension removes it, as a null removes any optional value.
    round = { "shape" => "round", "diameter_mm" => 125.0, "width_mm" => nil }
    completed(invoke("update", "id" => id, "values" => round, "expected_values" => { "shape" => "rectangular" }))
    assert_equal({ "shape" => "round", "diameter_mm" => 125.0 },
                 values(id).slice("shape", "diameter_mm", "width_mm", "height_mm"))
  end

  # A stale edit refuses as target.changed, before the shape of its new values is checked.
  def test_a_guarded_edit_is_one_undo_step_and_a_stale_one_writes_nothing
    operations = @model.operations.length
    id = create("name" => "DT-1")
    assert_equal operations + 1, @model.operations.length
    @model.undo
    assert_empty rows, "Undo takes the create back"
    @model.redo
    assert_equal ["DT-1"], rows.keys
    operations = @model.operations.length
    completed(invoke("update", "id" => id, "values" => { "diameter_mm" => 200.0, "insulation_reflective" => false },
                               "expected_values" => { "diameter_mm" => 160.0 }))
    assert_equal operations + 1, @model.operations.length
    assert_equal [200.0, false], values(id).values_at("diameter_mm", "insulation_reflective")
    assert_equal %w[refused target.changed none],
                 invoke("update", "id" => id, "values" => { "diameter_mm" => 250.0 },
                                  "expected_values" => { "diameter_mm" => 160.0 }).values_at("status", "code", "effect")
    assert_equal %w[refused target.changed none],
                 invoke("update", "id" => id, "values" => { "shape" => "rectangular" },
                                  "expected_values" => { "shape" => "rectangular" })
                   .values_at("status", "code", "effect"), "stale, and its new values short of a dimension"
    assert_equal 200.0, values(id).fetch("diameter_mm"), "a stale edit writes nothing"
    @model.undo
    assert_equal [160.0, true], values(id).values_at("diameter_mm", "insulation_reflective")
    @model.redo
    assert_equal 200.0, values(id).fetch("diameter_mm")
  end

  def test_insulation_with_no_conductivity_blocks_the_type_and_a_bare_duct_needs_none
    blocked = create("name" => "Unknown", "insulation_conductivity_w_mk" => nil)
    refute values(blocked).key?("insulation_conductivity_w_mk"), "a null on create leaves it absent"
    assert_equal [false, ["ducting.insulation_conductivity_missing"]],
                 rows.fetch("Unknown").values_at("export_ready", "export_blockers")
    create("name" => "Bare", "insulation_thickness_mm" => 0.0, "insulation_conductivity_w_mk" => nil)
    assert_equal [true, []], rows.fetch("Bare").values_at("export_ready", "export_blockers")
    edited = create("name" => "Edited")
    completed(invoke("update", "id" => edited, "values" => { "insulation_conductivity_w_mk" => nil },
                               "expected_values" => { "insulation_conductivity_w_mk" => 0.04 }))
    assert_equal ["ducting.insulation_conductivity_missing"], rows.fetch("Edited").fetch("export_blockers")
    completed(invoke("update", "id" => blocked, "values" => { "insulation_thickness_mm" => 0.0 },
                               "expected_values" => { "insulation_thickness_mm" => 25.4 }))
    assert_equal [], rows.fetch("Unknown").fetch("export_blockers"), "thickness 0 clears the blocker"
  end

  def test_duplicate_keeps_the_values_and_user_data_under_a_new_id
    id = create(RECTANGULAR.merge("name" => "DT-2", "insulation_reflective" => false), { "firm" => { "tag" => "a" } })
    copy = completed(invoke("duplicate", "id" => id)).fetch("id")
    copied = rows.fetch("DT-2 (copy)")
    assert_equal copy, copied.fetch("id")
    refute_equal id, copy
    assert_equal ["rectangular", 200.0, 100.0, false, { "kind" => "derived" }],
                 copied.fetch("values").values_at("shape", "width_mm", "height_mm", "insulation_reflective", "source")
    assert_equal({ "firm" => { "tag" => "a" } }, copied.fetch("user_data"))
  end

  def test_the_bounded_list_pages_filters_and_projects_and_the_snapshot_section_is_the_all_read
    first = create("name" => "DT-1")
    second = create("name" => "DT-2", "insulation_conductivity_w_mk" => nil)
    assert_equal query("all"), PhComposer::Snapshot.build(@context).fetch("sections").dig(PREFIX, "value")
    page = query("list", "limit" => 1, "fields" => ["export_ready"])
    rest = query("list", "limit" => 1, "fields" => ["export_ready"], "cursor" => page.fetch("next_cursor"))
    rows = (page.fetch("records") + rest.fetch("records")).to_h { |row| [row.fetch("id"), row] }
    assert_equal [first, second].sort, rows.keys.sort
    assert_equal [[KIND.id, 1, true], [KIND.id, 1, false]],
                 [first, second].map { |id| rows.fetch(id).values_at("kind", "schema_version", "export_ready") }
    refute rows.fetch(first).key?("values"), "fields leaves the values out"
    assert_equal [second], query("list", "ids" => [second]).fetch("records").map { |row| row.fetch("id") }
    assert_empty query("list", "ids" => ["dct_AAAAAAAAAAAA"]).fetch("records"), "a well-formed absent id"
    wrong = API.query(:context => @context, :name => "#{PREFIX}.list", :params => { "ids" => ["ppt_AAAAAAAAAAAA"] })
    assert_equal %w[refused params.invalid], wrong.values_at("status", "code"), "another kind's id"
  end

  def test_user_data_is_written_through_the_guarded_core_route
    id = create("name" => "DT-1")
    row = rows.fetch("DT-1")
    update = { "reference" => { "kind" => KIND.id, "id" => id }, "user_data" => { "firm" => { "run" => 2 } },
               "expected_metadata" => row.slice("user_data", "extension_data") }
    completed(invoke("ph_composer.records.update_metadata", { "updates" => [update] }, nil))
    assert_equal({ "firm" => { "run" => 2 } }, rows.fetch("DT-1").fetch("user_data"))
    stale = invoke("ph_composer.records.update_metadata", { "updates" => [update] }, nil)
    assert_equal %w[refused target.changed], stale.values_at("status", "code")
  end

  def test_delete_removes_the_type_and_undo_restores_it
    id = create({ "name" => "DT-1" }, { "firm" => { "tag" => "a" } })
    spare = create("name" => "DT-2")
    assert_equal %w[refused params.invalid none],
                 invoke("delete", "id" => id, "replacement_id" => id).values_at("status", "code", "effect"),
                 "a type cannot replace itself"
    assert_equal %w[refused target.not_found none],
                 invoke("delete", "id" => id, "replacement_id" => "dct_ZZZZZZZZZZZZ")
                   .values_at("status", "code", "effect"),
                 "a replacement must exist"
    operations = @model.operations.length
    deleted = completed(invoke("delete", "id" => id))
    assert_equal operations + 1, @model.operations.length
    assert_equal ["DT-2"], rows.keys
    assert_equal [{ "id" => id, "user_data_keys" => ["firm"], "user_data_key_total" => 1 }],
                 deleted.fetch("removed_user_data")
    @model.undo
    assert_equal({ "firm" => { "tag" => "a" } }, rows.fetch("DT-1").fetch("user_data"), "Undo restores it")
    @model.redo
    completed(invoke("delete", "id" => spare, "replacement_id" => nil))
    assert_empty rows
    @model.undo
    @model.undo
    completed(invoke("delete", "id" => id, "replacement_id" => spare))
    assert_equal ["DT-2"], rows.keys, "an existing replacement is accepted while no duct uses the type"
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
