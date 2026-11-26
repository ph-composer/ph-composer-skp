# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/authoring/duct_types_walkthrough"
require_relative "../tools/examples/authoring/ducting_assignment_walkthrough"

class DuctingAssignmentWalkthroughTest < PhComposerTestCase
  W = DuctingAssignmentWalkthrough

  def setup
    super
    @model = Sketchup.active_model
    @ventilator = AuthoringExample::Client.new.invoke("ph_composer.mechanical.ventilators.create",
                                                      "values" => { "name" => "ERV-1" }).dig("value", "id")
    DuctTypesWalkthrough.run
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

  def read
    W.selection.map { |row| row.values_at("type", "direction", "quantity") }
  end

  def test_the_walkthrough_draws_makes_a_group_assigns_and_clears_through_public_calls
    line_tool(@model.entities)
    edges = W.draw
    made = W.make("ERV-1")
    assert_equal "committed", made["effect"], made.inspect
    group_id = made.dig("value", "group_id")
    group = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) }
    assert_equal [edges, nil], [group.entities.map(&:persistent_id), @model.active_path]
    reselect(group_id, edges)
    assert_equal "committed", W.assign("DT-2", "outdoor_air")["effect"]
    reselect(group_id, edges)
    assert_equal [["DT-2", "outdoor_air", 1]] * 2, read
    assert_equal "committed", W.assign(nil, nil, 2)["effect"]
    reselect(group_id, edges)
    assert_equal [["DT-2", "outdoor_air", 2]] * 2, read
    assert_equal [{ "path" => [group.persistent_id], "ventilator" => @ventilator, "ducts" => 2,
                    "findings" => [] }], W.groups

    assert_equal "committed", W.clear["effect"]
    reselect(group_id, edges)
    assert_equal [[nil, nil, nil]] * 2, read
    @model.undo
    reselect(group_id, edges)
    assert_equal [["DT-2", "outdoor_air", 2]] * 2, read
    @model.redo
    reselect(group_id, edges)
    assert_equal [[nil, nil, nil]] * 2, read
    path = File.join(Dir.tmpdir, "ph-composer-ducting-walkthrough.skp")
    @model.undo
    @model.save(path)
    Sketchup.open_file(path)
    @model = Sketchup.active_model
    reselect(group_id, edges)
    assert_equal [["DT-2", "outdoor_air", 2]] * 2, read, "a reopen keeps the assignment"
    text = File.read(File.expand_path("../tools/examples/authoring/ducting_assignment_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Ducting|PhComposer::Mechanical/, text)
  end
end
