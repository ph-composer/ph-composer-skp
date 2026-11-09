# frozen_string_literal: true

require_relative "test_helper"

# One walk of the Model per read phase, instead of about two per target.
#
# The host measured the old behaviour as O(targets x Model Faces): a 50-target gesture cost 459 ms
# in a 252-Face Model and 3,352 ms in a 2,004-Face one, and the Face read was quadratic through the
# same call. With the index, the same gesture costs 164 ms at 2,004 Faces (SketchUp 26.1).
#
# The property these tests hold is not a number of milliseconds, which the offline stub cannot
# speak to. It is that the number of times the Model is walked does not grow with the number of
# targets. The stub counts a walk of the root entities, which is what every resolution starts with.
class OccurrenceIndexTest < PhComposerTestCase
  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    # Show Spaces walks the Model once per commit of its own; these tests hold the gesture's walks.
    PhComposer::ColourBy.for(@session).readout(PhComposer::Spaces::Readouts::SHOW, :on => false)
    @sequence = 0
    @next_id = 1_000
  end

  # One Zone, so both gestures touch one mutation scope and the only thing that differs is how
  # many Faces they name. Before the index a gesture walked the Model about twice per target, so
  # the twenty-Face gesture walked it about forty times.
  def test_a_gesture_walks_the_model_the_same_number_of_times_however_many_faces_it_touches
    box(100, 24)
    author

    references = face_references
    # Both gestures have to write, or the one that changes nothing skips the apply phase and the
    # two are not comparable.
    one = walks { classify(references.first(1), "Floor") }
    many = walks { classify(references.first(20), "RoofCeiling") }

    assert_equal one, many, "resolution is one walk a gesture, not one a target"
    assert_operator many, :<=, 2, "one walk to resolve the gesture, one to apply it"
  end

  # Retirement resolves the counterpart of every Face it retires, which was the same walk again.
  def test_retiring_a_pair_walks_no_more_than_a_gesture_that_retires_nothing
    wall(200, 0, :east)
    wall(210, 0, :west)
    wall(220, 6, :east)
    wall(230, 6, :west)
    author
    invoke("ph_composer.zones.solve_adjacency", { "zones" => zone_references })
    paired = face_references(&:any?)
    assert_equal 4, paired.length

    retiring = walks { reclassify(paired, "Outdoors") }

    assert_operator retiring, :<=, 2
    assert_equal ["Outdoors"], boundary_conditions.uniq, "the pair really did retire"
  end

  # The Face read resolves each Surface Face's counterpart, which is where its own quadratic was.
  def test_the_face_read_walks_once_whether_or_not_the_faces_are_paired
    wall(300, 0, :east)
    wall(310, 0, :west)
    author
    unpaired = walks { faces }

    invoke("ph_composer.zones.solve_adjacency", { "zones" => zone_references })
    paired = walks { faces }

    assert_equal 2, boundary_conditions.count("Surface")
    assert_equal unpaired, paired, "a paired Face costs the read no extra walk"
  end

  # The index answers the ambiguity check from what it already walked, so the check has to still
  # fire. A copied Zone Group duplicates every Face id inside it.
  def test_a_duplicated_face_id_is_still_ambiguous_when_the_index_answers_the_check
    box(400)
    box(500)
    author
    reference = face_references.first
    duplicate_face_id(reference.fetch("entity_id"))

    result = classify([reference], "Floor")

    assert_equal "refused", result.fetch("status")
    assert_equal "target.ambiguous", result.fetch("code")
  end

  # The index answers the Zone lookup too, so the refusals that lookup owns have to survive it.
  def test_a_stale_zone_path_is_still_refused_when_the_index_answers_the_lookup
    box(700)
    author
    reference = face_references.first.merge("zone_path" => [9_999])

    result = classify([reference], "Floor")

    assert_equal "refused", result.fetch("status")
    assert_equal "target.changed", result.fetch("code")
  end

  def test_a_missing_zone_is_still_refused_when_the_index_answers_the_lookup
    box(800)
    author
    reference = face_references.first.merge("zone_id" => "zon_000000000000")

    result = classify([reference], "Floor")

    assert_equal "target.not_found", result.fetch("code")
  end

  # An index answers for the Model it walked. Handing one to another Model's read would answer
  # about the wrong document while the write landed on this one.
  def test_an_index_refuses_a_model_it_did_not_walk
    box(900)
    other = Sketchup::Model.new
    index = PhComposer::Zones::Index.new(other)

    assert_raises(PhComposer::InternalError) do
      PhComposer::Zones::Occurrences.zones(@model, :index => index)
    end
  end

  def test_an_index_and_a_walk_resolve_the_same_occurrence
    box(600)
    author
    reference = face_references.first
    index = PhComposer::Zones::Index.new(@model)

    walked = PhComposer::Zones::Occurrences.resolve_face(@model, reference)
    indexed = PhComposer::Zones::Occurrences.resolve_face(@model, reference, :index => index)

    assert_equal walked.path, indexed.path
    assert_same walked.entity, indexed.entity
    assert_equal walked.zone.record, indexed.zone.record
  end

  private

  # Root-entity traversals during the block. Every resolution starts by walking the root.
  def walks
    before = @model.entities.each_count
    yield
    @model.entities.each_count - before
  end

  def classify(references, face_type)
    invoke("ph_composer.zones.faces.classify", {
      "faces" => references, "expected_values" => {},
      "intent" => { "face_type" => { "mode" => "set", "value" => face_type },
                    "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } }
    })
  end

  def reclassify(references, boundary)
    invoke("ph_composer.zones.faces.classify", {
      "faces" => references, "expected_values" => {},
      "intent" => { "boundary_condition" => { "mode" => "set", "value" => boundary } }
    })
  end

  # The same Face id on a Face in another Zone, which is what a copied Zone leaves behind.
  def duplicate_face_id(face_id)
    store = PhComposer::Zones::Faces::FACE_STORE
    other = @model.entities.to_a.last.entities.to_a.first
    store.write(other, store.read(other).merge("id" => face_id))
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def faces
    API.query(:context => @context, :name => "ph_composer.zones.faces.list").dig("value", "faces")
  end

  def face_references
    rows = faces
    rows = rows.select { |face| face.dig("values", "boundary_condition") == "Surface" } if block_given?
    rows.map { |face| face.fetch("reference") }
  end

  def zone_references
    API.query(:context => @context, :name => "ph_composer.zones.list")
       .dig("value", "zones").map { |zone| zone.fetch("reference") }
  end

  def boundary_conditions
    faces.map { |face| face.dig("values", "boundary_condition") }
  end

  def author
    invoke("ph_composer.zones.faces.classify", {
      "faces" => face_references,
      "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                    "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } },
      "expected_values" => {}
    })
  end

  def box(persistent_id, count = 4)
    faces = count.times.map do |index|
      Sketchup::Face.new(@next_id += 1, {}, :points => [point(0, 0, index), point(2, 0, index),
                                                        point(2, 2, index)])
    end
    @model.entities << Sketchup::Group.new(persistent_id, Sketchup::Entities.new(faces))
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [persistent_id] })
  end

  # One Zone holding one vertical wall in the y-z plane at x = offset.
  def wall(persistent_id, offset, facing)
    points = [[offset, 0, 0], [offset, 4, 0], [offset, 4, 3], [offset, 0, 3]]
    points = points.reverse if facing == :west
    face = Sketchup::Face.new(@next_id += 1, {}, :points => points.map { |value| metres(value) },
                                                 :normal => Geom::Vector3d.new(facing == :east ? 1 : -1, 0, 0))
    @model.entities << Sketchup::Group.new(persistent_id, Sketchup::Entities.new([face]))
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [persistent_id] })
  end

  def point(x_value, y_value, z_value)
    Geom::Point3d.new(x_value, y_value, z_value)
  end

  def metres(point)
    Geom::Point3d.new(*point.map { |value| value / 0.0254 })
  end
end
