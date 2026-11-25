# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# Ducting groups through their registered actions (context/CONTRACTS.md, "ERV ducting"): create opens a new group at
# the root in one Undo step, link and unlink are guarded, a group inside a Zone or another Ducting group refuses, a
# pasted copy reads copied and keeps its Ventilator, and a Ventilator delete moves, clears or refuses the groups
# naming it beside the Zones it serves.
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

  def test_create_adds_one_open_group_at_the_root_linked_to_the_ventilator_in_one_undo_step
    result = invoke("#{PREFIX}.create", "ventilator_id" => @erv1)
    assert_equal "committed", result["effect"], result.inspect
    id = result.dig("value", "group_id")
    assert_match(/\Adcg_[A-Za-z0-9]{12}\z/, id)
    groups = @model.entities.to_a.select { |entity| STORE.marks?(entity) }
    assert_equal 1, groups.length
    assert_equal({ "id" => id, "schema_version" => 1, "ventilator_id" => @erv1, "user_data" => {},
                   "extension_data" => {} }, STORE.read(groups.first))
    assert_equal [groups.first], Array(@model.active_path)
    assert_equal [{ "group_id" => id, "group_path" => [groups.first.persistent_id] }, 0, false, [], nil],
                 all.first.values_at("reference", "duct_count", "copied", "findings", "write_refusal")
    assert_equal %w[refused target.not_found], invoke("#{PREFIX}.create", "ventilator_id" => "vnt_ZZZZZZZZZZZZ")
      .values_at("status", "code")
    @model.undo
    assert(@model.entities.to_a.none? { |entity| STORE.marks?(entity) })
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    kind = PhComposer::Mechanical::VENTILATOR_KIND
    engine.kind(kind).store.write(@model, engine.find(kind, @erv2).merge("schema_version" => 9))
    assert_equal %w[refused record.unreadable], invoke("#{PREFIX}.create", "ventilator_id" => @erv2)
      .values_at("status", "code")
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
