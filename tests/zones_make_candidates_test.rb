# frozen_string_literal: true

require_relative "test_helper"

# The Groups Make Zone could take, found with no selection: each candidate carries the refusal the action
# gives it in its own context, by the action's own check (context/CONTRACTS.md, "Zones geometry rules"), and
# a context that is not open says so rather than refusing.
class ZonesMakeCandidatesTest < PhComposerTestCase
  API = PhComposer::API
  QUERY = "ph_composer.zones.make_candidates"
  QUARTER_TURN = [0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 500.0, 0.0, 0.0, 1.0].freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @plain = group(300)
    @locked = Sketchup::Group.new(310, Sketchup::Entities.new([face(311)]), :locked => true)
    @space = group(320)
    PhComposer::Spaces::SPACE_STORE.write(@space, "id" => "spc_AAAAAAAAAAAA")
    @holds_space = Sketchup::Group.new(330, Sketchup::Entities.new([group(331).tap do |inner|
      PhComposer::Spaces::SPACE_STORE.write(inner, "id" => "spc_BBBBBBBBBBBB")
    end]))
    @nested = group(400)
    @wrapper = Sketchup::Group.new(20, Sketchup::Entities.new([@nested]),
                                   :transformation => Geom::Transformation.new(QUARTER_TURN))
    [@plain, @locked, @space, @holds_space, @wrapper, face(5)].each { |entity| @model.entities << entity }
  end

  def face(id)
    Sketchup::Face.new(id)
  end

  def group(id)
    Sketchup::Group.new(id, Sketchup::Entities.new([face(id + 1)]))
  end

  def test_root_candidates_carry_the_refusal_make_zone_gives_each_and_a_free_one_becomes_a_zone
    root = candidates

    refusals = root.fetch("candidates").to_h { |row| [row.fetch("path").last, row.dig("refusal", "code")] }
    assert_equal({ 20 => nil, 300 => nil, 310 => "target.locked", 320 => "target.wrong_kind",
                   330 => "target.wrong_hierarchy" }, refusals)
    assert_equal [false, 1, 0], root.values_at("open_required", "loose_faces", "loose_edges")
    %w[target.locked target.wrong_kind target.wrong_hierarchy].zip([310, 320, 330]).each do |code, id|
      assert_equal code, make(row_for(root, id).fetch("make_zone"))["code"]
    end

    made = make(row_for(root, 300).fetch("make_zone"))
    assert_equal "committed", made["effect"], made.inspect
    assert_equal "target.wrong_hierarchy", row_for(candidates, 300).dig("refusal", "code")
  end

  def test_a_group_in_a_rotated_wrapper_needs_its_context_open_first
    inside = candidates("parent_path" => [20])
    row = row_for(inside, 400)

    assert_equal [true, nil], [inside.fetch("open_required"), row.fetch("refusal")]
    assert_equal({ "parent_path" => [20], "entity_ids" => [400] }, row.fetch("make_zone"))
    assert_equal "target.edit_path_changed", make(row.fetch("make_zone"))["code"]
    opened = API.view(:context => @context, :name => "ph_composer.context.open", :params => { "path" => [20] })
    assert_equal "completed", opened["status"], opened.inspect
    refute candidates("parent_path" => [20]).fetch("open_required")
    assert_equal "committed", make(row.fetch("make_zone"))["effect"]
  end

  def test_a_locked_wrapper_refuses_its_candidates_as_opening_it_would
    @wrapper.locked = true

    row = row_for(candidates("parent_path" => [20]), 400)
    opened = API.view(:context => @context, :name => "ph_composer.context.open", :params => { "path" => [20] })

    assert_equal %w[target.locked target.locked], [row.dig("refusal", "code"), opened["code"]]
  end

  def test_a_component_context_refuses_every_candidate_as_the_action_would
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([group(500)]))
    @model.entities << Sketchup::ComponentInstance.new(50, definition)

    rows = candidates("parent_path" => [50]).fetch("candidates")

    found = rows.map { |row| [row.fetch("path"), row.dig("refusal", "code")] }
    assert_equal [[[50, 500], "target.shared_definition"]], found
  end

  def test_reading_moves_and_writes_nothing_and_a_changed_model_expires_the_cursor
    scope = PhComposer::Operations::EntityScope.new([])
    before = [scope.capture(@model), @model.selection.to_a, @model.active_path, @session.revision]
    first = candidates("limit" => 2)
    candidates("parent_path" => [20])

    assert_equal before, [scope.capture(@model), @model.selection.to_a, @model.active_path, @session.revision]
    assert_equal 5, first.fetch("total")
    @session.host_event(:transaction_committed)
    expired = query("limit" => 2, "cursor" => first.fetch("next_cursor"))
    assert_equal "query.cursor_expired", expired.fetch("code")
    assert_equal "target.not_found", query("parent_path" => [999]).fetch("code")
  end

  private

  def row_for(read, id)
    read.fetch("candidates").find { |row| row.fetch("path").last == id }
  end

  def query(params)
    API.query(:context => @context, :name => QUERY, :params => params)
  end

  def candidates(params = {})
    result = query(params)
    assert_equal "completed", result.fetch("status"), result.inspect
    result.fetch("value")
  end

  def make(params)
    @sequence += 1
    API.invoke(:context => @context, :name => "ph_composer.zones.make", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
