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

  def reselect(group_id, edge_ids)
    group = @model.entities.to_a.find { |entity| entity.persistent_id == group_id }
    @model.active_path = [group]
    @model.selection.clear
    @model.selection.add(group.entities.to_a.select { |entity| edge_ids.include?(entity.persistent_id) })
  end

  def read
    W.selection.map { |row| row.values_at("type", "direction", "quantity") }
  end

  def test_the_walkthrough_creates_a_group_draws_assigns_and_clears_through_public_calls
    assert_equal "committed", W.create("ERV-1")["effect"]
    group = Array(@model.active_path).last
    line_tool(group.entities)
    edges = W.draw
    assert_equal "committed", W.assign("DT-2", "outdoor_air")["effect"]
    reselect(group.persistent_id, edges)
    assert_equal [["DT-2", "outdoor_air", 1]] * 2, read
    assert_equal "committed", W.assign(nil, nil, 2)["effect"]
    reselect(group.persistent_id, edges)
    assert_equal [["DT-2", "outdoor_air", 2]] * 2, read
    assert_equal [{ "path" => [group.persistent_id], "ventilator" => @ventilator, "ducts" => 2,
                    "findings" => [] }], W.groups

    assert_equal "committed", W.clear["effect"]
    reselect(group.persistent_id, edges)
    assert_equal [[nil, nil, nil]] * 2, read
    @model.undo
    reselect(group.persistent_id, edges)
    assert_equal [["DT-2", "outdoor_air", 2]] * 2, read
    @model.redo
    reselect(group.persistent_id, edges)
    assert_equal [[nil, nil, nil]] * 2, read
    path = File.join(Dir.tmpdir, "ph-composer-ducting-walkthrough.skp")
    @model.undo
    @model.save(path)
    Sketchup.open_file(path)
    @model = Sketchup.active_model
    reselect(group.persistent_id, edges)
    assert_equal [["DT-2", "outdoor_air", 2]] * 2, read, "a reopen keeps the assignment"
    text = File.read(File.expand_path("../tools/examples/authoring/ducting_assignment_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Ducting|PhComposer::Mechanical/, text)
  end
end
