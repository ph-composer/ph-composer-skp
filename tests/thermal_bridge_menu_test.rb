# frozen_string_literal: true

require_relative "test_helper"

# The right-click "Thermal bridge" menu: offered only on a selection holding an Edge a write can reach, one
# item per Thermal Bridge Type, then Clear when a selected Edge has an assignment. Each item is one public
# invoke and one native Undo step.
class ThermalBridgeMenuTest < PhComposerTestCase
  API = PhComposer::API
  TB = PhComposer::ThermalBridges
  STORE = TB::Assignment::STORE

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(TB::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @edge = Sketchup::Edge.new(101, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0))
    @wall = Sketchup::Face.new(110)
    @zone = Sketchup::Group.new(100, Sketchup::Entities.new([@edge, @wall]))
    PhComposer::Zones::ZONE_STORE.write(@zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                               "building_segment" => "Building", "level" => nil,
                                               "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    @model.entities << @zone
    @slab = create_type("Slab edge")
    @parapet = create_type("Parapet")
    @declaration = PhComposer::Registry.current.menu_items.fetch("#{TB::FEATURE_ID}.assign_menu")
    @model.active_path = [@zone]
  end

  def test_only_faces_selected_offers_no_menu
    @model.selection.add([@wall])
    refute @declaration.available.call(read)
  end

  def test_one_assignable_edge_offers_each_type_by_name_and_assigns_in_one_undo_step
    @model.selection.add([@edge])
    assert @declaration.available.call(read)
    entries = @declaration.entries.call(read)
    assert_equal ["Parapet", "Slab edge"], entries.map(&:label)

    before = @model.operations.length
    entries.first.handler.call(@session)
    assert_equal [@parapet, 1], STORE.read(@edge).values_at("thermal_bridge_type_id", "quantity")
    assert_equal before + 1, @model.operations.length
  end

  def test_an_assigned_edge_adds_clear_after_the_types
    @model.selection.add([@edge])
    @declaration.entries.call(read).last.handler.call(@session)
    entries = @declaration.entries.call(read)
    assert_equal ["Parapet", "Slab edge", "Clear thermal bridge"], entries.map(&:label)
    assert entries[1].separator_after

    entries.last.handler.call(@session)
    assert_nil STORE.read(@edge)
  end

  def test_an_invalid_assignment_with_no_values_offers_clear
    STORE.write(@edge, "id" => "tbe_BADBADBADBAD", "schema_version" => 1)
    @model.selection.add([@edge])
    entries = @declaration.entries.call(read)
    assert_equal "Clear thermal bridge", entries.last.label

    entries.last.handler.call(@session)
    assert_nil STORE.read(@edge)
  end

  def test_an_edge_outside_any_zone_offers_no_menu
    @model.active_path = []
    @model.entities << (loose = Sketchup::Edge.new(5, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(0, 100, 0)))
    @model.selection.add([loose])
    refute @declaration.available.call(read)
  end

  def test_a_selection_over_the_gesture_limit_offers_no_menu
    TB::Assignment.gesture_edge_limit = 0
    @model.selection.add([@edge])
    refute @declaration.available.call(read)
  end

  private

  def read
    PhComposer::HandlerRequest.for(@session, :owner => @declaration.owner, :name => @declaration.name)
  end

  def create_type(name)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{TB::FEATURE_ID}.types.create",
               :params => { "values" => { "name" => name, "psi_w_mk" => 0.1 } },
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision }).dig("value", "id")
  end
end
