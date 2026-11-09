# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "../src/ph_composer/features/windows/units/convert_rectangles"

class WindowConvertRectanglesTest < PhComposerTestCase
  R = PhComposer::Windows::Units::ConvertRectangles
  Plane = PhComposer::Windows::Placement::Plane

  WALL = [[0.0, 0.0, 0.0], [8.0, 0.0, 0.0], [8.0, 0.0, 6.0], [0.0, 0.0, 6.0]].freeze
  HOST = PhComposer::FaceGeometry.build(:loops_m => [WALL], :normal => [0.0, -1.0, 0.0])

  def plane
    Plane.new(HOST)
  end

  def extent(left, bottom, width, height)
    R::Extent.new(:left => left, :right => left + width, :bottom => bottom, :top => bottom + height)
  end

  def wall(left, bottom, width, height)
    right = left + width
    top = bottom + height
    [[left, 0.0, bottom], [right, 0.0, bottom], [right, 0.0, top], [left, 0.0, top]]
  end

  def tilted(degrees)
    run = Math.cos(degrees * Math::PI / 180.0)
    rise = Math.sin(degrees * Math::PI / 180.0)
    [[0.0, 0.0], [run, rise], [run - rise, rise + run], [-rise, run]].map { |x, z| [x, 0.0, z] }
  end

  def test_a_side_split_by_a_t_junction_is_one_side
    tall = wall(0.0, 0.0, 1.0, 2.0)
    split = tall[0, 2] + [[1.0, 0.0, 1.0]] + tall[2, 2]
    assert_equal tall, R.corners(split)
  end

  def test_a_corner_off_square_is_no_rectangle
    assert_nil R.corners([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 1.0], [0.1, 0.0, 1.0]])
    assert_nil R.corners([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 1.0], [0.5, 0.0, 1.5], [0.0, 0.0, 1.0]])
  end

  def test_alignment_is_to_the_hosts_right_and_up
    assert R.aligned?(wall(1.0, 1.0, 1.2, 1.5), plane)
    assert R.aligned?(tilted(0.05), plane), "inside the 0.1 degree tolerance"
    refute R.aligned?(tilted(0.2), plane)
    tilt = 1.0 * Math::PI / 180.0
    run = Math.cos(tilt)
    rise = Math.sin(tilt)
    rotated = [[0.0, 0.0], [run, rise], [run - rise, rise + run], [-rise, run]].map { |x, z| [x, 0.0, z] }
    refute R.aligned?(rotated, plane)
  end

  def test_one_rectangle_gives_its_width_and_height
    layout = R.layout([extent(2.0, 1.0, 1.2, 1.5)])
    assert_equal [[1.2], [1.5], [[[0, 0], [0, 0]]]], [layout.columns_m, layout.rows_m, layout.spans]
  end

  def test_a_row_of_three_gives_three_columns_left_to_right
    layout = R.layout([extent(0.0, 0.0, 0.6, 1.5), extent(0.6, 0.0, 1.2, 1.5), extent(1.8, 0.0, 0.6, 1.5)])
    assert_equal [0.6, 1.2, 0.6], layout.columns_m
    assert_equal [[[0, 0], [0, 0]], [[0, 0], [1, 1]], [[0, 0], [2, 2]]], layout.spans
  end

  def test_a_tall_rectangle_beside_two_stacked_spans_both_rows_and_rows_read_top_down
    layout = R.layout([extent(0.0, 0.0, 1.0, 2.0), extent(1.0, 1.2, 0.5, 0.8), extent(1.0, 0.0, 0.5, 1.2)])
    assert_equal [1.0, 0.5], layout.columns_m
    assert_equal [0.8, 1.2], layout.rows_m
    assert_equal [[[0, 1], [0, 0]], [[0, 0], [1, 1]], [[1, 1], [1, 1]]], layout.spans
  end

  def test_an_l_a_gap_and_an_overlap_do_not_tile
    assert_nil R.layout([extent(0.0, 0.0, 1.0, 1.0), extent(1.0, 0.0, 1.0, 1.0), extent(0.0, 1.0, 1.0, 1.0)]), "L"
    assert_nil R.layout([extent(0.0, 0.0, 1.0, 1.0), extent(1.5, 0.0, 1.0, 1.0)]), "gap"
    assert_nil R.layout([extent(0.0, 0.0, 1.0, 1.0), extent(0.5, 0.0, 1.0, 1.0)]), "overlap"
  end

  def test_rectangles_group_by_shared_edge_keys
    assert_equal [[0, 1, 2], [3]], R.clusters([[1, 2], [2, 3], [3, 4], [9]]) { true }
    assert_equal [[0], [1]], R.clusters([[1], [1]]) { false }, "a shared Edge joins only what may join"
  end

  def test_type_matching_is_within_one_millimetre_and_needs_the_same_spans
    drawn = R::Layout.new(:columns_m => [1.2], :rows_m => [1.5], :spans => [[[0, 0], [0, 0]]])
    near = R::Layout.new(:columns_m => [1.2009], :rows_m => [1.4991], :spans => [[[0, 0], [0, 0]]])
    far = R::Layout.new(:columns_m => [1.2011], :rows_m => [1.5], :spans => [[[0, 0], [0, 0]]])
    incomplete = R::Layout.new(:columns_m => [nil], :rows_m => [1.5], :spans => [[[0, 0], [0, 0]]])
    assert R.same_layout?(drawn, near, 0.001)
    refute R.same_layout?(drawn, far, 0.001)
    refute R.same_layout?(drawn, incomplete, 0.001), "a Type with a missing band matches nothing"
  end
end
