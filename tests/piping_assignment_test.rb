# frozen_string_literal: true

require_relative "test_helper"

# The pipe assignment through its registered actions and selection read (context/CONTRACTS.md, "Hot water piping"):
# every write names explicit Edges directly in a Piping group, carries exactly its role's values, refuses as a whole
# and is one native Undo step; a Pipe Type delete moves, nulls or refuses the pipes naming it.
class PipingAssignmentTest < PhComposerTestCase
  API = PhComposer::API
  P = PhComposer::Piping
  STORE = P::Assignment::STORE
  PREFIX = "ph_composer.piping"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @hws = invoke("ph_composer.mechanical.hot_water_systems.create", "values" => { "name" => "HWS-1" })
           .dig("value", "id")
    @pex = invoke("#{PREFIX}.pipe_types.create", "values" => { "name" => "PEX 3/4", "material" => 6 }).dig("value",
                                                                                                           "id")
    @copper = invoke("#{PREFIX}.pipe_types.create", "values" => { "name" => "Copper 1/2" }).dig("value", "id")
    fixture
  end

  # Piping group 600 at the root holds Edges 601 to 603, a Face 609 and a plain Group 610 holding Edge 611. Locked
  # wrapper 620 holds Piping group 621 with Edge 622. Plain Group 630 at the root holds Edge 631.
  def fixture
    @edges = [601, 602, 603].map { |id| edge(id) }
    @group = piping_group(600, "ppg_AAAAAAAAAAAA", @edges + [Sketchup::Face.new(609),
                                                             Sketchup::Group.new(610,
                                                                                 Sketchup::Entities.new([edge(611)]))])
    locked = Sketchup::Group.new(620, Sketchup::Entities.new([piping_group(621, "ppg_BBBBBBBBBBBB", [edge(622)])]),
                                 :locked => true)
    @model.entities << @group << locked << Sketchup::Group.new(630, Sketchup::Entities.new([edge(631)]))
  end

  def test_assign_writes_a_trunk_in_one_undo_step_and_a_new_role_drops_the_old_roles_values
    first = assign(@edges.map { |entity| target(entity) }, @pex, "trunk", "multiplier" => 12)
    assert_equal "committed", first["effect"], first.inspect
    ids = first.dig("value", "edge_ids")
    assert(ids.uniq.length == 3 && ids.all? { |id| id.match?(/\Appe_[A-Za-z0-9]{12}\z/) })
    trunk = { "pipe_type_id" => @pex, "role" => "trunk", "multiplier" => 12, "demand_recirculation" => false }
    assert_equal [trunk] * 3, @edges.map { |entity| P::Assignment.values(STORE.read(entity)) }

    second = assign([target(@edges.first)], @copper, "recirculation", "water_temp_c" => 55.0, "daily_period" => 18)
    assert_equal "committed", second["effect"], second.inspect
    assert_equal({ "pipe_type_id" => @copper, "role" => "recirculation", "water_temp_c" => 55.0,
                   "daily_period" => 18 }, P::Assignment.values(STORE.read(@edges.first)))
    assert_equal ids.first, STORE.read(@edges.first).fetch("id")
    @model.undo
    assert_equal trunk, P::Assignment.values(STORE.read(live(600, 601)))
    @model.undo
    assert_nil STORE.read(live(600, 601))
  end

  def test_a_value_the_role_does_not_take_refuses_params_invalid
    [["trunk", { "water_temp_c" => 55.0 }], ["branch", { "multiplier" => 2 }],
     ["recirculation", { "daily_period" => 25 }], ["twig", { "demand_recirculation" => true }]].each do |role, values|
      result = assign([target(@edges.first)], @pex, role, values)
      assert_equal %w[refused params.invalid none], result.values_at("status", "code", "effect"), [role, values].inspect
    end
    assert_nil STORE.read(@edges.first)
    assign([target(@edges.first)], @pex, "branch")
    assert_equal({ "pipe_type_id" => @pex, "role" => "branch" }, P::Assignment.values(STORE.read(@edges.first)))
  end

  def test_an_edge_outside_a_piping_group_or_behind_a_lock_refuses_all_and_writes_nothing
    { "piping.outside_group" => [reference([630, 631]), reference([600, 610, 611], [600])],
      "target.locked" => [reference([620, 621, 622])],
      "target.not_found" => [reference([600, 999])] }.each do |code, targets|
      targets.each do |bad|
        result = assign([target(@edges[1]), bad], @pex, "branch")
        assert_equal ["refused", code, "none"], result.values_at("status", "code", "effect"), bad.inspect
      end
    end
    P::Assignment.gesture_edge_limit = 2
    over = assign(@edges.map { |entity| target(entity) }, @pex, "branch")
    assert_equal %w[refused gesture.too_large], over.values_at("status", "code")
    P::Assignment.reset_for_test
    assert_equal 250, P::Assignment.gesture_edge_limit
    assert(@edges.all? { |entity| STORE.read(entity).nil? })
  end

  def test_a_reassign_keeps_its_roles_values_and_a_stale_target_misplaced_group_or_unknown_type_refuses
    assign([target(@edges.first)], @pex, "trunk", "multiplier" => 12)
    assign([target(@edges.first)], @copper, "trunk")
    assert_equal [@copper, 12], STORE.read(@edges.first).values_at("pipe_type_id", "multiplier")
    stale = target(@edges.first).merge("expected_values" => { "role" => "branch" })
    assert_equal %w[refused target.changed], assign([stale], @pex, "trunk").values_at("status", "code")
    assert_equal %w[refused target.not_found], assign([target(@edges[1])], "ppt_ZZZZZZZZZZZZ", "twig")
      .values_at("status", "code")
    inner = piping_group(641, "ppg_EEEEEEEEEEEE", [edge(642)])
    zone = Sketchup::Group.new(650, Sketchup::Entities.new([piping_group(651, "ppg_FFFFFFFFFFFF", [edge(652)])]))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    @model.entities << piping_group(640, "ppg_DDDDDDDDDDDD", [inner]) << zone
    { [640, 641, 642] => "piping.group_nested", [650, 651, 652] => "piping.group_in_zone" }.each do |path, code|
      assert_equal ["refused", code], assign([reference(path)], @pex, "twig").values_at("status", "code")
    end
    unreadable = piping_group(660, "ppg_GGGGGGGGGGGG", [edge(661)])
    unreadable.set_attribute(P::Group::STORE.dictionary, P::Group::STORE.key, "not json")
    @model.entities << unreadable
    assert_equal %w[refused record.unreadable],
                 assign([reference([660, 661])], @pex, "twig").values_at("status", "code")
  end

  def test_a_component_wrapper_a_newer_record_or_malformed_metadata_refuses_or_reads_without_breaking_other_writes
    definition = Sketchup::ComponentDefinition.new(
      Sketchup::Entities.new([piping_group(671, "ppg_HHHHHHHHHHHH", [edge(672)])])
    )
    @model.entities << Sketchup::ComponentInstance.new(670, definition)
    assert_equal %w[refused target.wrong_hierarchy none],
                 assign([reference([670, 671, 672])], @pex, "twig").values_at("status", "code", "effect")

    STORE.write(@edges.first, "id" => "ppe_NEWERNEWERNE", "schema_version" => 2, "pipe_type_id" => @pex,
                              "role" => "twig", "future" => true)
    assert_equal %w[refused validation.failed], assign([target(@edges.first)], @copper, "twig")
      .values_at("status", "code")
    assert_equal 2, STORE.read(@edges.first).fetch("schema_version")

    STORE.write(@edges[1], "id" => "ppe_NULLMAPNULLM", "schema_version" => 1, "pipe_type_id" => @pex,
                           "role" => "twig", "extension_data" => nil)
    spare = invoke("ph_composer.mechanical.hot_water_systems.create", "values" => { "name" => "Spare" })
    assert_equal "committed", invoke("ph_composer.mechanical.hot_water_systems.delete",
                                     "id" => spare.dig("value", "id"))["effect"]

    P::Group::STORE.write(@group, "schema_version" => 1, "hot_water_system_id" => @hws)
    row = select(@edges[2]).fetch("edges").first
    assert_nil row.fetch("group")
    assert_equal "validation.failed", row.dig("write_refusal", "code")
  end

  def test_clear_refuses_a_mixed_or_over_limit_batch_whole_and_a_referenced_pipe_with_a_malformed_map
    assign(@edges.map { |entity| target(entity) }, @pex, "twig")
    [[target(@edges.first), reference([620, 621, 622])],
     [target(@edges.first), reference([600, 999])]].each do |targets|
      assert_equal "none", invoke("#{PREFIX}.pipes.clear", "targets" => targets)["effect"]
    end
    P::Assignment.gesture_edge_limit = 2
    assert_equal "gesture.too_large", invoke("#{PREFIX}.pipes.clear", "targets" => @edges.map { |entity|
      target(entity)
    })
      .fetch("code")
    assert(@edges.all? { |entity| STORE.read(entity) })

    named = STORE.read(@edges[1]).fetch("id")
    STORE.write(@edges[1], STORE.read(@edges[1]).merge("extension_data" => nil))
    envelope = { "schema_version" => 1, "payload" => { "pipe" => named }, "export_relevance" => "local_only",
                 "references" => [{ "path" => "$.pipe", "target_kind" => P::PIPE_KIND, "cardinality" => "one" }] }
    STORE.write(@edges[2], STORE.read(@edges[2]).merge("extension_data" => { "other.tool" => envelope }))
    cleared = invoke("#{PREFIX}.pipes.clear", "targets" => [target(@edges[1])])
    assert_equal %w[refused reference.in_use], cleared.values_at("status", "code")
    assert_match(/still refers to #{P::PIPE_KIND} #{named}/, cleared["message"])
    assert_equal %w[refused reference.in_use], invoke("#{PREFIX}.pipe_types.delete",
                                                      "id" => @pex, "replacement_id" => nil).values_at("status", "code")
  end

  def test_clear_removes_the_record_and_a_split_edge_reads_two_pipes_with_one_id
    assign([target(@edges.first)], @pex, "twig")
    split = edge(604)
    STORE.write(split, STORE.read(@edges.first))
    @group.entities << split
    rows = select(@edges.first, split).fetch("edges")
    assert_equal [true, true], rows.map { |row| row.fetch("copied") }
    assert_equal 1, rows.map { |row| row.dig("reference", "entity_id") }.uniq.length

    cleared = invoke("#{PREFIX}.pipes.clear", "targets" => [target(@edges.first)])
    assert_equal [1, "committed"], [cleared.dig("value", "cleared"), cleared["effect"]]
    refute STORE.marks?(@edges.first)
    refute_nil STORE.read(split)
  end

  # A removed id is checked whatever else is wrong with its record: one of a newer schema version, and one whose
  # every copy this clear removes though one copy is invalid, still refuse while a record names it.
  def test_clear_checks_every_removed_id_against_its_referrers
    named = lambda do |entity, id|
      envelope = { "schema_version" => 1, "payload" => { "pipe" => id }, "export_relevance" => "local_only",
                   "references" => [{ "path" => "$.pipe", "target_kind" => P::PIPE_KIND, "cardinality" => "one" }] }
      STORE.write(entity, STORE.read(entity).merge("extension_data" => { "other.tool" => envelope }))
    end
    assign(@edges.map { |entity| target(entity) }, @pex, "twig")
    STORE.write(@edges.first, STORE.read(@edges.first).merge("schema_version" => 2))
    named.call(@edges[2], STORE.read(@edges.first).fetch("id"))
    assert_equal %w[refused reference.in_use], invoke("#{PREFIX}.pipes.clear", "targets" => [target(@edges.first)])
      .values_at("status", "code")

    STORE.write(@edges[1], STORE.read(@edges[1]).merge("role" => "bogus"))
    copy = edge(604)
    STORE.write(copy, STORE.read(@edges[1]).merge("role" => "twig"))
    @group.entities << copy
    named.call(@edges[2], STORE.read(@edges[1]).fetch("id"))
    both = invoke("#{PREFIX}.pipes.clear", "targets" => [target(@edges[1]), target(copy)])
    assert_equal %w[refused reference.in_use], both.values_at("status", "code")
  end

  # A stale expected_values refuses before any pipe is planned, so a pipe the rewrite cannot reach never hides it.
  def test_a_stale_pipe_type_delete_refuses_target_changed_before_a_stranded_pipe
    assign([target(@edges.first)], @pex, "twig")
    tagged = live(620, 621, 622)
    STORE.write(tagged, STORE.read(@edges.first).merge("id" => "ppe_LOCKEDLOCKED"))
    stale = invoke("#{PREFIX}.pipe_types.delete", "id" => @pex, "replacement_id" => @copper,
                                                  "expected_values" => { "name" => "PEX 1/2" })
    assert_equal [%w[name], "refused", "target.changed"], [stale.dig("detail", "fields")] +
                                                          stale.values_at("status", "code")
    fresh = invoke("#{PREFIX}.pipe_types.delete", "id" => @pex, "replacement_id" => @copper)
    assert_equal %w[refused reference.in_use], fresh.values_at("status", "code")
  end

  def test_deleting_a_pipe_type_in_use_refuses_moves_or_nulls_every_pipe_in_one_undo_step
    assign(@edges.map { |entity| target(entity) }, @pex, "branch")
    assert_equal %w[refused reference.in_use], invoke("#{PREFIX}.pipe_types.delete", "id" => @pex)
      .values_at("status", "code")
    moved = invoke("#{PREFIX}.pipe_types.delete", "id" => @pex, "replacement_id" => @copper)
    assert_equal "committed", moved["effect"], moved.inspect
    assert_equal [@copper] * 3, types
    @model.undo
    assert_equal [@pex] * 3, types
    assert_equal "committed", invoke("#{PREFIX}.pipe_types.delete", "id" => @pex, "replacement_id" => nil)["effect"]
    assert_equal [nil] * 3, types
  end

  def test_a_pipe_type_delete_through_two_placements_of_one_group_refuses_atomically
    assign([target(@edges.first)], @pex, "branch")
    shared = piping_group(700, "ppg_CCCCCCCCCCCC", [tagged = edge(701)])
    STORE.write(tagged, STORE.read(@edges.first).merge("id" => "ppe_SHAREDSHARED"))
    copy = Sketchup::Group.new(710, shared.entities)
    P::Group::STORE.write(copy, P::Group::STORE.read(shared))
    @model.entities << shared << copy
    refusal = invoke("#{PREFIX}.pipe_types.delete", "id" => @pex, "replacement_id" => @copper)
    assert_equal %w[refused reference.in_use none], refusal.values_at("status", "code", "effect")
    assert_match(/\A2 pipe\(s\) use Pipe Type/, refusal["message"], "both placements are stranded")
    assert_equal [@pex, @pex], [STORE.read(@edges.first), STORE.read(tagged)].map { |record| record["pipe_type_id"] }
  end

  def test_the_selection_reports_each_edge_with_its_group_and_system_and_ignores_a_face
    assign([target(@edges.first)], @pex, "trunk")
    face = @group.entities.to_a.find { |entity| entity.is_a?(Sketchup::Face) }
    value = select(@edges.first, @edges[1], face)
    assert_equal [{ "persistent_id" => 609, "type" => "Face" }], value.fetch("ignored")
    rows = value.fetch("edges")
    assert_equal [[600, 601], [600, 602]], rows.map { |row| row.fetch("path") }
    assert_equal [{ "group_id" => "ppg_AAAAAAAAAAAA", "group_path" => [600], "hot_water_system_id" => @hws }] * 2,
                 rows.map { |row| row.fetch("group") }
    assert_equal ["trunk", nil], rows.map { |row| row.dig("values", "role") }
    assert_equal [nil, nil], rows.map { |row| row.fetch("write_refusal") }

    client = P::Assignment::Selection.client(@session)
    @model.selection.clear
    @model.selection.add([@edges[1], @edges[2]])
    assert_equal "committed", client.assign(@copper, "recirculation", "daily_period" => 12)["effect"]
    assert_equal [12, 12], [@edges[1], @edges[2]].map { |entity| STORE.read(entity)["daily_period"] }
  end

  private

  def edge(id)
    Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, id, 0))
  end

  def piping_group(persistent_id, id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    P::Group::STORE.write(group, P::Group.new_record(id, @hws))
    group
  end

  def target(entity, group_path = [600])
    record = STORE.read(entity)
    { "reference" => { "group_path" => group_path, "entity_path" => group_path + [entity.persistent_id],
                       "entity_id" => P::Assignment.identity(record) },
      "expected_values" => P::Assignment.values(record) }
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
    [601, 602, 603].map { |id| STORE.read(live(600, id))["pipe_type_id"] }
  end

  def select(*entities)
    @model.active_path = [@group]
    @model.selection.clear
    @model.selection.add(entities)
    result = API.query(:context => @context, :name => "#{PREFIX}.pipes.selection")
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def assign(targets, type_id, role, values = {})
    invoke("#{PREFIX}.pipes.assign", { "targets" => targets, "pipe_type_id" => type_id, "role" => role }.merge(values))
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
