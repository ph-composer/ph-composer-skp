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

  # Undo, Redo and a reopen close the group and clear the selection, as the host does.
  def reselect(group_id, edge_ids)
    assert_equal "completed", W.open_group(group_id)["status"]
    W.reselect(edge_ids)
  end

  def test_the_walkthrough_draws_makes_a_group_assigns_and_clears_through_public_calls
    line_tool(@model.entities)
    edges = W.draw
    made = W.make("HWS-1")
    assert_equal "committed", made["effect"], made.inspect
    group_id = made.dig("value", "group_id")
    group = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) }
    assert_equal [edges, nil], [group.entities.map(&:persistent_id), @model.active_path]
    reselect(group_id, edges)
    assert_equal "committed", W.assign("PT-1", "trunk", "multiplier" => 12)["effect"]
    reselect(group_id, edges)
    assert_equal [["PT-1", "trunk", 12]] * 3, W.selection.map { |row|
      [row["type"], row["role"], row.dig("values", "multiplier")]
    }
    assert_equal [{ "path" => [group.persistent_id], "system" => @system, "pipes" => 3,
                    "findings" => [] }], W.groups

    assert_equal "committed", W.clear["effect"]
    reselect(group_id, edges)
    assert_equal [nil] * 3, W.selection.map { |row| row["role"] }
    @model.undo
    reselect(group_id, edges)
    assert_equal ["trunk"] * 3, W.selection.map { |row| row["role"] }
    @model.redo
    reselect(group_id, edges)
    assert_equal [nil] * 3, W.selection.map { |row| row["role"] }
    text = File.read(File.expand_path("../tools/examples/authoring/piping_assignment_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Piping|PhComposer::Mechanical/, text)
  end
end
