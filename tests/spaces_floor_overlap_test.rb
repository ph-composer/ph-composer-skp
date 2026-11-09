# frozen_string_literal: true

require_relative "test_helper"

# Whether two Floor Segments cover the same plan area: stacked or crossing outlines do, whatever their
# shape; outlines that only touch do not.
class SpacesFloorOverlapTest < PhComposerTestCase
  OVERLAP = PhComposer::Spaces::FloorOverlap

  def square(x0, y0, side, z = 0)
    [[x0, y0, z], [x0 + side, y0, z], [x0 + side, y0 + side, z], [x0, y0 + side, z]]
  end

  # A 4 by 4 m L, its notch the top right 2 by 2 m.
  def ell(z = 0)
    [[0, 0, z], [4, 0, z], [4, 2, z], [2, 2, z], [2, 4, z], [0, 4, z]]
  end

  def test_the_same_outline_stacked_above_itself_overlaps
    assert OVERLAP.any?([[square(0, 0, 3)], [square(0, 0, 3, 2.5)]])
  end

  def test_outlines_crossing_with_no_corner_inside_each_other_overlap
    bar = [[-1, 1, 0], [4, 1, 0], [4, 2, 0], [-1, 2, 0]]
    post = [[1, -1, 1], [2, -1, 1], [2, 4, 1], [1, 4, 1]]
    assert OVERLAP.any?([[bar], [post]])
  end

  def test_outlines_sharing_an_edge_or_a_corner_do_not_overlap
    refute OVERLAP.any?([[square(0, 0, 3)], [square(3, 0, 3)]])
    refute OVERLAP.any?([[square(0, 0, 3)], [square(3, 3, 3)]])
  end

  def test_an_outline_in_a_concave_notch_does_not_overlap_but_one_over_the_arm_does
    refute OVERLAP.any?([[ell], [square(2, 2, 2, 1)]])
    assert OVERLAP.any?([[ell], [square(1, 1, 2, 1)]])
  end

  def test_an_outline_in_a_hole_does_not_overlap_and_one_across_its_edge_does
    ring = [square(0, 0, 6), square(2, 2, 2)]
    refute OVERLAP.any?([ring, [square(2.5, 2.5, 1, 1)]])
    assert OVERLAP.any?([ring, [square(1, 2.5, 2, 1)]])
  end

  def test_any_pair_among_several_is_enough
    assert OVERLAP.any?([[square(0, 0, 1)], [square(5, 5, 1)], [square(5.5, 5.5, 1, 3)]])
  end

  def test_a_shared_area_under_the_minimum_does_not_count
    refute OVERLAP.any?([[square(0, 0, 3)], [square(2.999, 0, 3, 1)]])
  end

  # Corners a float apart, as two Faces under their own transforms give, put a strip's middle exactly on a corner.
  def test_a_strip_sampled_on_a_corner_still_pairs_its_edges
    triangle = [[0.0, 0.0, 0.0], [2.0, 0.0, 0.0], [1.0, 1.0, 0.0]]
    x = 1.0.next_float
    inside = [[0.5, 0.1, 3.0], [x, 0.1, 3.0], [x, 0.4, 3.0], [0.5, 0.4, 3.0]]
    assert_equal 1.0, (1.0 + x) / 2.0
    assert OVERLAP.any?([[triangle], [inside]])
  end

  def test_a_single_outline_and_a_wall_seen_edge_on_do_not_overlap
    wall = [[1, 1, 0], [2, 2, 0], [2, 2, 3], [1, 1, 3]]
    refute OVERLAP.any?([[square(0, 0, 3)]])
    refute OVERLAP.any?([[square(0, 0, 3)], [wall]])
  end
end
