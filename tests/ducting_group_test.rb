# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# Ducting groups through their registered actions (context/CONTRACTS.md, "ERV ducting"): make wraps loose lines in a
# new group in one Undo step and refuses lines it cannot wrap, the selection read says which, link and unlink are
# guarded, a group inside a Zone or another Ducting group refuses, a pasted copy reads copied and keeps its
# Ventilator, and a Ventilator delete moves, clears or refuses the groups naming it beside the Zones it serves.
class DuctingGroupTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  D = PhComposer::Ducting
  STORE = D::Group::STORE
  PREFIX = "ph_composer.ducting.groups"
  VENTILATORS = "ph_composer.mechanical.ventilators"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @erv1 = invoke("#{VENTILATORS}.create", "values" => { "name" => "ERV-1" }).dig("value", "id")
    @erv2 = invoke("#{VENTILATORS}.create", "values" => { "name" => "ERV-2" }).dig("value", "id")
  end

  def test_make_wraps_loose_lines_in_a_group_linked_to_the_ventilator_in_one_undo_step
    lines = [801, 802].map { |id| edge(id) }
    lines.each { |line| @model.entities << line }
    lines.last.set_attribute("user.notes", "kept", 2)
    steps = @model.operations.length
    result = make([[801], [802]], @erv1)
    assert_equal "committed", result["effect"], result.inspect
    id = result.dig("value", "group_id")
    assert_match(/\Adcg_[A-Za-z0-9]{12}\z/, id)
    groups = @model.entities.to_a.select { |entity| STORE.marks?(entity) }
    assert_equal 1, groups.length
    assert_equal [["Ducting group 1", 0], "Ducting group 1"],
                 [result["value"].values_at("name", "removed_faces"), groups.first.name]
    assert_equal({ "id" => id, "schema_version" => 1, "ventilator_id" => @erv1, "user_data" => {},
                   "extension_data" => {} }, STORE.read(groups.first))
    assert_equal [lines, 2, nil], [groups.first.entities.to_a, lines.last.get_attribute("user.notes", "kept"),
                                   @model.active_path]
    assert_equal [["Make Ducting Group", true, :committed]], @model.operations.drop(steps)
    assert_equal [{ "group_id" => id, "group_path" => [groups.first.persistent_id] }, 0, false, [], nil],
                 all.first.values_at("reference", "duct_count", "copied", "findings", "write_refusal")
    @model.undo
    assert(@model.entities.to_a.none? { |entity| STORE.marks?(entity) })
    assert_equal [801, 802], @model.entities.to_a.grep(Sketchup::Edge).map(&:persistent_id)
    assert_equal %w[refused target.not_found], make([[801]], "vnt_ZZZZZZZZZZZZ").values_at("status", "code")
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    kind = PhComposer::Mechanical::VENTILATOR_KIND
    engine.kind(kind).store.write(@model, engine.find(kind, @erv2).merge("schema_version" => 9))
    assert_equal %w[refused record.unreadable], make([[801]], @erv2).values_at("status", "code")
    Sketchup.active_model = Sketchup::Model.new
    assert_equal "committed", make([[801]], @erv1)["effect"]
  end

  # Each refusal writes nothing: no group, and every line where it was.
  def test_make_refuses_lines_it_cannot_wrap_and_writes_nothing
    face = Sketchup::Face.new(890)
    plain = Sketchup::Group.new(600, Sketchup::Entities.new([edge(601)]))
    zone = Sketchup::Group.new(100, Sketchup::Entities.new([edge(101)]))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_BBBBBBBBBBBB", "schema_version" => 1, "name" => "Zone B",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    ducting = ducting_group(520, "dcg_CCCCCCCCCCCC", @erv1, [edge(521)])
    piping = Sketchup::Group.new(530, Sketchup::Entities.new([edge(531)]))
    PhComposer::Piping::Group::STORE.write(piping, PhComposer::Piping::Group.new_record("ppg_AAAAAAAAAAAA", nil))
    [edge(801), face, plain, zone, ducting, piping].each { |entity| @model.entities << entity }
    { [[], nil] => "params.invalid", [[[890]], nil] => "target.wrong_kind",
      [[[801], [600, 601]], nil] => "target.wrong_hierarchy", [[[600, 601]], nil] => "target.edit_path_changed",
      [[[100, 101]], [zone]] => "ducting.group_in_zone", [[[520, 521]], [ducting]] => "ducting.group_nested",
      [[[530, 531]], [piping]] => "target.wrong_hierarchy" }.each do |(paths, open), code|
      @model.active_path = open
      assert_equal ["refused", code], make(paths, @erv1).values_at("status", "code"), paths.inspect
    end
    @model.active_path = nil
    paths = (1000..1250).map { |id| edge(id).tap { |line| @model.entities << line }.persistent_id }.map { |id| [id] }
    assert_equal %w[refused gesture.too_large], make(paths, @erv1).values_at("status", "code"), "the handler's limit"
    assert_equal [ducting], @model.entities.to_a.select { |entity| STORE.marks?(entity) }
    assert_equal [[601], [101], [521], [531]], [plain, zone, ducting, piping].map { |group|
      group.entities.map(&:persistent_id)
    }
  end

  def test_the_selection_read_says_whether_its_lines_make_a_group
    lines = [801, 802].map { |id| edge(id) }
    ducting = ducting_group(520, "dcg_CCCCCCCCCCCC", @erv1, [edge(521)])
    [*lines, ducting].each { |entity| @model.entities << entity }
    assert_equal "params.invalid", make_refusal
    @model.selection.add(lines)
    assert_nil make_refusal
    @model.selection.add([ducting])
    assert_equal "target.wrong_kind", make_refusal
    @model.selection.clear
    @model.active_path = [ducting]
    @model.selection.add(ducting.entities.to_a)
    assert_equal "ducting.group_nested", make_refusal
  end

  def test_link_and_unlink_are_guarded_and_each_one_undo_step
    @model.entities << ducting_group(500, "dcg_AAAAAAAAAAAA", @erv1)
    stale = target(live(500)).merge("expected_values" => { "ventilator_id" => @erv2 })
    assert_equal %w[refused target.changed none],
                 invoke("#{PREFIX}.link", "targets" => [stale], "ventilator_id" => @erv2)
                   .values_at("status", "code", "effect")
    assert_equal "committed", invoke("#{PREFIX}.link", "targets" => [target(live(500))],
                                                       "ventilator_id" => @erv2)["effect"]
    assert_equal @erv2, ventilator_of(500)
    assert_equal "committed", invoke("#{PREFIX}.unlink", "targets" => [target(live(500))])["effect"]
    assert_nil ventilator_of(500)
    @model.undo
    assert_equal @erv2, ventilator_of(500)
  end

  def test_a_group_inside_a_zone_or_another_ducting_group_refuses
    in_zone = ducting_group(510, "dcg_BBBBBBBBBBBB", @erv1)
    zone = Sketchup::Group.new(100, Sketchup::Entities.new([in_zone]))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    inner = ducting_group(521, "dcg_DDDDDDDDDDDD", @erv1)
    @model.entities << zone << ducting_group(520, "dcg_CCCCCCCCCCCC", @erv1, [inner])
    { [100, 510] => ["dcg_BBBBBBBBBBBB", "ducting.group_in_zone"],
      [520, 521] => ["dcg_DDDDDDDDDDDD", "ducting.group_nested"] }.each do |path, (id, code)|
      reference = { "group_id" => id, "group_path" => path }
      assert_equal ["refused", code], invoke("#{PREFIX}.link", "targets" => [{ "reference" => reference }],
                                                               "ventilator_id" => @erv2)
        .values_at("status", "code")
      row = all.find { |entry| entry.fetch("path") == path }
      assert_equal [[code], code], [row.fetch("findings"), row.dig("write_refusal", "code")]
    end
    assert_equal @erv1, STORE.read(in_zone).fetch("ventilator_id")
    zone.locked = true
    row = all.find { |entry| entry.fetch("path") == [100, 510] }
    locked = invoke("#{PREFIX}.link", "targets" => [row.slice("reference")], "ventilator_id" => @erv2)
    assert_equal [["ducting.group_in_zone"], "target.locked", "target.locked"],
                 [row.fetch("findings"), row.dig("write_refusal", "code"), locked["code"]]
  end

  def test_a_pasted_copy_reads_copied_keeps_its_ventilator_and_refuses_a_write_through_its_shared_storage
    group = ducting_group(530, "dcg_EEEEEEEEEEEE", @erv1)
    copy = Sketchup::Group.new(531, group.entities)
    STORE.write(copy, STORE.read(group))
    @model.entities << group << copy
    rows = all
    assert_equal [[true, @erv1]] * 2, rows.map { |row| [row.fetch("copied"), row.dig("values", "ventilator_id")] }
    assert_equal ["target.shared_definition"] * 2, rows.map { |row| row.dig("write_refusal", "code") }
    assert_equal %w[refused target.shared_definition],
                 invoke("#{PREFIX}.link", "targets" => [target(copy)], "ventilator_id" => @erv2)
                   .values_at("status", "code")
  end

  # Zone A is served by ERV-1, and a Ducting group names it: the delete refuses, a replacement moves both the group
  # and the Zone's slot in one Undo step, and null unlinks the group and empties the slot.
  def test_a_ventilator_delete_refuses_moves_or_unlinks_the_group_beside_the_zone_it_serves
    @model.entities << served_zone << ducting_group(540, "dcg_FFFFFFFFFFFF", @erv1)
    adopt_zone_options
    serve("Zone A", @erv1)
    refusal = invoke("#{VENTILATORS}.delete", "id" => @erv1)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code")
    moved = invoke("#{VENTILATORS}.delete", "id" => @erv1, "replacement_id" => @erv2)
    assert_equal "committed", moved["effect"], moved.inspect
    assert_equal [@erv2, @erv2], [ventilator_of(540), slot("Zone A")]
    @model.undo
    assert_equal [@erv1, @erv1], [ventilator_of(540), slot("Zone A")]
    assert_equal "committed", invoke("#{VENTILATORS}.delete", "id" => @erv1, "replacement_id" => nil)["effect"]
    assert_equal [nil, nil], [ventilator_of(540), slot("Zone A")]
  end

  def test_a_ventilator_delete_with_only_a_group_naming_it_refuses_and_a_locked_group_strands_it
    @model.entities << ducting_group(550, "dcg_GGGGGGGGGGGG", @erv1)
    refusal = invoke("#{VENTILATORS}.delete", "id" => @erv1)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code")
    assert_match(/#{D::GROUP_KIND} dcg_GGGGGGGGGGGG still refers/, refusal["message"])
    live(550).locked = true
    stranded = invoke("#{VENTILATORS}.delete", "id" => @erv1, "replacement_id" => @erv2)
    assert_equal %w[refused reference.in_use none], stranded.values_at("status", "code", "effect")
    assert_match(/\A1 Ducting group\(s\) name Ventilator/, stranded["message"])
    assert_equal @erv1, ventilator_of(550)
  end

  def test_a_shared_group_strands_the_delete_and_one_with_no_id_refuses_it_by_its_path
    shared = ducting_group(560, "dcg_HHHHHHHHHHHH", @erv1)
    copy = Sketchup::Group.new(561, shared.entities)
    STORE.write(copy, STORE.read(shared))
    no_id = Sketchup::Group.new(570, Sketchup::Entities.new([]))
    STORE.write(no_id, "schema_version" => 1, "ventilator_id" => @erv2)
    @model.entities << shared << copy << no_id
    stranded = invoke("#{VENTILATORS}.delete", "id" => @erv1, "replacement_id" => @erv2)
    assert_equal %w[refused reference.in_use none], stranded.values_at("status", "code", "effect")
    assert_match(/\A2 Ducting group\(s\) name Ventilator/, stranded["message"])
    refusal = invoke("#{VENTILATORS}.delete", "id" => @erv2)
    assert_equal %w[refused reference.in_use], refusal.values_at("status", "code")
    assert_match(/\[570\] still refers/, refusal["message"])
    rows = query("ph_composer.ducting.ventilators", {}).fetch("ventilators")
    linked = rows.find { |row| row["ventilator_id"] == @erv2 }
    assert_equal [[], 0, ["Ducting group 570"], 1],
                 linked.values_at("group_names", "group_count", "blocking_group_names", "blocking_group_count"),
                 "a group whose record fails its schema but names the Ventilator blocks its delete, not unlinked"
  end

  # One schema-invalid group naming the Ventilator refuses every delete of it, beside a group the delete could move.
  def test_a_group_failing_its_schema_blocks_every_delete_beside_one_the_delete_could_unlink
    no_id = Sketchup::Group.new(571, Sketchup::Entities.new([]), :name => "DG-bad")
    STORE.write(no_id, "schema_version" => 1, "ventilator_id" => @erv1)
    @model.entities << ducting_group(572, "dcg_LLLLLLLLLLLL", @erv1) << no_id
    [{}, { "replacement_id" => @erv2 }, { "replacement_id" => nil }].each do |choice|
      refusal = invoke("#{VENTILATORS}.delete", { "id" => @erv1 }.merge(choice))
      assert_equal %w[refused reference.in_use], refusal.values_at("status", "code"), choice.inspect
    end
    assert_equal @erv1, ventilator_of(572)
    rows = query("ph_composer.ducting.ventilators", {}).fetch("ventilators")
    linked = rows.find { |row| row["ventilator_id"] == @erv1 }
    assert_equal [["Ducting group 572"], 1, ["DG-bad"], 1],
                 linked.values_at("group_names", "group_count", "blocking_group_names", "blocking_group_count")
  end

  def test_the_ventilators_read_walks_the_model_once
    @model.entities << ducting_group(573, "dcg_MMMMMMMMMMMM", @erv1, [edge(574)])
    before = @model.entities.each_count
    query("ph_composer.ducting.ventilators", {})
    assert_equal 1, @model.entities.each_count - before
  end

  def test_the_list_pages_the_occurrences_in_path_order
    @model.entities << ducting_group(580, "dcg_JJJJJJJJJJJJ", @erv1) << ducting_group(590, "dcg_KKKKKKKKKKKK", nil)
    linked = ->(page) { page.fetch("groups").map { |row| [row.fetch("path"), row.dig("values", "ventilator_id")] } }
    first = query("#{PREFIX}.list", "limit" => 1)
    assert_equal [[[[580], @erv1]], 2], [linked.call(first), first.fetch("total")]
    second = query("#{PREFIX}.list", "limit" => 1, "cursor" => first.fetch("next_cursor"))
    assert_equal [[[[590], nil]], nil], [linked.call(second), second.fetch("next_cursor")]
  end

  private

  def query(name, params)
    result = API.query(:context => @context, :name => name, :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def served_zone
    space = space_group(110, space_record("A", :number => "1", :name => "Zone A"),
                        [volume_group(120, volume_record("A"),
                                      [floor_face(130, rectangle(0, 0, 5, 5), segment_record("A"))])])
    group = Sketchup::Group.new(100, Sketchup::Entities.new([space]), :name => "Zone A")
    PhComposer::Zones::ZONE_STORE.write(group, { "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1,
                                                 "name" => "Zone A", "building_segment" => "Building",
                                                 "level" => "L1", "ground_depth_mm" => 0.0 })
    host_children([space], "zon_AAAAAAAAAAAA")
    group
  end

  def serve(name, ventilator_id)
    row = serves_rows.fetch(name)
    result = invoke("ph_composer.mechanical.serves.assign",
                    "zones" => [{ "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }],
                    "slot" => "ventilator_id", "item_id" => ventilator_id)
    assert_equal "committed", result["effect"], result.inspect
  end

  def serves_rows
    result = API.query(:context => @context, :name => "ph_composer.mechanical.serves.all")
    result.dig("value", "zones").to_h { |row| [row.fetch("name"), row] }
  end

  def slot(name)
    serves_rows.fetch(name).dig("slots", "ventilator_id")
  end

  def edge(persistent_id)
    Sketchup::Edge.new(persistent_id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, persistent_id, 0))
  end

  def make(edge_paths, ventilator_id)
    invoke("#{PREFIX}.make", "edge_paths" => edge_paths, "ventilator_id" => ventilator_id)
  end

  def make_refusal
    result = API.query(:context => @context, :name => "ph_composer.ducting.ducts.selection_all")
    assert_equal "completed", result["status"], result.inspect
    result.dig("value", "make_refusal", "code")
  end

  def ducting_group(persistent_id, id, ventilator_id, children = [])
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    STORE.write(group, D::Group.new_record(id, ventilator_id))
    group
  end

  def target(group)
    record = STORE.read(group)
    { "reference" => { "group_id" => record.fetch("id"), "group_path" => [group.persistent_id] },
      "expected_values" => D::Group.values(record) }
  end

  def live(persistent_id)
    @model.entities.to_a.find { |entity| entity.persistent_id == persistent_id }
  end

  def ventilator_of(persistent_id)
    STORE.read(live(persistent_id)).fetch("ventilator_id")
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
