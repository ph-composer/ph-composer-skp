# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Faces a client can make into Floor Segments or new Volumes, found by a read rather than a private walk
# (context/AGENT_INTERFACE.md, "Focused reads"), and the typed values the Spaces edits take.
class SpacesCandidateFacesTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  SPACE = { "space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [1000, 1100] }.freeze
  VOLUME = { "volume_id" => "vol_VVVVVVVVVVVV", "entity_path" => [1000, 1100, 1110] }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    marked = floor_face(1111, rectangle(0, 0, 3, 4), segment_record("M"))
    @unmarked = floor_face(1112, rectangle(3, 0, 2, 2))
    @loose = floor_face(1120, rectangle(0, 4, 2, 2))
    volume = volume_group(1110, volume_record("V"), [marked, @unmarked])
    @space = space_group(1100, space_record("S", :number => "101"), [volume, @loose])
    @zone = zone_group(1000, "A", [@space])
    @model.entities << @zone
  end

  def test_a_space_lists_its_unmarked_volume_face_and_its_loose_face
    rows = candidates("space" => SPACE)

    assert_equal [[1000, 1100, 1110, 1112], [1000, 1100, 1120]], rows.map { |row| row["entity_path"] }
    assert_equal %w[floor volume], rows.map { |row| row["candidate"] }
    assert_equal %w[ph_composer.spaces.floors.mark ph_composer.spaces.volumes.create],
                 rows.map { |row| row["operation"] }
    assert_equal [nil, nil], rows.map { |row| row["refusal"] }
    assert_in_delta 4.0, rows.first["plan_area_m2"], 1e-9
    refute rows.first.key?("loops_m")
    assert_equal [[1000, 1100, 1110, 1112]], candidates("volume" => VOLUME).map { |row| row["entity_path"] }
  end

  def test_marking_the_candidate_removes_it_and_unmarking_brings_it_back
    path = candidates("volume" => VOLUME).first.fetch("entity_path")
    marked = invoke("ph_composer.spaces.floors.mark", "faces" => [path], "weighting_factor" => 1.0)
    segment = { "floor_segment_id" => marked.dig("value", "floor_segment_ids", 0), "entity_path" => path }

    assert_equal "committed", marked["effect"]
    assert_empty candidates("volume" => VOLUME)
    invoke("ph_composer.spaces.floors.unmark", "floor_segments" => [segment])
    assert_equal [path], candidates("volume" => VOLUME).map { |row| row["entity_path"] }
  end

  def test_the_loose_face_becomes_a_new_volume_once_the_space_is_open
    loose = candidates("space" => SPACE).last
    @model.active_path = [@zone, @space]

    created = invoke(loose["operation"], "space" => SPACE, "faces" => [loose["entity_path"]])

    assert_equal "committed", created["effect"], created.inspect
    assert_equal ["floor"], candidates("space" => SPACE).map { |row| row["candidate"] }
  end

  def test_a_locked_space_refuses_as_its_action_would_and_reading_changes_nothing
    @space.locked = true
    before = [@model.active_path, @model.selection.to_a, @session.revision]

    rows = candidates("space" => SPACE)
    mark = invoke("ph_composer.spaces.floors.mark", "faces" => [rows.first["entity_path"]], "weighting_factor" => 1.0)

    assert_equal %w[target.locked target.locked], rows.map { |row| row.dig("refusal", "code") }
    assert_equal "target.locked", mark["code"]
    assert_equal before, [@model.active_path, @model.selection.to_a, @session.revision]
  end

  def test_a_face_in_a_volume_outside_every_space_refuses_as_floors_mark_does
    stray = volume_group(2110, volume_record("O"), [floor_face(2111, rectangle(10, 0, 2, 2))])
    @model.entities << zone_group(2000, "B", [stray])
    reference = { "volume_id" => "vol_OOOOOOOOOOOO", "entity_path" => [2000, 2110] }

    row = candidates("volume" => reference).first
    mark = invoke("ph_composer.spaces.floors.mark", "faces" => [row["entity_path"]], "weighting_factor" => 1.0)

    assert_equal ["target.wrong_hierarchy"] * 2, [row.dig("refusal", "code"), mark["code"]]
  end

  def test_a_loose_face_that_shares_an_edge_is_refused_alone_and_accepted_with_its_neighbour
    edge = Sketchup::Edge.new(300, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(0, 1 / 0.0254, 0))
    pair = [1121, 1122].map do |id|
      points = rectangle(id - 1121, 6, 1, 1).map { |x, y, z| Geom::Point3d.new(x / 0.0254, y / 0.0254, z / 0.0254) }
      Sketchup::Face.new(id, {}, :points => points, :edges => [edge])
    end
    pair.each { |face| @space.entities << face }
    @model.active_path = [@zone, @space]

    rows = candidates("space" => SPACE).select { |row| [1121, 1122].include?(row["entity_path"].last) }
    alone = invoke("ph_composer.spaces.volumes.create", "space" => SPACE, "faces" => [rows.first["entity_path"]])
    # Grouping stub Faces that carry a shared Edge is not modelled offline, so the pair is previewed.
    together = API.preview(:context => @context, :name => "ph_composer.spaces.volumes.create",
                           :params => { "space" => SPACE, "faces" => rows.map { |row| row["entity_path"] } })

    assert_equal %w[space.shares_edge space.shares_edge], rows.map { |row| row.dig("refusal", "code") }
    assert_equal "space.shares_edge", alone["code"]
    assert_equal "completed", together["status"], together.inspect
  end

  QUARTER_TURN = [0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 500.0, 0.0, 0.0, 1.0].freeze

