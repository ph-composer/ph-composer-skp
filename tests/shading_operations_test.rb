# frozen_string_literal: true

require_relative "test_helper"

# The shading mark through its registered actions and reads, with the panel closed: assign and clear over
# explicit root-to-entity paths, each one native Undo step; every target rule of context/CONTRACTS.md, "The
# shading mark"; a mixed command; stale paths and revisions; an unreadable mark; list and selection.
class ShadingOperationsTest < PhComposerTestCase
  API = PhComposer::API
  SH = PhComposer::Shading
  STORE = SH::Mark::STORE

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(SH::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    fixture
  end

  # Zone A (100) holds an overhang Face 101, a wall Face 102, a Group "Fin" (110) of Face 111, a locked Group
  # (120) of Face 121 and a cutting component (130) of Face 131. At the root: loose Face 5 and Edge 6; a Group
  # "Neighbour" (20) of Face 21 and an unnamed Group (22) of Face 23; three placements (40, 42, 43) of a
  # component "Louvre" of Face 41; a component placed once (50) of Face 51; two copies (60, 61) of a Group of
  # Face 62; a Group (70) holding Zone 71 and Face 73; a Space Group (80) of Face 81; a Group (85) holding a
  # Space (86); a Window Unit (90) of Face 91; a Louvre placement named "Louvre East" (44) and a locked one (45);
  # and two root Faces that share persistent id 7.
  def fixture
    cutting = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(131)]))
    cutting.behavior.cuts_opening = true
    @zone = zone(100, "Zone A", [Sketchup::Face.new(101), Sketchup::Face.new(102),
                                 Sketchup::Group.new(110, Sketchup::Entities.new([Sketchup::Face.new(111)]),
                                                     :name => "Fin"),
                                 Sketchup::Group.new(120, Sketchup::Entities.new([Sketchup::Face.new(121)]),
                                                     :locked => true),
                                 Sketchup::ComponentInstance.new(130, cutting)])
    louvre = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(41)]), :name => "Louvre")
    once = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(51)]), :name => "Once")
    copied = Sketchup::Entities.new([Sketchup::Face.new(62)])
    space = Sketchup::Group.new(80, Sketchup::Entities.new([Sketchup::Face.new(81), Sketchup::Group.new(
      82, Sketchup::Entities.new([Sketchup::Face.new(83)])
    )]))
    PhComposer::Spaces::SPACE_STORE.write(space, "id" => "spc_AAAAAAAAAAAA")
    inner_space = Sketchup::Group.new(86, Sketchup::Entities.new([Sketchup::Face.new(87)]))
    PhComposer::Spaces::SPACE_STORE.write(inner_space, "id" => "spc_BBBBBBBBBBBB")
    window = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(91)]))
    window.behavior.cuts_opening = true
    unit = Sketchup::ComponentInstance.new(90, window)
    PhComposer::Windows::Units::STORE.write(unit, "id" => "win_AAAAAAAAAAAA")
    [@zone, Sketchup::Face.new(5), Sketchup::Edge.new(6, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0)),
     Sketchup::Group.new(20, Sketchup::Entities.new([Sketchup::Face.new(21),
                                                     Sketchup::Group.new(22, Sketchup::Entities.new(
                                                       [Sketchup::Face.new(23)]
                                                     )), Sketchup::ComponentInstance.new(24, cutting)]),
                         :name => "Neighbour"),
     Sketchup::ComponentInstance.new(40, louvre), Sketchup::ComponentInstance.new(42, louvre),
     Sketchup::ComponentInstance.new(43, louvre), Sketchup::ComponentInstance.new(50, once),
     Sketchup::Group.new(60, copied), Sketchup::Group.new(61, copied),
     Sketchup::Group.new(70, Sketchup::Entities.new([zone(71, "Inner", [Sketchup::Face.new(72)]),
                                                     Sketchup::Face.new(73)])),
     Sketchup::ComponentInstance.new(44, louvre, :name => "Louvre East"), locked_louvre(louvre),
     Sketchup::Face.new(7), Sketchup::Face.new(7),
     space, Sketchup::Group.new(85, Sketchup::Entities.new([inner_space])), unit].each do |entity|
      @model.entities << entity
    end
  end

  def test_assign_marks_faces_groups_and_instances_direct_and_nested_in_one_undo_step
    paths = [[5], [20], [20, 22, 23], [40], [100, 101], [100, 110], [100, 110, 111], [70, 71, 72], [50, 51]]
    result = assign(*paths)
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assert_equal paths, result.dig("value", "assigned").map { |row| row.fetch("entity_path") }
    assert_equal [[], []], result.fetch("value").values_at("unchanged", "left_out")
    assert(paths.all? { |path| STORE.read(live(*path)) == { "schema_version" => 1 } })
    assert_equal paths.length, result.fetch("affected").length

    @model.undo
    assert(paths.none? { |path| STORE.marks?(live(*path)) })
    @model.redo
    assert(paths.all? { |path| STORE.marks?(live(*path)) })
  end

  def test_assign_on_a_marked_entity_is_unchanged_and_keeps_its_user_data
    STORE.write(live(5), "schema_version" => 1, "user_data" => { "firm.note" => "kept" })
    result = assign([5])
    assert_equal %w[completed none], result.values_at("status", "effect"), result.inspect
    assert_equal [[{ "entity_path" => [5] }], []], result.fetch("value").values_at("unchanged", "assigned")
    assert_equal({ "schema_version" => 1, "user_data" => { "firm.note" => "kept" } }, STORE.read(live(5)))
  end

  def test_clear_removes_only_the_named_mark_in_one_undo_step
    assign([5], [20], [40])
    result = clear([5], [40], [42], [20, 21])
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    value = result.fetch("value")
    assert_equal [[5], [40]], value.fetch("cleared").map { |row| row.fetch("entity_path") }
    assert_equal [{ "entity_path" => [42] }], value.fetch("unchanged")
    inherited = value.fetch("left_out").first
    assert_equal [[20, 21], "shading.inherited"], inherited.values_at("entity_path", "code")
    assert_match(/"Neighbour" at path \[20\]/, inherited.fetch("message"))
    refute STORE.marks?(live(5))
    assert STORE.marks?(live(20))

    @model.undo
    assert STORE.marks?(live(5)) && STORE.marks?(live(40))
    @model.redo
    refute STORE.marks?(live(5)) || STORE.marks?(live(40))
  end

  # Every refusal rule, each named alone: it refuses with its code and writes nothing.
  def test_every_refusal_row_carries_its_code_and_writes_nothing
    classify([100, 102])
    rows = {
      [6] => "target.wrong_kind",
      [40, 41] => "target.shared_definition",
      [60, 62] => "target.shared_definition",
      [100, 102] => "shading.face_classified",
      [100] => "shading.zone_target",
      [70] => "shading.zone_target",
      [80] => "target.wrong_kind",
      [80, 81] => "target.wrong_kind",
      [85] => "target.wrong_kind",
      [90] => "shading.cutting_component",
      [90, 91] => "shading.cutting_component",
      [100, 130] => "shading.cutting_component",
      [100, 130, 131] => "shading.cutting_component",
      [100, 120] => "target.locked",
      [100, 120, 121] => "target.locked",
      [45] => "target.locked"
    }
    rows.each do |path, code|
      result = assign(path)
      assert_equal ["refused", code, "none"], result.values_at("status", "code", "effect"), path.inspect
      assert_equal [{ "entity_path" => path, "code" => code }],
                   result.dig("detail", "left_out").map { |row| row.slice("entity_path", "code") }
    end
    assert_empty list.fetch("marked")
  end

  # A Window Unit claims nothing, so the claim check never refuses it; it is a cutting component, as Windows
  # writes every Unit's definition, and that refuses it and its pane Faces.
  def test_a_window_unit_is_refused_as_a_cutting_component_not_as_claimed
    refute PhComposer::Records::EntityStore.claimed?([live(90)])
    assert_equal "shading.cutting_component", assign([90])["code"]
  end

  def test_a_face_in_a_component_placed_once_takes_the_mark_and_one_placed_three_times_does_not
    assert_equal [[50, 51]], assign([50, 51]).dig("value", "assigned").map { |row| row.fetch("entity_path") }
    assert_equal "target.shared_definition", assign([42, 41])["code"]
  end

  def test_a_mixed_command_applies_what_it_can_and_names_what_it_left_out
    classify([100, 102])
    result = assign([5], [6], [100, 102], [100, 101])
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    value = result.fetch("value")
    assert_equal [[5], [100, 101]], value.fetch("assigned").map { |row| row.fetch("entity_path") }
    assert_equal [[[6], "target.wrong_kind"], [[100, 102], "shading.face_classified"]],
                 value.fetch("left_out").map { |row| row.values_at("entity_path", "code") }
    refute STORE.marks?(live(100, 102))
  end

  def test_every_target_left_out_refuses_with_the_first_code_and_the_whole_result
    result = assign([6], [100])
    assert_equal %w[refused target.wrong_kind none], result.values_at("status", "code", "effect")
    assert_match(/None of the 2 entities can take the mark/, result.fetch("message"))
    assert_equal 2, result.dig("detail", "left_out").length
  end

  def test_a_stale_path_or_revision_refuses_the_whole_command
    { [999] => "target.not_found", [5, 1] => "target.not_found", [100, 999] => "target.not_found",
      [7] => "target.ambiguous" }.each do |path, code|
      result = assign([5], path)
      assert_equal ["refused", code], result.values_at("status", "code"), path.inspect
    end
    stale = API.invoke(:context => @context, :name => "#{SH::FEATURE_ID}.assign",
                       :params => { "targets" => [{ "entity_path" => [5] }] },
                       :request => { "sequence" => (@sequence += 1), "expected_revision" => @session.revision - 1 })
    assert_equal %w[refused revision.stale], stale.values_at("status", "code")
    refute STORE.marks?(live(5))
  end

  def test_an_unreadable_mark_still_marks_lists_and_clears
    live(5).set_attribute(STORE.dictionary, STORE.key, "{not json")
    assert_equal [{ "entity_path" => [5], "kind" => "face", "readable" => false }], list.fetch("marked")
    assert_equal [{ "display_name" => "Shading", "face_count" => 1 }],
                 list.fetch("components").map { |row| row.slice("display_name", "face_count") }
    assert_equal [{ "entity_path" => [5] }], assign([5]).dig("value", "unchanged")
    assert_equal [{ "entity_path" => [5] }], clear([5]).dig("value", "cleared")
    refute STORE.marks?(live(5))
  end

  def test_list_groups_shading_faces_by_the_name_they_export_under
    assign([5], [20], [40], [42], [43], [100, 101], [100, 110])
    value = list
    assert_equal [[5], [20], [40], [42], [43], [100, 101], [100, 110]],
                 value.fetch("marked").map { |row| row.fetch("entity_path") }
    rows = value.fetch("components").to_h { |row| [row.fetch("display_name"), row.fetch("face_count")] }
    assert_equal({ "Fin" => 1, "Louvre" => 3, "Neighbour" => 2, "Shading" => 1, "Zone A Shading" => 1 }, rows)
    # Each fixture Face is the stub's default half-square inch, once per placement.
    louvre = value.fetch("components").find { |row| row.fetch("display_name") == "Louvre" }
    assert_in_delta 3 * 0.5 * (0.0254**2), louvre.fetch("area_m2"), 1e-12
  end

  # A mark inside a cutting component stays listed for clear to find; its Face counts in no component.
  def test_list_names_a_mark_inside_a_cutting_component_and_counts_no_face_there
    STORE.write(live(100, 130, 131), SH::Mark::RECORD)
    value = list
    # The cutting definition is placed at 130 and 24, so its one marked Face is listed per placement.
    assert_equal [[20, 24, 131], [100, 130, 131]], value.fetch("marked").map { |row| row.fetch("entity_path") }
    assert_empty value.fetch("components")
    assert_equal "target.shared_definition", clear([100, 130, 131])["code"]
  end

  def test_list_refuses_a_shading_face_under_a_singular_transform
    flat = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(96)]), :name => "Flat")
    @model.entities << Sketchup::ComponentInstance.new(95, flat,
                                                       :transformation => Geom::Transformation.scaling(0, 1, 1))
    STORE.write(live(95), SH::Mark::RECORD)
    result = API.query(:context => @context, :name => "#{SH::FEATURE_ID}.list", :params => {})
    assert_equal %w[refused geometry.invalid], result.values_at("status", "code")
  end

  # An instance's own name comes before its definition's.
  def test_an_instance_named_on_its_own_exports_under_that_name
    assign([44])
    assert_equal [["Louvre East", 1]], list.fetch("components").map { |row|
      row.values_at("display_name", "face_count")
    }
  end

  def test_clear_leaves_out_a_mark_behind_a_lock_or_shared_storage
    STORE.write(live(100, 120, 121), SH::Mark::RECORD)
    STORE.write(live(40, 41), SH::Mark::RECORD)
    result = clear([100, 120, 121], [40, 41])
    assert_equal %w[refused target.locked], result.values_at("status", "code")
    assert_equal %w[target.locked target.shared_definition], result.dig("detail", "left_out").map { |row| row["code"] }
    assert STORE.marks?(live(100, 120, 121)) && STORE.marks?(live(40, 41))
  end

  # A claimed entity anywhere above a Face wins over a mark, its own or a nearer container's.
  def test_a_mark_inside_a_space_never_makes_a_shading_face
    STORE.write(live(80, 81), SH::Mark::RECORD)
    STORE.write(live(80, 82), SH::Mark::RECORD)
    assert_empty list.fetch("components")
  end

  # Clear names shading.inherited only where the mark above would reach: not a Zone, a cutting component or
  # anything inside them, which stay unchanged.
  def test_clear_reports_inherited_only_where_the_mark_above_reaches
    STORE.write(live(70), SH::Mark::RECORD)
    STORE.write(live(20), SH::Mark::RECORD)
    result = clear([70, 71], [70, 71, 72], [20, 24], [20, 24, 131], [70, 73])
    value = result.fetch("value")
    assert_equal [[70, 71], [70, 71, 72], [20, 24], [20, 24, 131]],
                 value.fetch("unchanged").map { |row| row.fetch("entity_path") }
    left_out = value.fetch("left_out").map { |row| row.values_at("entity_path", "code") }
    assert_equal [[[70, 73], "shading.inherited"]], left_out
  end

  # The Group's own Face beside the Zone stays shading; the Zone's and the Space's Faces never are.
  def test_a_mark_above_a_zone_or_a_space_never_reaches_its_faces
    STORE.write(live(70), SH::Mark::RECORD)
    STORE.write(live(85), SH::Mark::RECORD)
    assert_equal [["Shading", 1]], list.fetch("components").map { |row| row.values_at("display_name", "face_count") }
  end

  def test_selection_says_what_each_action_would_do_and_ignores_other_entities
    assign([20])
    classify([100, 102])
    @model.selection.add([live(5), live(6), live(20)])
    value = selection
    rows = value.fetch("entities").map do |row|
      [row.dig("reference", "entity_path"), row.dig("assign", "outcome"), row.dig("clear", "outcome")]
    end
    assert_equal [[[5], "assigned", "unchanged"], [[20], "unchanged", "cleared"]], rows
    assert_equal [1, [{ "persistent_id" => 6, "type" => "Edge" }]], value.values_at("ignored_total", "ignored")

    @model.selection.clear
    @model.active_path = [@zone]
    @model.selection.add([live(100, 102)])
    row = selection.fetch("entities").first
    assert_equal [[100, 102], "left_out", "shading.face_classified"],
                 [row.dig("reference", "entity_path"), row.dig("assign", "outcome"), row.dig("assign", "code")]
  end

  private

  def zone(persistent_id, name, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    PhComposer::Zones::ZONE_STORE.write(group,
                                        "id" => "zon_#{persistent_id.to_s.rjust(12, 'A')}", "schema_version" => 1,
                                        "name" => name, "building_segment" => "Building", "level" => nil,
                                        "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    group
  end

  def locked_louvre(definition)
    instance = Sketchup::ComponentInstance.new(45, definition)
    instance.locked = true
    instance
  end

  def live(*path)
    path.reduce(nil) do |parent, id|
      entities = if parent.nil? then @model.entities
                 elsif parent.is_a?(Sketchup::Group) then parent.entities
                 else parent.definition.entities
                 end
      entities.to_a.find { |entity| entity.persistent_id == id }
    end
  end

  # Classifies a Zone Face as a Wall through Zones' own action, as a user would.
  def classify(path)
    host = API.query(:context => @context, :name => "ph_composer.zones.faces.host_context",
                     :params => { "paths" => [path] })
    reference = host.dig("value", "faces", 0, "reference")
    result = API.invoke(:context => @context, :name => "ph_composer.zones.faces.classify",
                        :params => { "faces" => [reference],
                                     "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" } } },
                        :request => { "sequence" => (@sequence += 1), "expected_revision" => @session.revision })
    assert_equal "committed", result["effect"], result.inspect
  end

  def assign(*paths)
    invoke("assign", "targets" => paths.map { |path| { "entity_path" => path } })
  end

  def clear(*paths)
    invoke("clear", "targets" => paths.map { |path| { "entity_path" => path } })
  end

  def list
    read("list")
  end

  def selection
    read("selection")
  end

  def read(name)
    result = API.query(:context => @context, :name => "#{SH::FEATURE_ID}.#{name}", :params => {})
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{SH::FEATURE_ID}.#{name}", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
