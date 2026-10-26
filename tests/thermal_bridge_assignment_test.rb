# frozen_string_literal: true

require_relative "test_helper"

# Edge assignment through its registered actions and selection read: every write names explicit Edge
# references inside a Zone, refuses as a whole, and is one native Undo step (context/CONTRACTS.md,
# "Geometry records and occurrence references").
class ThermalBridgeAssignmentTest < PhComposerTestCase
  API = PhComposer::API
  TB = PhComposer::ThermalBridges
  STORE = TB::Assignment::STORE
  QUARTER_TURN = [0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 500.0, 0.0, 0.0, 1.0].freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(TB::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    fixture
    @parapet = create_type("Parapet", 0.05)
    @slab = create_type("Slab edge", 0.12)
  end

  # Zone A (100) at the root holds Edges 101 to 103, a wall Face, a component placement whose
  # definition holds Edge 141, a locked Group holding Edge 131 and a nested Zone (150) holding Edge 151.
  # Zone B (200) sits in a quarter-turned wrapper (20) and holds Edge 201.
  # Edge 5 is at the Model root.
  def fixture
    @edges = [101, 102, 103].map { |id| edge(id) }
    @wall = Sketchup::Face.new(110)
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([@shared = edge(141)]))
    locked = Sketchup::Group.new(130, Sketchup::Entities.new([edge(131)]), :locked => true)
    inner = zone("zon_CCCCCCCCCCCC", 150, [edge(151)])
    @zone_a = zone("zon_AAAAAAAAAAAA", 100, @edges + [@wall, Sketchup::ComponentInstance.new(140, definition), locked,
                                                      inner])
    @nested = edge(201)
    @wrapper = Sketchup::Group.new(20, Sketchup::Entities.new([zone("zon_BBBBBBBBBBBB", 200, [@nested])]),
                                   :transformation => Geom::Transformation.new(QUARTER_TURN))
    @model.entities << @zone_a
    @model.entities << @wrapper
    @model.entities << (@loose = edge(5))
  end

  def test_assign_writes_every_edge_in_one_undo_step_and_reassign_and_clear_follow
    first = assign(@edges.map { |entity| target(entity) }, @parapet)
    assert_equal "committed", first["effect"], first.inspect
    ids = first.dig("value", "edge_ids")
    assert_equal 3, ids.uniq.length
    assert(ids.all? { |id| id.match?(/\Atbe_[A-Za-z0-9]{12}\z/) })
    assert_equal [@parapet] * 3, @edges.map { |entity| STORE.read(entity)["thermal_bridge_type_id"] }

    tagged = STORE.read(@edges.first).merge("user_data" => { "test" => { "kept" => true } })
    STORE.write(@edges.first, tagged)
    second = assign([target(@edges.first)], @slab, :quantity => 2)
    assert_equal "committed", second["effect"], second.inspect
    assert_equal tagged.merge("thermal_bridge_type_id" => @slab, "quantity" => 2), STORE.read(@edges.first)

    cleared = invoke("edges.clear", "targets" => [target(@edges.first)])
    assert_equal [1, "committed"], [cleared.dig("value", "cleared"), cleared["effect"]]
    assert_nil @edges.first.attribute_dictionary(STORE.dictionary)

    @model.undo
    assert_equal tagged.merge("thermal_bridge_type_id" => @slab, "quantity" => 2), STORE.read(live(100, 101))
    @model.undo
    assert_equal tagged.merge("thermal_bridge_type_id" => @parapet), STORE.read(live(100, 101))
    @model.undo
    assert([101, 102, 103].all? { |id| STORE.read(live(100, id)).nil? })
  end

  def test_a_stale_or_unwritable_target_or_one_over_the_limit_refuses_all_and_writes_nothing
    assign([target(@edges.first)], @parapet)
    stale = target(@edges.first).merge("expected_values" => { "thermal_bridge_type_id" => @slab })
    refusals = {
      "target.changed" => [target(@edges[1]), stale],
      "target.shared_definition" => [target(@edges[1]), reference_target([100, 140, 141])],
      "target.locked" => [target(@edges[1]), reference_target([100, 130, 131])],
      "target.wrong_hierarchy" => [target(@edges[1]), reference_target([100, 150, 151])],
      "target.not_found" => [target(@edges[1]), reference_target([100, 999])]
    }
    refusals.each do |code, targets|
      result = assign(targets, @slab)
      assert_equal ["refused", code, "none"], result.values_at("status", "code", "effect"), code
    end
    TB::Assignment.gesture_edge_limit = 2
    over = assign(@edges.map { |entity| target(entity) }, @slab)
    assert_equal %w[refused gesture.too_large], over.values_at("status", "code")
    assert_equal [@parapet, nil, nil], @edges.map { |entity| STORE.read(entity)&.fetch("thermal_bridge_type_id") }
  end

  def test_the_limit_itself_assigns_and_the_shipped_limit_is_250
    assert_equal 250, TB::Assignment::GESTURE_EDGE_LIMIT
    TB::Assignment.gesture_edge_limit = 2
    assert_equal "committed", assign(@edges.first(2).map { |entity| target(entity) }, @slab)["effect"]
  end

  def test_two_references_with_one_root_path_are_still_two_targets
    through_outer = reference_target([100, 150, 151])
    inner = { "reference" => { "zone_id" => "zon_CCCCCCCCCCCC", "zone_path" => [100, 150], "entity_path" => [151],
                               "entity_id" => nil } }
    result = assign([through_outer, inner], @parapet)
    assert_equal %w[refused target.wrong_hierarchy], result.values_at("status", "code"), result.inspect
  end

  def test_an_invalid_assignment_reads_with_its_problem_and_can_be_cleared
    STORE.write(@edges.first, "id" => "tbe_BADBADBADBAD", "schema_version" => 1,
                              "thermal_bridge_type_id" => @parapet, "quantity" => -3)
    @model.active_path = [@zone_a]
    @model.selection.add([@edges.first])
    row = selection.fetch("edges").first
    assert_match(/quantity/, row.fetch("record_problem"))
    cleared = invoke("edges.clear", "targets" => [{ "reference" => row.fetch("reference") }])
    assert_equal "committed", cleared["effect"], cleared.inspect
    assert_nil STORE.read(live(100, 101))
  end

  def test_clearing_an_assignment_another_record_names_refuses_unless_a_copy_keeps_its_id
    assign([target(@edges.first)], @parapet)
    assign([target(@edges[1])], @slab)
    named = STORE.read(@edges.first).fetch("id")
    envelope = { "schema_version" => 1, "payload" => { "edge" => named }, "export_relevance" => "local_only",
                 "references" => [{ "path" => "$.edge", "target_kind" => TB::EDGE_KIND, "cardinality" => "one" }] }
    STORE.write(@edges[1], STORE.read(@edges[1]).merge("extension_data" => { "other.tool" => envelope }))
    [["edges.clear", { "targets" => [target(@edges.first)] }],
     ["types.delete", { "id" => @parapet, "replacement_id" => nil }]].each do |name, params|
      result = invoke(name, params)
      assert_equal %w[refused reference.in_use none], result.values_at("status", "code", "effect"), name
    end
    STORE.write(@edges[2], STORE.read(@edges.first))
    assert_equal "committed", invoke("edges.clear", "targets" => [target(@edges.first)])["effect"]
  end

  def test_a_stored_value_of_the_wrong_type_still_reads_and_clears
    STORE.write(@edges.first, "id" => "tbe_BADBADBADBAD", "schema_version" => 1,
                              "thermal_bridge_type_id" => @parapet, "quantity" => "two", "invented" => true)
    @model.active_path = [@zone_a]
    @model.selection.add([@edges.first])
    row = selection.fetch("edges").first
    assert_equal "two", row.dig("values", "quantity")
    refute_nil row.fetch("record_problem")
    cleared = invoke("edges.clear", "targets" => [{ "reference" => row.fetch("reference"),
                                                    "expected_values" => row.fetch("values") }])
    assert_equal "committed", cleared["effect"], cleared.inspect
  end

  def test_the_selection_pages_within_its_bound_and_a_changed_selection_expires_the_cursor
    @model.active_path = [@zone_a]
    @model.selection.add(@edges)
    first = selection("limit" => 2)
    assert_equal [3, [[100, 101], [100, 102]]], [first.fetch("total"), first.fetch("edges").map { |row| row["path"] }]
    second = selection("limit" => 2, "cursor" => first.fetch("next_cursor"))
    assert_equal [[[100, 103]], nil], [second.fetch("edges").map { |row| row["path"] }, second.fetch("next_cursor")]
    @model.selection.remove(@edges.last)
    expired = API.query(:context => @context, :name => "#{TB::FEATURE_ID}.edges.selection",
                        :params => { "limit" => 2, "cursor" => first.fetch("next_cursor") })
    assert_equal %w[refused query.cursor_expired], expired.values_at("status", "code")
    all = API.query(:context => @context, :name => "#{TB::FEATURE_ID}.edges.selection_all")
    assert_equal 2, all.dig("value", "edges").length
  end

  def test_the_selection_client_assigns_and_clears_what_is_selected
    @model.active_path = [@zone_a]
    @model.selection.add(@edges)
    client = TB::Assignment::Selection.client(@session)
    assert_equal "committed", client.assign(@parapet, :quantity => 2)["effect"]
    assigned = [101, 102, 103].map { |id| STORE.read(live(100, id)).values_at("thermal_bridge_type_id", "quantity") }
    assert_equal [[@parapet, 2]] * 3, assigned
    @model.active_path = [live(100)]
    @model.selection.add([101, 102, 103].map { |id| live(100, id) })
    assert_equal "committed", client.clear["effect"]
    assert([101, 102, 103].all? { |id| STORE.read(live(100, id)).nil? })
  end

  def test_the_step_writes_nothing_when_an_edge_changed_after_planning
    reference = target(@edges.first).fetch("reference")
    after = { "id" => "tbe_AAAAAAAAAAAA", "schema_version" => 1, "thermal_bridge_type_id" => @parapet, "quantity" => 1 }
    step = TB::Assignment::WriteStep.new(:updates => [{ "reference" => reference, "before" => nil, "after" => after,
                                                        "change" => "created" },
                                                      { "reference" => target(@edges[1]).fetch("reference"),
                                                        "before" => nil, "after" => after, "change" => "created" }])
    STORE.write(@edges[1], after.merge("id" => "tbe_BBBBBBBBBBBB"))
    error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
    assert_equal "target.changed", error.code
    assert_nil STORE.read(@edges.first)
  end

  def test_the_selection_returns_edges_with_their_zone_and_reports_anything_else_as_ignored
    @model.active_path = [@zone_a]
    @model.selection.add([@edges.first, @wall])
    value = selection
    assert_equal [[{ "persistent_id" => 110, "type" => "Face" }], 1], value.values_at("ignored", "ignored_total")
    row = value.fetch("edges").first
    assert_equal({ "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [100], "entity_path" => [101],
                   "entity_id" => nil }, row.fetch("reference"))
    assert_equal [{}, false, nil], row.values_at("values", "copied", "write_refusal")

    @model.active_path = []
    @model.selection.clear
    @model.selection.add([@loose])
    outside = selection.fetch("edges").first
    assert_equal [nil, "outside_zone"], outside.values_at("reference", "reason")
    refused = TB::Assignment::Selection.client(@session).assign(@parapet)
    assert_equal "refused", refused["status"]
    assert_nil STORE.read(@loose)
  end

  def test_delete_with_a_replacement_rewrites_direct_and_nested_edges_in_one_undo_step
    assign([target(@edges.first)], @parapet)
    assign([target(@nested, [20, 200])], @parapet)
    in_use = invoke("types.delete", "id" => @parapet)
    assert_equal %w[refused reference.in_use], in_use.values_at("status", "code")

    replaced = invoke("types.delete", "id" => @parapet, "replacement_id" => @slab)
    assert_equal "committed", replaced["effect"], replaced.inspect
    assert_equal [@slab, @slab], [@edges.first, @nested].map { |entity| STORE.read(entity)["thermal_bridge_type_id"] }

    @model.undo
    assert_equal [@parapet, @parapet],
                 [live(100, 101), live(20, 200, 201)].map { |entity| STORE.read(entity)["thermal_bridge_type_id"] }
    assert_includes type_ids, @parapet

    cleared = invoke("types.delete", "id" => @parapet, "replacement_id" => nil)
    assert_equal "committed", cleared["effect"], cleared.inspect
    assert_nil STORE.read(live(100, 101))
    assert_nil STORE.read(live(20, 200, 201))
    refute_includes type_ids, @parapet
  end

  def test_a_tag_inside_shared_storage_refuses_the_whole_delete
    assign([target(@edges.first)], @parapet)
    STORE.write(@shared, STORE.read(@edges.first).merge("id" => "tbe_SHAREDSHARED"))
    result = invoke("types.delete", "id" => @parapet, "replacement_id" => @slab)
    assert_equal %w[refused reference.in_use none], result.values_at("status", "code", "effect")
    assert_match(/explode its component/, result.fetch("message"))
    assert_equal @parapet, STORE.read(@edges.first)["thermal_bridge_type_id"]
  end

  # The host splits a tagged Edge into two that both carry its whole record (context/SKETCHUP_HOST_BEHAVIOR.md,
  # "Edge#split"); the stub plants the second piece with the same dictionary.
  def test_a_split_edge_reads_as_copied_on_both_pieces_and_nothing_repairs_it
    assign([target(@edges.first)], @parapet)
    record = STORE.read(@edges.first)
    piece = edge(104)
    STORE.write(piece, record)
    @zone_a.entities << piece
    @model.active_path = [@zone_a]
    @model.selection.add([@edges.first, piece])

    rows = selection.fetch("edges")
    assert_equal [true, true], rows.map { |row| row.fetch("copied") }
    assert_equal [record.fetch("id")] * 2, rows.map { |row| row.dig("reference", "entity_id") }
    targets = rows.map { |row| { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") } }
    result = assign(targets, @slab)
    assert_equal "committed", result["effect"], result.inspect
    assert_equal [record.fetch("id")] * 2, [@edges.first, piece].map { |entity| STORE.read(entity)["id"] }
  end

  private

  # The entity at a root-to-entity path in the live Model, which Undo restores as new objects.
  def live(*path)
    path.reduce(nil) do |parent, id|
      entities = if parent.nil? then @model.entities
                 elsif parent.is_a?(Sketchup::Group) then parent.entities
                 else parent.definition.entities
                 end
      entities.to_a.find { |entity| entity.persistent_id == id }
    end
  end

  def edge(id)
    Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, id, 0))
  end

  def zone(id, persistent_id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    PhComposer::Zones::ZONE_STORE.write(group,
                                        "id" => id, "schema_version" => 1, "name" => "Zone #{persistent_id}",
                                        "building_segment" => "Building", "level" => nil, "ground_depth_mm" => 0.0,
                                        "user_data" => {}, "extension_data" => {})
    group
  end

  def target(entity, zone_path = [100])
    record = STORE.read(entity)
    reference = { "zone_id" => zone_path == [100] ? "zon_AAAAAAAAAAAA" : "zon_BBBBBBBBBBBB", "zone_path" => zone_path,
                  "entity_path" => [entity.persistent_id], "entity_id" => record&.fetch("id") }
    { "reference" => reference, "expected_values" => TB::Assignment.values(record) }
  end

  def reference_target(path)
    { "reference" => { "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [path.first], "entity_path" => path[1..-1],
                       "entity_id" => nil } }
  end

  def assign(targets, type_id, quantity: 1)
    invoke("edges.assign", "targets" => targets, "thermal_bridge_type_id" => type_id, "quantity" => quantity)
  end

  def selection(params = {})
    result = API.query(:context => @context, :name => "#{TB::FEATURE_ID}.edges.selection", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def create_type(name, psi)
    invoke("types.create", "values" => { "name" => name, "psi_w_mk" => psi }).dig("value", "id")
  end

  def type_ids
    API.query(:context => @context, :name => "#{TB::FEATURE_ID}.types.all").dig("value", "records").map do |row|
      row.fetch("id")
    end
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{TB::FEATURE_ID}.#{name}", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
