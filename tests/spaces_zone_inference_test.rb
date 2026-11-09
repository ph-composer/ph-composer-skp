# frozen_string_literal: true

require_relative "test_helper"

# Which Zone a floor outline drawn outside every Zone belongs in: its plan centroid over a Zone Face and all of it
# inside the Zone's height range (W6-3).
class SpacesZoneInferenceTest < Minitest::Test
  INFER = PhComposer::Spaces::ZoneInference

  def square(x0, y0, size, z)
    [[x0, y0, z], [x0 + size, y0, z], [x0 + size, y0 + size, z], [x0, y0 + size, z]]
  end

  def zone(name, floors, height: 3.0)
    roofs = floors.map { |floor| floor.map { |x, y, z| [x, y, z + height] } }
    INFER::Candidate.new(:reference => name, :faces => (floors + roofs).map { |loop| [loop] })
  end

  def test_the_zone_over_the_centroid_and_around_the_height_wins
    outline = [square(2, 2, 1, 1)]
    assert_equal "A", INFER.pick(outline, [zone("B", [square(50, 0, 10, 0)]), zone("A", [square(0, 0, 10, 0)])])
  end

  def test_an_outline_above_or_below_the_height_range_is_in_no_zone
    above = zone("A", [square(0, 0, 10, 0)], :height => 3.0)
    assert_nil INFER.pick([square(2, 2, 1, 4)], [above])
    assert_nil INFER.pick([square(2, 2, 1, -1)], [above])
  end

  def test_the_notch_of_an_l_shaped_zone_holds_nothing
    leg_a = [[0, 0, 0], [10, 0, 0], [10, 4, 0], [0, 4, 0]]
    leg_b = [[0, 4, 0], [4, 4, 0], [4, 10, 0], [0, 10, 0]]
    l_shape = zone("A", [leg_a, leg_b])
    assert_nil INFER.pick([square(7, 7, 1, 1)], [l_shape])
    assert_equal "A", INFER.pick([square(1, 7, 1, 1)], [l_shape])
  end

  def test_a_face_hole_holds_nothing
    outer = square(0, 0, 10, 0)
    hole = square(4, 4, 2, 0)
    candidate = INFER::Candidate.new(:reference => "A", :faces => [[outer, hole], [square(0, 0, 10, 3)]])
    # The roof Face has no hole, so a centre in the hole is still held; only a Face with the hole is not enough.
    assert_equal "A", INFER.pick([square(4.5, 4.5, 1, 1)], [candidate])
    refute INFER.inside_face?([5, 5], [outer, hole])
  end

  def test_the_centroid_is_area_weighted_across_outlines
    assert_equal [4.0, 1.0], INFER.centroid([square(0, 0, 2, 0), square(6, 0, 2, 0)]).map { |value| value.round(6) }
    big = square(0, 0, 10, 0)
    small = square(20, 0, 2, 0)
    x, = INFER.centroid([big, small])
    assert_in_delta 5.0 + (21.0 - 5.0) * 4.0 / 104.0, x, 1e-9
  end

  def test_no_outline_and_no_candidates_are_no_zone
    assert_nil INFER.pick([], [zone("A", [square(0, 0, 10, 0)])])
    assert_nil INFER.pick([square(0, 0, 1, 0)], [])
  end
end
