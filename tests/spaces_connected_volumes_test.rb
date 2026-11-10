# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Faces share a Volume only when they are joined by a shared SketchUp Edge, a step between planes included; Faces
# meeting at a corner, or not at all, make separate Volumes. Create Space and volumes.create both follow it, and a
# Volume whose Floor Segments come apart later reads space.floor_disconnected, a warning that does not block
# export (spaces_export_test.rb).
class SpacesConnectedVolumesTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  ZONE = { "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [100] }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @zone = zone_group(100, "Z", [])
    @model.entities << @zone
    @model.active_path = [@zone]
  end

  def point(x, y, z = 0)
    Geom::Point3d.new(x * INCHES, y * INCHES, z * INCHES)
  end

  # A Face with the Edges named: the host gives every Face its Edges, the stub only those a fixture passes.
  def face(id, corners_m, edges = [])
    Sketchup::Face.new(id, {}, :points => corners_m.map { |x, y, z| point(x, y, z || 0) }, :edges => edges)
  end

  def draw(*entities)
    entities.each { |entity| @zone.entities << entity }
  end

  def create(faces)
    invoke("ph_composer.spaces.create", "zone" => ZONE, "faces" => faces.map { |entity| [100, entity.persistent_id] })
  end

  def space
    query("ph_composer.spaces.all").fetch("spaces").first
  end

  def test_two_separate_faces_make_one_space_with_a_volume_each_in_one_undo_step
    near = face(101, rectangle(0, 0, 2, 2))
    far = face(102, rectangle(5, 0, 2, 2))
    draw(near, far)
    operations = @model.operations.length

    result = create([near, far])

    assert_equal "completed", result["status"], result.inspect
    assert_equal operations + 1, @model.operations.length
    created = result.dig("value", "volumes")
    row = space
    assert_equal(row.fetch("volumes").map { |volume| volume.dig("reference", "volume_id") },
                 created.map { |volume| volume["volume_id"] })
    assert_equal [1, 2], row.fetch("volumes").map { |volume| volume.dig("values", "number") }
    assert_equal [[101], [102]], row.fetch("volumes").map { |volume| segment_faces(volume) }
    assert_equal [1, 1], created.map { |volume| volume.fetch("floor_segment_ids").length }
    assert_equal 3, row.dig("values", "next_volume_sequence")
    assert(row.fetch("volumes").all? do |volume|
      volume.dig("reference", "entity_path")[0...-1] == row.dig("reference", "entity_path")
    end, "both Volumes are in the Space placed outside the Zone")
    assert @model.undo
    assert_nil space, "one Undo takes the Space and both Volumes back"
  end

  def test_two_faces_sharing_an_edge_across_a_step_make_one_volume
    edge = Sketchup::Edge.new(300, point(2, 0), point(2, 2))
    flat = face(101, rectangle(0, 0, 2, 2), [edge])
    ramp = face(102, [[2, 0, 0], [4, 0, 0.5], [4, 2, 0.5], [2, 2, 0]], [edge])
    draw(edge, flat, ramp)

    result = create([flat, ramp])

    assert_equal "completed", result["status"], result.inspect
    assert_equal 1, result.dig("value", "volumes").length
    volume = space.fetch("volumes").first
    assert_equal [101, 102], segment_faces(volume)
    assert_empty codes(volume), "a joined floor surface is not disconnected"
  end

  def test_faces_meeting_only_at_a_corner_make_two_volumes
    corner = Sketchup::Vertex.new(point(1, 1))
    left = face(101, rectangle(0, 0, 1, 1), [Sketchup::Edge.new(300, point(1, 0), corner)])
    right = face(102, rectangle(1, 1, 1, 1), [Sketchup::Edge.new(301, corner, point(2, 1))])
    draw(*left.edges, *right.edges, left, right)

    result = create([left, right])

    assert_equal "completed", result["status"], result.inspect
    assert_equal [[101], [102]], space.fetch("volumes").map { |volume| segment_faces(volume) }
  end

  def test_a_disconnected_set_given_to_volumes_create_makes_several_volumes_in_one_undo_step
    draw(face(101, rectangle(0, 0, 2, 2)))
    assert_equal "completed", create([@zone.entities.to_a.first])["status"]
    group = @model.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    group.entities << face(110, rectangle(0, 5, 1, 1)) << face(111, rectangle(5, 5, 1, 1))
    @model.active_path = [group]
    reference = space.fetch("reference")
    operations = @model.operations.length

    result = invoke("ph_composer.spaces.volumes.create",
                    "space" => reference, "faces" => [110, 111].map { |id| reference.fetch("entity_path") + [id] })

    assert_equal "completed", result["status"], result.inspect
    assert_equal operations + 1, @model.operations.length
    assert_equal 2, result.dig("value", "volumes").length
    row = space
    assert_equal [1, 2, 3], row.fetch("volumes").map { |volume| volume.dig("values", "number") }
    assert_equal 4, row.dig("values", "next_volume_sequence")
    assert_in_delta 2.5, row.dig("volumes", 2, "values", "avg_ceiling_height_m"), 1e-9, "the Space's default height"
  end

  def test_a_volume_whose_floor_segments_come_apart_warns_without_blocking
    @model.active_path = nil
    faces = [face(1111, rectangle(0, 0, 2, 2)), face(1112, rectangle(5, 0, 2, 2))]
    faces.zip(%w[L M]).each { |entity, letter| SPACES::FLOOR_SEGMENT_STORE.write(entity, segment_record(letter)) }
    @zone.entities << space_group(1100, space_record("L", :number => "101"),
                                  [volume_group(1110, volume_record("L"), faces)])
    volume = space.fetch("volumes").first
    found = volume.fetch("findings").find { |finding| finding["code"] == "space.floor_disconnected" }
    assert_equal "Volume 1 has Floor Segments that share no Edge with the others, so its floor is in separate pieces.",
                 found["message"]
    assert_equal false, found["blocks_export"]
  end

  def segment_faces(volume)
    volume.fetch("floor_segments").map { |segment| segment.dig("reference", "entity_path").last }
  end

  def codes(row)
    row.fetch("findings").map { |finding| finding["code"] }
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => name, :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
