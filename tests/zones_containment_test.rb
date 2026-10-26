# frozen_string_literal: true

require_relative "test_helper"
require_relative "../src/ph_composer/features/zones/install"

# Zones answers which Zone occurrence holds any drawing element at a native path, and the refusal a
# write through that path meets, from the path alone (context/CONTRACTS.md, "Geometry records and
# occurrence references"). The rule is the one Face picking uses, with any element as the leaf.
class ZonesContainmentTest < PhComposerTestCase
  Z = PhComposer::Zones
  QUARTER_TURN = [0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 500.0, 0.0, 0.0, 1.0].freeze

  def setup
    super
    PhComposer::Registry.install([Z]) unless PhComposer::Registry.installed?(Z::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
  end

  def edge(id)
    Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0))
  end

  def zone(id, persistent_id, children, segment: "Building", **options)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children), **options)
    Z::ZONE_STORE.write(group,
                        "id" => id, "schema_version" => 1, "name" => "Zone #{persistent_id}",
                        "building_segment" => segment, "level" => "L1", "ground_depth_mm" => 0.0,
                        "user_data" => {}, "extension_data" => {})
    group
  end

  def containment(*paths)
    request = PhComposer::HandlerRequest.for(@session, :owner => Z::FEATURE_ID, :name => "test.containment")
    request.query("ph_composer.zones.containment", "paths" => paths).fetch("paths")
  end

  def test_a_direct_zone_and_zones_under_translated_and_rotated_wrappers_hold_their_elements
    @model.entities << zone("zon_AAAAAAAAAAAA", 100, [edge(102)])
    moved = Sketchup::Group.new(10, Sketchup::Entities.new([zone("zon_BBBBBBBBBBBB", 200, [edge(202)])]),
                                :transformation => Geom::Transformation.translation([500, 0, 0]))
    turned = Sketchup::Group.new(20, Sketchup::Entities.new([zone("zon_CCCCCCCCCCCC", 300, [edge(302)],
                                                                  :segment => "Annex")]),
                                 :transformation => Geom::Transformation.new(QUARTER_TURN))
    @model.entities << moved
    @model.entities << turned

    rows = containment([100, 102], [10, 200, 202], [20, 300, 302])

    assert_equal [{ "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [100], "building_segment" => "Building",
                    "level" => "L1" },
                  { "zone_id" => "zon_BBBBBBBBBBBB", "zone_path" => [10, 200], "building_segment" => "Building",
                    "level" => "L1" },
                  { "zone_id" => "zon_CCCCCCCCCCCC", "zone_path" => [20, 300], "building_segment" => "Annex",
                    "level" => "L1" }], rows.map { |row| row.fetch("zone") }
    assert_equal [[102], [202], [302]], rows.map { |row| row.fetch("entity_path") }
    assert_equal [nil, nil, nil], rows.map { |row| [row.fetch("reason"), row.fetch("write_refusal")].compact.first }
    assert_equal [[100, 102], [10, 200, 202], [20, 300, 302]], rows.map { |row| row.fetch("path") }
  end

  def test_paths_no_zone_holds_answer_their_reason
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([edge(203)]))
    definition.behavior.cuts_opening = true
    container = Sketchup::Group.new(120, Sketchup::Entities.new([edge(122)]))
    held = zone("zon_AAAAAAAAAAAA", 100, [Sketchup::ComponentInstance.new(201, definition), container,
                                          Sketchup::Entity.new(125)])
    @model.entities << held
    @model.entities << edge(5)
    @model.entities << Sketchup::Group.new(6, Sketchup::Entities.new([edge(7)]))
    Z::STAMP_STORE.write(container, Z::Schema.stamp(Z::ZONE_STORE.read(held)))

    rows = containment([100, 201, 203], [100, 120, 122], [5], [6, 7], [100, 999], [100, 125])

    assert_equal %w[cutting_instance nested_container outside_zone outside_zone not_found not_a_drawing_element],
                 rows.map { |row| row.fetch("reason") }
    assert(rows.all? { |row| row["zone"].nil? && row["entity_path"].nil? && row["write_refusal"].nil? })
  end

  def test_a_group_leaf_is_held_and_storage_on_the_path_answers_the_write_refusal
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([edge(141)]))
    locked = Sketchup::Group.new(130, Sketchup::Entities.new([edge(131)]), :locked => true)
    inner = zone("zon_BBBBBBBBBBBB", 150, [edge(151)])
    @model.entities << zone("zon_AAAAAAAAAAAA", 100, [Sketchup::Group.new(110), locked,
                                                      Sketchup::ComponentInstance.new(140, definition), inner])
    @model.entities << zone("zon_CCCCCCCCCCCC", 300, [edge(302)], :locked => true)

    rows = containment([100, 110], [100, 130, 131], [100, 140, 141], [100, 150, 151], [300, 302])

    assert_equal [[100], [100], [100], [100, 150], [300]], rows.map { |row| row.dig("zone", "zone_path") }
    assert_equal [[110], [130, 131], [140, 141], [151], [302]], rows.map { |row| row.fetch("entity_path") }
    assert_equal [nil, "target.locked", "target.shared_definition", "target.wrong_hierarchy", "target.locked"],
                 rows.map { |row| row["write_refusal"]&.fetch("code") }
    assert_match(/Edge is inside a locked Group/, rows[1].dig("write_refusal", "message"))
  end

  def test_host_context_still_answers_faces_alone
    wall = Sketchup::Face.new(101)
    @model.entities << zone("zon_AAAAAAAAAAAA", 100, [wall, edge(102)])
    request = PhComposer::HandlerRequest.for(@session, :owner => Z::FEATURE_ID, :name => "test.containment")

    rows = request.query("ph_composer.zones.faces.host_context", "paths" => [[100, 101], [100, 102]]).fetch("faces")

    assert_equal [[100, 101]], rows.map { |row| row.fetch("path") }
    assert_equal({ "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [100], "entity_path" => [101],
                   "entity_id" => nil }, rows.first.fetch("reference"))
    assert_nil rows.first.fetch("write_refusal")
  end
end