  # A first Space needs no Space and no selection: the Faces loose at the root or in a rotated plain wrapper
  # are candidates for create, each refused as create refuses it named alone.
  def test_a_context_lists_its_loose_faces_for_a_first_space_with_creates_own_refusals
    floor = floor_face(3001, rectangle(20, 0, 2, 3))
    wall = floor_face(3002, [[30, 0, 0], [32, 0, 0], [32, 0, 2], [30, 0, 2]])
    turned = floor_face(3101, rectangle(1, 0, 2, 2))
    wrapper = Sketchup::Group.new(3100, Sketchup::Entities.new([turned]),
                                  :transformation => Geom::Transformation.new(QUARTER_TURN))
    [floor, wall, wrapper].each { |entity| @model.entities << entity }
    scope = PhComposer::Operations::EntityScope.new([])
    before = [scope.capture(@model), @model.selection.to_a, @model.active_path, @session.revision]

    root = candidates("context" => [])
    inside = candidates("context" => [3100], "fields" => %w[plan_area_m2 loops_m])

    assert_equal before, [scope.capture(@model), @model.selection.to_a, @model.active_path, @session.revision]
    assert_equal [[3001], [3002]], root.map { |row| row["entity_path"] }
    assert_equal [["space", "ph_composer.spaces.create", nil, nil], ["space", "ph_composer.spaces.create",
                                                                     "vertical", nil]],
                 root.map { |row| [row["candidate"], row["operation"], row.dig("refusal", "code"), row["requires"]] }
    preview = API.query(:context => @context, :name => "ph_composer.spaces.create_preview",
                        :params => { "faces" => [[3002]] }).fetch("value")
    assert_equal ["vertical"], preview.fetch("left_out").map { |row| row["reason"] }
    assert_in_delta 6.0, root.first["plan_area_m2"], 1e-9
    row = inside.first
    assert_equal [[3100, 3101], nil], [row["entity_path"], row["refusal"]]
    assert_match(/ph_composer.context.open/, row["requires"])
    assert_in_delta 4.0, row["plan_area_m2"], 1e-9
    # The quarter turn maps (1, 0) to (0, 1) and moves 500 inches along x, applied once.
    assert_equal [12.7, 1.0, 0.0], row.dig("loops_m", 0, 0).map { |value| value.round(9) }

    opened = API.view(:context => @context, :name => "ph_composer.context.open", :params => { "path" => [3100] })
    assert_equal "completed", opened["status"], opened.inspect
    assert_nil candidates("context" => [3100]).first["requires"]
    created = invoke("ph_composer.spaces.create", "faces" => [row["entity_path"]])
    assert_equal [[[3100, 3101]], []], [created.dig("value", "accepted"), created.dig("value", "left_out")],
                 created.inspect
  end

  def test_an_empty_or_locked_context_and_a_changed_model_read_as_create_would
    empty = Sketchup::Group.new(3200, Sketchup::Entities.new)
    locked = Sketchup::Group.new(3300, Sketchup::Entities.new([floor_face(3301, rectangle(0, 0, 1, 1)),
                                                               floor_face(3302, rectangle(2, 0, 1, 1))]),
                                 :locked => true)
    [empty, locked].each { |entity| @model.entities << entity }

    assert_equal [[], 0], query("context" => [3200]).fetch("value").values_at("candidate_faces", "total")
    rows = candidates("context" => [3300])
    assert_equal %w[target.locked target.locked], rows.map { |row| row.dig("refusal", "code") }
    first = query("context" => [3300], "limit" => 1).fetch("value")
    @session.host_event(:transaction_committed)
    assert_equal "query.cursor_expired",
                 query("context" => [3300], "limit" => 1, "cursor" => first.fetch("next_cursor"))["code"]
  end

  def test_a_scope_names_one_parent
    assert_equal "params.invalid", query("space" => SPACE, "context" => [])["code"]
    assert_equal "target.not_found", query("context" => [999])["code"]
    assert_equal "params.invalid", query({})["code"]
    assert_equal "target.changed", query("space" => SPACE.merge("space_id" => "spc_XXXXXXXXXXXX"))["code"]
  end

  def test_edits_are_typed_with_units_and_a_cross_kind_or_mistyped_value_refuses
    values = API.describe(:name => "ph_composer.spaces.update").dig("params", "properties", "values", "properties")
    volume = VOLUME

    assert_equal "m", values.dig("avg_ceiling_height_m", "x-unit")
    assert_equal %w[number null], values.dig("v_sup_m3h", "type")
    assert_equal "params.invalid", update(volume, { "weighting_factor" => 0.5 }, {})["code"]
    assert_equal "params.invalid", update(volume, { "avg_ceiling_height_m" => "tall" }, {})["code"]
    assert_equal "params.invalid", update(volume, { "display_name" => "" }, { "v_sup_m3h" => nil })["code"]
    raised = update(volume, { "avg_ceiling_height_m" => 2.7 }, { "avg_ceiling_height_m" => 2.5 })
    assert_equal "committed", raised["effect"]
    cleared = update(volume, { "avg_ceiling_height_m" => nil }, { "avg_ceiling_height_m" => 2.7 })
    assert_equal "committed", cleared["effect"]
    refute PhComposer::Spaces::VOLUME_STORE.read(@space.entities.to_a.first).key?("avg_ceiling_height_m")
  end

  private

  def query(params)
    API.query(:context => @context, :name => "ph_composer.spaces.candidate_faces.list", :params => params)
  end

  def candidates(params)
    result = query(params)
    assert_equal "completed", result["status"], result.inspect
    result.dig("value", "candidate_faces")
  end

  def update(reference, values, expected)
    invoke("ph_composer.spaces.update", "reference" => reference, "values" => values, "expected_values" => expected)
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
