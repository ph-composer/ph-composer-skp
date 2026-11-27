# frozen_string_literal: true

require_relative "test_helper"

# Piping groups through their registered actions (context/CONTRACTS.md, "Hot water piping"): make wraps loose lines
# in a new group in one Undo step and refuses lines it cannot wrap, the selection read says which, link and unlink
# are guarded, a group inside a Zone or another Piping group refuses, a pasted copy reads copied, and a Hot Water
# System delete moves or refuses the groups naming it.
class PipingGroupTest < PhComposerTestCase
  API = PhComposer::API
  P = PhComposer::Piping
  STORE = P::Group::STORE
  PREFIX = "ph_composer.piping.groups"
  SYSTEMS = "ph_composer.mechanical.hot_water_systems"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @hws1 = invoke("#{SYSTEMS}.create", "values" => { "name" => "HWS-1" }).dig("value", "id")
    @hws2 = invoke("#{SYSTEMS}.create", "values" => { "name" => "HWS-2" }).dig("value", "id")
  end

  def test_make_wraps_loose_lines_in_a_group_linked_to_the_system_in_one_undo_step
    lines = [801, 802, 803].map { |id| edge(id) }
    lines.each { |line| @model.entities << line }
    lines.first.set_attribute("user.notes", "kept", 1)
    steps = @model.operations.length
    result = make(lines.map { |line| [line.persistent_id] }, @hws1)
    assert_equal "committed", result["effect"], result.inspect
    id = result.dig("value", "group_id")
    assert_match(/\Appg_[A-Za-z0-9]{12}\z/, id)
    groups = @model.entities.to_a.select { |entity| STORE.marks?(entity) }
    assert_equal 1, groups.length
    assert_equal({ "id" => id, "schema_version" => 1, "hot_water_system_id" => @hws1, "user_data" => {},
                   "extension_data" => {} }, STORE.read(groups.first))
    assert_equal [lines, 1, nil], [groups.first.entities.to_a, lines.first.get_attribute("user.notes", "kept"),
                                   @model.active_path]
    assert_equal [["Make Piping Group", true, :committed]], @model.operations.drop(steps)
    assert_equal [["Piping group 1", 0], "Piping group 1"],
                 [result["value"].values_at("name", "removed_faces"), groups.first.name]
    assert_equal [{ "group_id" => id, "group_path" => [groups.first.persistent_id] }, 0, false, [], nil],
                 all.first.values_at("reference", "pipe_count", "copied", "findings", "write_refusal")
    assert_equal %w[refused target.not_found], make([[801]], "hws_ZZZZZZZZZZZZ").values_at("status", "code")
    @model.undo
    assert(@model.entities.to_a.none? { |entity| STORE.marks?(entity) })
    assert_equal [801, 802, 803], @model.entities.to_a.grep(Sketchup::Edge).map(&:persistent_id)
  end

  # A planar loop SketchUp filled with a Face still makes a group: Make erases the Faces its lines alone close in its
  # own operation, says how many, and one Undo brings back the Face and the loose lines. Nothing else is touched.
  def test_make_erases_the_faces_its_lines_close_in_the_same_undo_step
    loop_lines = [811, 812, 813, 814].map { |id| edge(id) }
    filled = Sketchup::Face.new(819, :edges => loop_lines)
    other = Sketchup::Face.new(829, :edges => [edge(821), edge(822)])
    [*loop_lines, filled, other, *other.edges].each { |entity| @model.entities << entity }
    first = piping_group(520, "ppg_CCCCCCCCCCCC", @hws1, [edge(521)])
    first.name = "Piping group 1"
    @model.entities << first
    steps = @model.operations.length
    @model.selection.add(loop_lines + [filled])
    assert_equal [nil, nil], make_refusals, "a selected Face its lines close is no obstacle"
    result = make(loop_lines.map { |line| [line.persistent_id] }, @hws1)
    assert_equal [["Piping group 2", 1], [["Make Piping Group", true, :committed]]],
                 [result["value"].values_at("name", "removed_faces"), @model.operations.drop(steps)]
    made = all_groups.find { |group| group.name == "Piping group 2" }
    assert_equal [[811, 812, 813, 814], [], [other]], [made.entities.map(&:persistent_id),
                                                       loop_lines.flat_map(&:faces), other.edges.first.faces]
    assert_equal [520, 821, 822, 829, made.persistent_id].sort, @model.entities.map(&:persistent_id).sort
    @model.undo
    assert_equal [520, 811, 812, 813, 814, 819, 821, 822, 829], @model.entities.map(&:persistent_id).sort
    restored = @model.entities.to_a.find { |entity| entity.persistent_id == 811 }
    assert_equal [819], restored.faces.map(&:persistent_id)
  end

  # A Face with any line outside the selection still refuses, naming the fix, and writes nothing.
  def test_make_refuses_a_face_bounded_by_an_unselected_line_and_names_the_fix
    loop_lines = [811, 812, 813, 814].map { |id| edge(id) }
    filled = Sketchup::Face.new(819, :edges => loop_lines)
    [*loop_lines, filled].each { |entity| @model.entities << entity }
    result = make(loop_lines.first(3).map { |line| [line.persistent_id] }, @hws1)
    assert_equal %w[refused target.wrong_kind], result.values_at("status", "code")
    assert_equal "A selected line bounds a Face drawn with lines outside the selection; erase the Face, keep its " \
                 "lines, then Make Piping group again. Nothing was written.", result["message"]
    assert_equal [[], [811, 812, 813, 814, 819]], [all_groups, @model.entities.map(&:persistent_id)]
  end

  # Each refusal writes nothing: no group, and every line where it was.
  def test_make_refuses_lines_it_cannot_wrap_and_writes_nothing
    bounding = edge(891)
    face = Sketchup::Face.new(890, :edges => [bounding, edge(892)])
    plain = Sketchup::Group.new(600, Sketchup::Entities.new([edge(601)]))
    inner = Sketchup::Group.new(110, Sketchup::Entities.new([edge(111)]))
    zone = zone_group(100, [edge(101), inner])
    piping = piping_group(520, "ppg_CCCCCCCCCCCC", @hws1, [edge(521)])
    ducting = Sketchup::Group.new(530, Sketchup::Entities.new([edge(531)]))
    PhComposer::Ducting::Group::STORE.write(ducting, PhComposer::Ducting::Group.new_record("dcg_AAAAAAAAAAAA", nil))
    locked = Sketchup::Group.new(540, Sketchup::Entities.new([edge(541)])).tap { |group| group.locked = true }
    shared = Sketchup::Entities.new([edge(551)])
    copies = [550, 560].map { |id| Sketchup::Group.new(id, shared) }
    component = @model.definitions.add("Riser").tap { |definition| definition.entities << edge(571) }
    instance = @model.entities.add_instance(component, Geom::Transformation.new)
    entities = [edge(801), face, bounding, plain, zone, piping, ducting, locked, *copies]
    entities.each { |entity| @model.entities << entity }
    { [[], nil] => "params.invalid", [[[890]], nil] => "target.wrong_kind", [[[891]], nil] => "target.wrong_kind",
      [[[999]], nil] => "target.not_found", [[[801], [600, 601]], nil] => "target.wrong_hierarchy",
      [[[600, 601]], nil] => "target.edit_path_changed", [[[100, 101]], [zone]] => "piping.group_in_zone",
      [[[100, 110, 111]], [zone, inner]] => "piping.group_in_zone", [[[520, 521]], [piping]] => "piping.group_nested",
      [[[530, 531]], [ducting]] => "target.wrong_hierarchy", [[[540, 541]], [locked]] => "target.locked",
      [[[550, 551]], [copies.first]] => "target.shared_definition",
      [[[instance.persistent_id, 571]], [instance]] => "target.wrong_hierarchy" }.each do |(paths, open), code|
      @model.active_path = open
      assert_equal ["refused", code], make(paths, @hws1).values_at("status", "code"), paths.inspect
    end
    @model.active_path = nil
    assert_equal [piping], all_groups
    assert_equal [[601], [101, 110], [521], [531]], [plain, zone, piping, ducting].map { |group|
      group.entities.map(&:persistent_id)
    }
  end

  # In an open plain Group the new group is made inside it, where the lines are, and the Group stays open.
  def test_make_in_an_open_plain_group_wraps_the_lines_there
    plain = Sketchup::Group.new(600, Sketchup::Entities.new([edge(601), edge(602)]),
                                {}, :transformation => Geom::Transformation.translation([100, 0, 0]))
    @model.entities << plain
    @model.active_path = [plain]
    assert_equal "committed", make([[600, 601], [600, 602]], @hws1)["effect"]
    made = plain.entities.to_a.find { |entity| STORE.marks?(entity) }
    assert_equal [[601, 602], [plain]], [made.entities.map(&:persistent_id), Array(@model.active_path)]
    assert_equal [[600, made.persistent_id]], all.map { |row| row.fetch("path") }
  end

  # The gesture limit is the handler's, so 251 lines refuse with its code and 250 are made.
  def test_make_takes_250_lines_and_refuses_251_as_too_large
    lines = (1000..1250).map { |id| edge(id) }
    lines.each { |line| @model.entities << line }
    paths = lines.map { |line| [line.persistent_id] }
    assert_equal %w[refused gesture.too_large], make(paths, @hws1).values_at("status", "code")
    assert_equal "committed", make(paths.first(250), @hws1)["effect"]
    assert_equal [250], all_groups.map { |group| group.entities.count }
  end

  # The selection read answers what make would meet over the selection, so the panel offers it only when it can run.
  def test_the_selection_read_says_whether_its_lines_make_a_group
    lines = [801, 802].map { |id| edge(id) }
    piping = piping_group(520, "ppg_CCCCCCCCCCCC", @hws1, [edge(521)])
    face = Sketchup::Face.new(890)
    [*lines, piping, face].each { |entity| @model.entities << entity }
    assert_equal ["params.invalid"] * 2, make_refusals
    @model.selection.add(lines)
    assert_equal [nil, nil], make_refusals
    assert_equal "committed", make(selection_paths, @hws2)["effect"]
    @model.selection.add([face])
    assert_equal ["target.wrong_kind"] * 2, make_refusals
    @model.selection.clear
    @model.selection.add([face])
    assert_equal ["target.wrong_kind"] * 2, make_refusals, "a Face alone is no line either"
    @model.selection.clear
    @model.active_path = [piping]
    @model.selection.add(piping.entities.to_a)
    assert_equal ["piping.group_nested"] * 2, make_refusals
  end

  def test_link_and_unlink_are_guarded_and_each_one_undo_step
    group = piping_group(500, "ppg_AAAAAAAAAAAA", @hws1)
    @model.entities << group
    stale = target(group).merge("expected_values" => { "hot_water_system_id" => @hws2 })
    assert_equal %w[refused target.changed none],
                 invoke("#{PREFIX}.link", "targets" => [stale], "hot_water_system_id" => @hws2)
                   .values_at("status", "code", "effect")
    assert_equal "committed", invoke("#{PREFIX}.link", "targets" => [target(group)],
                                                       "hot_water_system_id" => @hws2)["effect"]
    assert_equal @hws2, system_of(500)
    assert_equal "committed", invoke("#{PREFIX}.unlink", "targets" => [target(live(500))])["effect"]
    assert_nil system_of(500)
    @model.undo
    assert_equal @hws2, system_of(500)
  end

  def test_a_group_inside_a_zone_or_another_piping_group_refuses
    in_zone = piping_group(510, "ppg_BBBBBBBBBBBB", @hws1)
    zone = Sketchup::Group.new(100, Sketchup::Entities.new([in_zone]))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    inner = piping_group(521, "ppg_DDDDDDDDDDDD", @hws1)
    outer = piping_group(520, "ppg_CCCCCCCCCCCC", @hws1, [inner])
    @model.entities << zone << outer
    { [100, 510] => ["ppg_BBBBBBBBBBBB", "piping.group_in_zone"],
      [520, 521] => ["ppg_DDDDDDDDDDDD", "piping.group_nested"] }.each do |path, (id, code)|
      reference = { "group_id" => id, "group_path" => path }
      assert_equal ["refused", code], invoke("#{PREFIX}.link", "targets" => [{ "reference" => reference }],
                                                               "hot_water_system_id" => @hws2)
        .values_at("status", "code")
      assert_equal [code], all.find { |row| row.fetch("path") == path }.fetch("findings")
    end
    assert_equal @hws1, STORE.read(in_zone).fetch("hot_water_system_id")
  end

  # Make moves no edit path, so a Model SketchUp is not showing takes it, as it takes Make Zone.
  def test_make_groups_lines_in_a_model_sketchup_is_not_showing
    @model.entities << edge(801)
    Sketchup.active_model = Sketchup::Model.new
    assert_equal "committed", make([[801]], @hws1)["effect"]
    assert_equal [[801]], @model.entities.to_a.select { |entity| STORE.marks?(entity) }.map { |group|
      group.entities.map(&:persistent_id)
    }
  end

  # A group row's write_refusal is what link meets, in its order: nested, the path's own, then in a Zone.
  def test_a_group_row_shows_the_placement_refusal_a_write_meets
    in_zone = piping_group(510, "ppg_BBBBBBBBBBBB", @hws1)
    zone = Sketchup::Group.new(100, Sketchup::Entities.new([in_zone]))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    @model.entities << zone << piping_group(520, "ppg_CCCCCCCCCCCC", @hws1,
                                            [piping_group(521, "ppg_DDDDDDDDDDDD", @hws1)])
    { [100, 510] => "piping.group_in_zone", [520, 521] => "piping.group_nested" }.each do |path, code|
      assert_equal code, all.find { |row| row.fetch("path") == path }.dig("write_refusal", "code")
    end
    zone.locked = true
    row = all.find { |entry| entry.fetch("path") == [100, 510] }
    locked = invoke("#{PREFIX}.link", "targets" => [row.slice("reference")], "hot_water_system_id" => @hws2)
    assert_equal %w[target.locked target.locked], [row.dig("write_refusal", "code"), locked["code"]]
  end

  def test_a_pasted_copy_reads_copied_and_refuses_a_write_through_its_shared_storage
    group = piping_group(530, "ppg_EEEEEEEEEEEE", @hws1)
    copy = Sketchup::Group.new(531, group.entities)
    STORE.write(copy, STORE.read(group))
    @model.entities << group << copy
    rows = all
    assert_equal [true, true], rows.map { |row| row.fetch("copied") }
    assert_equal ["target.shared_definition"] * 2, rows.map { |row| row.dig("write_refusal", "code") }
    assert_equal %w[refused target.shared_definition],
                 invoke("#{PREFIX}.link", "targets" => [target(copy)], "hot_water_system_id" => @hws2)
                   .values_at("status", "code")
  end

  def test_deleting_a_system_a_group_names_refuses_and_a_replacement_retargets_it_in_one_undo_step
    @model.entities << piping_group(540, "ppg_FFFFFFFFFFFF", @hws1)
    assert_equal %w[refused reference.in_use], invoke("#{SYSTEMS}.delete", "id" => @hws1).values_at("status", "code")
    assert_equal "committed", invoke("#{SYSTEMS}.delete", "id" => @hws1, "replacement_id" => @hws2)["effect"]
    assert_equal @hws2, system_of(540)
    @model.undo
    assert_equal @hws1, system_of(540)
    assert_equal "committed", invoke("#{SYSTEMS}.delete", "id" => @hws1, "replacement_id" => nil)["effect"]
    assert_nil system_of(540)
  end

  def test_a_locked_group_strands_the_system_delete
    @model.entities << piping_group(550, "ppg_GGGGGGGGGGGG", @hws1).tap { |group| group.locked = true }
    refusal = invoke("#{SYSTEMS}.delete", "id" => @hws1, "replacement_id" => @hws2)
    assert_equal %w[refused reference.in_use none], refusal.values_at("status", "code", "effect")
    assert_equal @hws1, system_of(550)
  end

  def test_a_group_record_with_no_id_still_refuses_the_system_delete_by_its_path
    group = Sketchup::Group.new(560, Sketchup::Entities.new([]))
    STORE.write(group, "schema_version" => 1, "hot_water_system_id" => @hws1)
    @model.entities << group
    refusal = invoke("#{SYSTEMS}.delete", "id" => @hws1)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code")
    assert_match(/\[560\] still refers/, refusal["message"])
  end

  private

  def edge(persistent_id)
    Sketchup::Edge.new(persistent_id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, persistent_id, 0))
  end

  def zone_group(persistent_id, children)
    zone = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    zone
  end

  def make(edge_paths, system_id)
    invoke("#{PREFIX}.make", "edge_paths" => edge_paths, "hot_water_system_id" => system_id)
  end

  # The selected lines' paths as the selection read gives them, which is what the panel sends make.
  def selection_paths
    selection("selection_all").fetch("edges").map { |row| row.fetch("path") }
  end

  # The make_refusal code of the whole and the paged selection read.
  def make_refusals
    %w[selection_all selection].map { |name| selection(name).dig("make_refusal", "code") }
  end

  def selection(name)
    result = API.query(:context => @context, :name => "ph_composer.piping.pipes.#{name}")
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def all_groups
    @model.entities.to_a.select { |entity| STORE.marks?(entity) }
  end

  def piping_group(persistent_id, id, system_id, children = [])
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    STORE.write(group, P::Group.new_record(id, system_id))
    group
  end

  def target(group)
    record = STORE.read(group)
    { "reference" => { "group_id" => record.fetch("id"), "group_path" => [group.persistent_id] },
      "expected_values" => P::Group.values(record) }
  end

  def live(persistent_id)
    @model.entities.to_a.find { |entity| entity.persistent_id == persistent_id }
  end

  def system_of(persistent_id)
    STORE.read(live(persistent_id)).fetch("hot_water_system_id")
  end

  def all
    result = API.query(:context => @context, :name => "#{PREFIX}.all")
    assert_equal "completed", result["status"], result.inspect
    result.dig("value", "groups")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
