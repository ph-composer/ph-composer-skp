# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/authoring/pipe_types_walkthrough"
require_relative "../tools/examples/authoring/piping_assignment_walkthrough"

class PipingAssignmentWalkthroughTest < PhComposerTestCase
  W = PipingAssignmentWalkthrough

  def setup
    super
    @model = Sketchup.active_model
    @system = AuthoringExample::Client.new.invoke("ph_composer.mechanical.hot_water_systems.create",
                                                  "values" => { "name" => "HWS-1" }).dig("value", "id")
    PipeTypesWalkthrough.run
  end

  # The stub has no Line tool; each line is a new Edge, which is what the host's add_line gives.
  def line_tool(entities)
    entities.define_singleton_method(:add_line) do |start, finish|
      Sketchup::Edge.new(Sketchup::Entities.allocate_persistent_id, start, finish).tap { |edge| self << edge }
    end
  end

  def reselect(group_id, edge_ids)
    group = @model.entities.to_a.find { |entity| entity.persistent_id == group_id }
    @model.active_path = [group]
    @model.selection.clear
    @model.selection.add(group.entities.to_a.select { |entity| edge_ids.include?(entity.persistent_id) })
  end

  def test_the_walkthrough_creates_a_group_draws_assigns_and_clears_through_public_calls
    assert_equal "committed", W.create("HWS-1")["effect"]
    group = Array(@model.active_path).last
    line_tool(group.entities)
    edges = W.draw
    assert_equal "committed", W.assign("PT-1", "trunk", "multiplier" => 12)["effect"]
    reselect(group.persistent_id, edges)
    assert_equal [["PT-1", "trunk", 12]] * 3, W.selection.map { |row|
      [row["type"], row["role"], row.dig("values", "multiplier")]
    }
    assert_equal [{ "path" => [group.persistent_id], "system" => @system, "pipes" => 3,
                    "findings" => [] }], W.groups

    assert_equal "committed", W.clear["effect"]
    reselect(group.persistent_id, edges)
    assert_equal [nil] * 3, W.selection.map { |row| row["role"] }
    @model.undo
    reselect(group.persistent_id, edges)
    assert_equal ["trunk"] * 3, W.selection.map { |row| row["role"] }
    @model.redo
    reselect(group.persistent_id, edges)
    assert_equal [nil] * 3, W.selection.map { |row| row["role"] }
    text = File.read(File.expand_path("../tools/examples/authoring/piping_assignment_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Piping|PhComposer::Mechanical/, text)
  end
end
