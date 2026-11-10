# frozen_string_literal: true

require_relative "test_helper"

# What one container holds, read with no selection (context/AGENT_INTERFACE.md, "Model context"): every
# direct child, whatever its state, with what a feature needs before it builds on it, a bounded page at a
# time, and nothing moved or written by reading.
class ContextChildrenTest < PhComposerTestCase
  API = PhComposer::API
  CHILDREN = PhComposer::ContextCommands::CHILDREN
  QUARTER_TURN = [0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 500.0, 0.0, 0.0, 1.0].freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @face = Sketchup::Face.new(201)
    @locked = Sketchup::Group.new(210, Sketchup::Entities.new, :locked => true, :name => "Locked")
    @hidden = Sketchup::Group.new(220, Sketchup::Entities.new([Sketchup::Edge.new(221, origin, origin)]))
    @hidden.hidden = true
    @definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(231)]))
    @component = Sketchup::ComponentInstance.new(230, @definition)
    @wrapper = Sketchup::Group.new(200, Sketchup::Entities.new([@face, @locked, @hidden, @component]),
                                   :transformation => Geom::Transformation.new(QUARTER_TURN), :name => "Wrapper")
    @model.entities << @wrapper
    @model.entities << Sketchup::Edge.new(5, origin, origin)
  end

  def origin
    Geom::Point3d.new(0, 0, 0)
  end

  def test_the_root_and_a_rotated_wrapper_list_every_child_with_its_state_and_owner
    zone_store = PhComposer::Zones::ZONE_STORE
    zone_store.write(@locked, "id" => "zon_AAAAAAAAAAAA")

    root = children
    inside = children("path" => [200])

    assert_equal [[5], [200]], root.fetch("children").map { |row| row.fetch("path") }
    assert_equal %w[edge group], root.fetch("children").map { |row| row.fetch("kind") }
    rows = inside.fetch("children").to_h { |row| [row.fetch("persistent_id"), row] }
    assert_equal [201, 210, 220, 230], rows.keys
    assert_equal({ "path" => [200, 210], "persistent_id" => 210, "kind" => "group", "type" => "Group",
                   "name" => "Locked", "definition_name" => "", "hidden" => false, "locked" => true,
                   "shared" => false, "solid" => false, "child_count" => 0,
                   "records" => [{ "dictionary" => zone_store.dictionary, "key" => zone_store.key,
                                   "claims" => false }] }, rows.fetch(210))
    assert_equal [true, true], [rows.fetch(220).fetch("hidden"), rows.fetch(230).fetch("shared")]
    assert_equal [nil, nil, nil], rows.fetch(201).values_at("locked", "shared", "child_count")
    assert_equal({ "path" => [200], "locked" => false, "hidden" => false, "shared" => false },
                 inside.fetch("container"))
    assert_equal({ "path" => [200, 230], "locked" => false, "hidden" => false, "shared" => true },
                 children("path" => [200, 230]).fetch("container"))
  end

  def test_a_claimed_solid_a_shared_group_and_a_locked_hidden_container_read_as_they_are
    PhComposer::Spaces::SPACE_STORE.write(@locked, "id" => "spc_AAAAAAAAAAAA")
    @locked.solid_volume = 1000.0
    copy = Sketchup::Group.new(240, @hidden.entities)
    @wrapper.entities << copy
    @wrapper.locked = true
    @wrapper.hidden = true

    rows = children("path" => [200]).fetch("children").to_h { |row| [row.fetch("persistent_id"), row] }

    assert_equal [true, true], [rows.fetch(210).fetch("solid"), rows.fetch(210).dig("records", 0, "claims")]
    assert_equal [true, true], [rows.fetch(220).fetch("shared"), rows.fetch(240).fetch("shared")]
    assert_equal({ "path" => [200], "locked" => true, "hidden" => true, "shared" => false },
                 children("path" => [200]).fetch("container"))
  end

  def test_kinds_filter_and_a_hidden_tag_hides_without_dropping
    @face.layer = Sketchup::Tag.new("Hidden", false)

    faces = children("path" => [200], "kinds" => ["face"]).fetch("children")

    assert_equal [[201, true]], faces.map { |row| [row.fetch("persistent_id"), row.fetch("hidden")] }
    groups = children("path" => [200], "kinds" => ["group"]).fetch("children")
    assert_equal [210, 220], groups.map { |row| row.fetch("persistent_id") }
  end

  def test_pages_resume_and_a_changed_model_expires_the_cursor
    first = children("path" => [200], "limit" => 3)
    rest = children("path" => [200], "limit" => 3, "cursor" => first.fetch("next_cursor"))

    assert_equal [201, 210, 220, 230],
                 (first.fetch("children") + rest.fetch("children")).map { |row| row.fetch("persistent_id") }
    assert_equal [4, nil], [rest.fetch("total"), rest.fetch("next_cursor")]
    @session.host_event(:transaction_committed)
    expired = query("path" => [200], "limit" => 3, "cursor" => first.fetch("next_cursor"))
    assert_equal "query.cursor_expired", expired.fetch("code")
  end

  # 600 named Groups page losslessly, each whole reply inside the agent budget, the byte cut resuming after
  # the last row it sent.
  def test_a_large_container_pages_to_the_end_within_the_reply_budget
    crowd = Sketchup::Group.new(900, Sketchup::Entities.new((1..600).map do |index|
      Sketchup::Group.new(10_000 + index, Sketchup::Entities.new, :name => "Group #{index} #{'x' * 200}")
    end))
    @model.entities << crowd
    seen = []
    cursor = nil
    pages = 0
    loop do
      result = query({ "path" => [900], "limit" => 500, "cursor" => cursor }.compact)
      assert_operator JSON.generate(result).bytesize, :<, 24 * 1024
      seen.concat(result.dig("value", "children").map { |row| row.fetch("persistent_id") })
      pages += 1
      break unless (cursor = result.dig("value", "next_cursor"))
    end

    assert_equal (10_001..10_600).to_a, seen
    assert_operator pages, :>, 2
  end

  # SketchUp bounds no name: a long one is cut by characters, multibyte text included, and the row names it.
  def test_a_long_name_is_cut_and_named_so_one_row_stays_inside_the_reply_budget
    long = "é" * 26_000
    @wrapper.entities << Sketchup::Group.new(250, Sketchup::Entities.new, :name => long)

    result = query("path" => [200], "kinds" => ["group"], "limit" => 1, "cursor" => children(
      "path" => [200], "kinds" => ["group"], "limit" => 2
    ).fetch("next_cursor"))
    row = result.dig("value", "children", 0)
    candidate = API.query(:context => @context, :name => "ph_composer.zones.make_candidates",
                          :params => { "parent_path" => [200] })
    named = candidate.dig("value", "candidates").find { |entry| entry.fetch("path") == [200, 250] }

    assert_equal [250, "é" * 256, ["name"]], row.values_at("persistent_id", "name", "truncated")
    assert_operator JSON.generate(result).bytesize, :<, 24 * 1024
    assert_equal [256, ["name"]], [named.fetch("name").length, named.fetch("truncated")]
    refute children("path" => [200], "kinds" => ["face"]).dig("children", 0).key?("truncated")
  end

  def test_a_missing_step_and_a_leaf_that_holds_nothing_refuse
    assert_equal "target.not_found", query("path" => [999]).fetch("code")
    assert_equal "target.wrong_kind", query("path" => [200, 201]).fetch("code")
  end

  def test_reading_moves_and_writes_nothing
    @model.selection.add(@face)
    scope = PhComposer::Operations::EntityScope.new([])
    before = [scope.capture(@model), @model.selection.to_a, @model.active_path, @session.revision,
              @session.view_generation]

    children("path" => [200])
    children

    assert_equal before, [scope.capture(@model), @model.selection.to_a, @model.active_path, @session.revision,
                          @session.view_generation]
  end

  private

  def query(params)
    API.query(:context => @context, :name => CHILDREN, :params => params)
  end

  def children(params = {})
    result = query(params)
    assert_equal "completed", result.fetch("status"), result.inspect
    result.fetch("value")
  end
end
