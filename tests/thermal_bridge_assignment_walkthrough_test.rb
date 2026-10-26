# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/authoring/thermal_bridge_types_walkthrough"
require_relative "../tools/examples/authoring/thermal_bridge_assignment_walkthrough"

class ThermalBridgeAssignmentWalkthroughTest < PhComposerTestCase
  W = ThermalBridgeAssignmentWalkthrough

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.thermal_bridges")
    @model = Sketchup.active_model
    edges = [101, 102].map do |id|
      Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, id, 0))
    end
    @zone = Sketchup::Group.new(100, Sketchup::Entities.new(edges))
    PhComposer::Zones::ZONE_STORE.write(@zone,
                                        "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                        "building_segment" => "Building", "level" => nil, "ground_depth_mm" => 0.0,
                                        "user_data" => {}, "extension_data" => {})
    @model.entities << @zone
    ThermalBridgeTypesWalkthrough.run
  end

  def select_edges
    @model.active_path = [@zone]
    @model.selection.clear
    @model.selection.add(@zone.entities.to_a)
  end

  def test_the_walkthrough_assigns_replaces_and_clears_the_selection_through_public_calls
    select_edges
    assert_equal "committed", W.assign("Walkthrough parapet")["effect"]
    select_edges
    rows = W.selection.fetch("edges")
    assert_equal [["Walkthrough parapet", 1]] * 2, rows.map { |row| row.values_at("type", "quantity") }

    assert_equal "committed", W.replace("Walkthrough parapet", "Walkthrough slab edge")["effect"]
    select_edges
    assert_equal ["Walkthrough slab edge"] * 2, W.selection.fetch("edges").map { |row| row.fetch("type") }
    @model.undo
    @zone = @model.entities.to_a.find { |entity| entity.persistent_id == 100 }
    select_edges
    assert_equal ["Walkthrough parapet"] * 2, W.selection.fetch("edges").map { |row| row.fetch("type") }

    assert_equal "committed", W.clear["effect"]
    select_edges
    assert_equal [nil, nil], W.selection.fetch("edges").map { |row| row.fetch("type") }
    text = File.read(File.expand_path("../tools/examples/authoring/thermal_bridge_assignment_walkthrough.rb", __dir__))
    refute_match(/PhComposer::ThermalBridges|PhComposer::Zones/, text)
  end
end
