# frozen_string_literal: true

require_relative "test_helper"

# The duct assignment through its registered actions and selection read (context/CONTRACTS.md, "ERV ducting"): every
# write names explicit Edges directly in a Ducting group, carries a Duct Type, a direction and a quantity, refuses as
# a whole and is one native Undo step; a Duct Type delete moves, nulls or refuses the ducts naming it.
class DuctingAssignmentTest < PhComposerTestCase
  API = PhComposer::API
  D = PhComposer::Ducting
  STORE = D::Assignment::STORE
  PREFIX = "ph_composer.ducting"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @erv = invoke("ph_composer.mechanical.ventilators.create", "values" => { "name" => "ERV-1" }).dig("value", "id")
    @dt1 = invoke("#{PREFIX}.duct_types.create", "values" => { "name" => "DT-1" }).dig("value", "id")
    @dt2 = invoke("#{PREFIX}.duct_types.create", "values" => { "name" => "DT-2", "diameter_mm" => 200.0 })
           .dig("value", "id")
    fixture
  end

  # Ducting group 600 at the root holds Edges 601 to 603, a Face 609 and a plain Group 610 holding Edge 611. Locked
  # wrapper 620 holds Ducting group 621 with Edge 622. Plain Group 630 at the root holds Edge 631.
  def fixture
    @edges = [601, 602, 603].map { |id| edge(id) }
    @group = ducting_group(600, "dcg_AAAAAAAAAAAA", @edges + [Sketchup::Face.new(609),
                                                              Sketchup::Group.new(610,
                                                                                  Sketchup::Entities.new([edge(611)]))])
    locked = Sketchup::Group.new(620, Sketchup::Entities.new([ducting_group(621, "dcg_BBBBBBBBBBBB", [edge(622)])]),
                                 :locked => true)
    @model.entities << @group << locked << Sketchup::Group.new(630, Sketchup::Entities.new([edge(631)]))
  end

  def test_assign_writes_outdoor_air_in_one_undo_step_and_a_reassign_keeps_what_it_is_not_given
    two = @edges.first(2).map { |entity| target(entity) }
    first = assign(two, "duct_type_id" => @dt1, "direction" => "outdoor_air")
    assert_equal "committed", first["effect"], first.inspect
    ids = first.dig("value", "edge_ids")
    assert(ids.uniq.length == 2 && ids.all? { |id| id.match?(/\Adce_[A-Za-z0-9]{12}\z/) })
    outdoor = { "duct_type_id" => @dt1, "direction" => "outdoor_air", "quantity" => 1 }
    assert_equal [outdoor] * 2, @edges.first(2).map { |entity| D::Assignment.values(STORE.read(entity)) }

    second = assign([target(@edges.first)], "quantity" => 2)
    assert_equal "committed", second["effect"], second.inspect
    assert_equal outdoor.merge("quantity" => 2), D::Assignment.values(STORE.read(@edges.first))
    assign([target(@edges.first)], "duct_type_id" => @dt2)
    assert_equal outdoor.merge("duct_type_id" => @dt2, "quantity" => 2), D::Assignment.values(STORE.read(@edges.first))
    assert_equal ids.first, STORE.read(@edges.first).fetch("id")
    @model.undo
    @model.undo
    assert_equal outdoor, D::Assignment.values(STORE.read(live(600, 601)))
    @model.undo
    assert_equal [nil, nil], [STORE.read(live(600, 601)), STORE.read(live(600, 602))]
  end

  def test_a_missing_or_unknown_direction_a_missing_type_or_a_bad_quantity_refuses_params_invalid
    [{ "duct_type_id" => @dt1 }, { "direction" => "exhaust_air" },
     { "duct_type_id" => @dt1, "direction" => "supply" },
     { "duct_type_id" => @dt1, "direction" => "exhaust_air", "quantity" => 0 },
     { "duct_type_id" => @dt1, "direction" => "exhaust_air", "quantity" => 1.5 }].each do |values|
      result = assign([target(@edges.first)], values)
      assert_equal %w[refused params.invalid none], result.values_at("status", "code", "effect"), values.inspect
    end
    assert_nil STORE.read(@edges.first)
    assign([target(@edges[1])], "duct_type_id" => @dt1, "direction" => "exhaust_air")
    mixed = assign([target(@edges.first), target(@edges[1])], "quantity" => 3)
    assert_equal %w[refused params.invalid], mixed.values_at("status", "code"), "the unassigned Edge needs both"
    assert_equal 1, STORE.read(@edges[1]).fetch("quantity")
    assert_equal %w[refused target.not_found], assign([target(@edges.first)], "duct_type_id" => "dct_ZZZZZZZZZZZZ",
                                                                              "direction" => "exhaust_air")
      .values_at("status", "code")
  end

  def test_an_edge_outside_a_ducting_group_or_behind_a_lock_refuses_all_and_writes_nothing
    values = { "duct_type_id" => @dt1, "direction" => "exhaust_air" }
    { "ducting.outside_group" => [reference([630, 631]), reference([600, 610, 611], [600])],
      "target.locked" => [reference([620, 621, 622])],
      "target.not_found" => [reference([600, 999])] }.each do |code, targets|
      targets.each do |bad|
        result = assign([target(@edges[1]), bad], values)
        assert_equal ["refused", code, "none"], result.values_at("status", "code", "effect"), bad.inspect
      end
    end
    D::Assignment.gesture_edge_limit = 2
    over = assign(@edges.map { |entity| target(entity) }, values)
    assert_equal %w[refused gesture.too_large], over.values_at("status", "code")
    D::Assignment.reset_for_test
    assert_equal 250, D::Assignment.gesture_edge_limit
    assert(@edges.all? { |entity| STORE.read(entity).nil? })
  end

  def test_a_stale_target_a_misplaced_group_a_component_wrapper_or_a_newer_record_refuses
    values = { "duct_type_id" => @dt1, "direction" => "exhaust_air" }
    assign([target(@edges.first)], values)
    stale = target(@edges.first).merge("expected_values" => { "direction" => "outdoor_air" })
    assert_equal %w[refused target.changed], assign([stale], "quantity" => 2).values_at("status", "code")
    inner = ducting_group(641, "dcg_EEEEEEEEEEEE", [edge(642)])
    zone = Sketchup::Group.new(650, Sketchup::Entities.new([ducting_group(651, "dcg_FFFFFFFFFFFF", [edge(652)])]))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    definition = Sketchup::ComponentDefinition.new(
      Sketchup::Entities.new([ducting_group(671, "dcg_HHHHHHHHHHHH", [edge(672)])])
    )
    @model.entities << ducting_group(640, "dcg_DDDDDDDDDDDD", [inner]) << zone <<
      Sketchup::ComponentInstance.new(670, definition)
    { [640, 641, 642] => "ducting.group_nested", [650, 651, 652] => "ducting.group_in_zone",
      [670, 671, 672] => "target.wrong_hierarchy" }.each do |path, code|
      assert_equal ["refused", code], assign([reference(path)], values).values_at("status", "code")
    end
    STORE.write(@edges[1], "id" => "dce_NEWERNEWERNE", "schema_version" => 2, "duct_type_id" => @dt1,
                           "direction" => "exhaust_air", "quantity" => 1, "future" => true)
    assert_equal %w[refused validation.failed], assign([target(@edges[1])], "quantity" => 2).values_at("status", "code")
    assert_equal 2, STORE.read(@edges[1]).fetch("schema_version")
  end

  def test_clear_removes_the_record_refuses_a_mixed_batch_whole_and_a_split_edge_reads_two_ducts_with_one_id
    assign([target(@edges.first)], "duct_type_id" => @dt1, "direction" => "outdoor_air")
    mixed = [target(@edges.first), reference([620, 621, 622])]
    assert_equal %w[target.locked none], invoke("#{PREFIX}.ducts.clear", "targets" => mixed).values_at("code", "effect")
    D::Assignment.gesture_edge_limit = 0
    assert_equal "gesture.too_large", invoke("#{PREFIX}.ducts.clear", "targets" => [target(@edges.first)])["code"]
    D::Assignment.reset_for_test
    refute_nil STORE.read(@edges.first)
    split = edge(604)
    STORE.write(split, STORE.read(@edges.first))
    @group.entities << split
    rows = select(@edges.first, split).fetch("edges")
    assert_equal [true, true], rows.map { |row| row.fetch("copied") }
    assert_equal 1, rows.map { |row| row.dig("reference", "entity_id") }.uniq.length

    cleared = invoke("#{PREFIX}.ducts.clear", "targets" => [target(@edges.first)])
    assert_equal [1, "committed"], [cleared.dig("value", "cleared"), cleared["effect"]]
    refute STORE.marks?(@edges.first)
    refute_nil STORE.read(split)
    @model.undo
    assert STORE.marks?(live(600, 601))
  end

  def test_a_pasted_group_an_unreadable_record_or_a_referenced_duct_with_a_malformed_map_refuses_the_write
    values = { "duct_type_id" => @dt1, "direction" => "exhaust_air" }
    shared = ducting_group(700, "dcg_CCCCCCCCCCCC", [edge(701)])
    copy = Sketchup::Group.new(710, shared.entities)
    D::Group::STORE.write(copy, D::Group::STORE.read(shared))
    unreadable = ducting_group(720, "dcg_GGGGGGGGGGGG", [edge(721)])
    unreadable.set_attribute(D::Group::STORE.dictionary, D::Group::STORE.key, "not json")
    @model.entities << shared << copy << unreadable
    @edges[2].set_attribute(STORE.dictionary, STORE.key, "not json")
    { [710, 701] => "target.shared_definition", [720, 721] => "record.unreadable",
      [600, 603] => "record.unreadable" }.each do |path, code|
      assert_equal ["refused", code], assign([reference(path)], values).values_at("status", "code"), path.inspect
    end

    assign(@edges.first(2).map { |entity| target(entity) }, values)
    named = STORE.read(@edges[1]).fetch("id")
    STORE.write(@edges[1], STORE.read(@edges[1]).merge("extension_data" => nil))
    envelope = { "schema_version" => 1, "payload" => { "duct" => named }, "export_relevance" => "local_only",
                 "references" => [{ "path" => "$.duct", "target_kind" => D::DUCT_KIND, "cardinality" => "one" }] }
    STORE.write(@edges.first, STORE.read(@edges.first).merge("extension_data" => { "other.tool" => envelope }))
    cleared = invoke("#{PREFIX}.ducts.clear", "targets" => [target(@edges[1])])
    assert_equal %w[refused reference.in_use], cleared.values_at("status", "code")
    assert_match(/still refers to #{D::DUCT_KIND} #{named}/, cleared["message"])
  end

  # A removed id is checked whatever else is wrong with its record: one of a newer schema version, and one whose
  # every copy this clear removes though one copy is invalid, still refuse while a record names it.
  def test_clear_checks_every_removed_id_against_its_referrers
    named = lambda do |entity, id|
      envelope = { "schema_version" => 1, "payload" => { "duct" => id }, "export_relevance" => "local_only",
                   "references" => [{ "path" => "$.duct", "target_kind" => D::DUCT_KIND, "cardinality" => "one" }] }
      STORE.write(entity, STORE.read(entity).merge("extension_data" => { "other.tool" => envelope }))
    end
    values = { "duct_type_id" => @dt1, "direction" => "exhaust_air" }
    assign(@edges.map { |entity| target(entity) }, values)
    STORE.write(@edges.first, STORE.read(@edges.first).merge("schema_version" => 2))
    named.call(@edges[2], STORE.read(@edges.first).fetch("id"))
    assert_equal %w[refused reference.in_use], invoke("#{PREFIX}.ducts.clear", "targets" => [target(@edges.first)])
      .values_at("status", "code")

    STORE.write(@edges[1], STORE.read(@edges[1]).merge("direction" => "bogus"))
    copy = edge(604)
    STORE.write(copy, STORE.read(@edges[1]).merge("direction" => "exhaust_air"))
    @group.entities << copy
    named.call(@edges[2], STORE.read(@edges[1]).fetch("id"))
    both = invoke("#{PREFIX}.ducts.clear", "targets" => [target(@edges[1]), target(copy)])
    assert_equal %w[refused reference.in_use], both.values_at("status", "code")
  end

  def test_a_stale_duct_type_delete_refuses_target_changed_before_a_stranded_duct
    assign([target(@edges.first)], "duct_type_id" => @dt1, "direction" => "exhaust_air")
    @model.entities << Sketchup::Group.new(800, Sketchup::Entities.new([ducting_group(801, "dcg_LLLLLLLLLLLL",
                                                                                      [tagged = edge(802)])]),
                                           :locked => true)
    STORE.write(tagged, STORE.read(@edges.first).merge("id" => "dce_LOCKEDLOCKED"))
    stale = invoke("#{PREFIX}.duct_types.delete", "id" => @dt1, "replacement_id" => @dt2,
                                                  "expected_values" => { "name" => "DT-0" })
    assert_equal %w[refused target.changed], stale.values_at("status", "code")
    fresh = invoke("#{PREFIX}.duct_types.delete", "id" => @dt1, "replacement_id" => @dt2)
    assert_equal %w[refused reference.in_use], fresh.values_at("status", "code")
  end

  def test_deleting_a_duct_type_in_use_refuses_moves_or_nulls_every_duct_in_one_undo_step
    assign(@edges.map { |entity| target(entity) }, "duct_type_id" => @dt1, "direction" => "exhaust_air")
    assert_equal %w[refused reference.in_use], invoke("#{PREFIX}.duct_types.delete", "id" => @dt1)
      .values_at("status", "code")
    moved = invoke("#{PREFIX}.duct_types.delete", "id" => @dt1, "replacement_id" => @dt2)
    assert_equal "committed", moved["effect"], moved.inspect
    assert_equal [@dt2] * 3, types
    @model.undo
    assert_equal [@dt1] * 3, types
    assert_equal "committed", invoke("#{PREFIX}.duct_types.delete", "id" => @dt1, "replacement_id" => nil)["effect"]
    assert_equal [nil] * 3, types
    @model.undo
    assert_equal [@dt1] * 3, types
  end

  def test_a_duct_type_delete_through_two_placements_of_one_group_refuses_atomically
    assign([target(@edges.first)], "duct_type_id" => @dt1, "direction" => "exhaust_air")
    shared = ducting_group(700, "dcg_CCCCCCCCCCCC", [tagged = edge(701)])
    STORE.write(tagged, STORE.read(@edges.first).merge("id" => "dce_SHAREDSHARED"))
    copy = Sketchup::Group.new(710, shared.entities)
    D::Group::STORE.write(copy, D::Group::STORE.read(shared))
    @model.entities << shared << copy
    refusal = invoke("#{PREFIX}.duct_types.delete", "id" => @dt1, "replacement_id" => @dt2)
    assert_equal %w[refused reference.in_use none], refusal.values_at("status", "code", "effect")
    assert_match(/\A2 duct\(s\) use Duct Type/, refusal["message"], "both placements are stranded")
    assert_equal [@dt1, @dt1], [STORE.read(@edges.first), STORE.read(tagged)].map { |record| record["duct_type_id"] }
  end

  def test_the_selection_reports_each_edge_with_its_group_and_ventilator_and_ignores_a_face
    assign([target(@edges.first)], "duct_type_id" => @dt1, "direction" => "outdoor_air")
    face = @group.entities.to_a.find { |entity| entity.is_a?(Sketchup::Face) }
    value = select(@edges.first, @edges[1], face)
    assert_equal [{ "persistent_id" => 609, "type" => "Face" }], value.fetch("ignored")
    rows = value.fetch("edges")
    assert_equal [[600, 601], [600, 602]], rows.map { |row| row.fetch("path") }
    assert_equal [{ "group_id" => "dcg_AAAAAAAAAAAA", "group_path" => [600], "ventilator_id" => @erv }] * 2,
                 rows.map { |row| row.fetch("group") }
    assert_equal ["outdoor_air", nil], rows.map { |row| row.dig("values", "direction") }
    assert_equal [nil, nil], rows.map { |row| row.fetch("write_refusal") }
    section = PhComposer::Snapshot.build(@context).dig("sections", "#{PREFIX}.ducts.selected", "value")
    assert_equal rows, section.fetch("edges")
  end

  private

  def edge(id)
    Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, id, 0))
  end

  def ducting_group(persistent_id, id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    D::Group::STORE.write(group, D::Group.new_record(id, @erv))
    group
  end

  def target(entity, group_path = [600])
    record = STORE.read(entity)
    { "reference" => { "group_path" => group_path, "entity_path" => group_path + [entity.persistent_id],
                       "entity_id" => D::LINE_GROUP.edge_identity(record) },
      "expected_values" => D::Assignment.values(record) }
  end

  def reference(path, group_path = path[0...-1])
    { "reference" => { "group_path" => group_path, "entity_path" => path, "entity_id" => nil } }
  end

  def live(*path)
    path.reduce(nil) do |parent, id|
      (parent ? parent.entities : @model.entities).to_a.find { |entity| entity.persistent_id == id }
    end
  end

  def types
    [601, 602, 603].map { |id| STORE.read(live(600, id))["duct_type_id"] }
  end

  def select(*entities)
    @model.active_path = [@group]
    @model.selection.clear
    @model.selection.add(entities)
    result = API.query(:context => @context, :name => "#{PREFIX}.ducts.selection")
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def assign(targets, values)
    invoke("#{PREFIX}.ducts.assign", { "targets" => targets }.merge(values))
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
