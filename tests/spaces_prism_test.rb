# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# A Volume's preview prism: per Floor Segment, the outer loop projected to its mean height and extruded by
# the Volume's height, in world metres.
class SpacesPrismTest < PhComposerTestCase
  include SpaceFixtures

  PRISM = PhComposer::Spaces::Prism

  def test_a_rectangle_gives_a_base_a_top_and_four_sides
    shape = PRISM.call([[rectangle(0, 0, 4, 3)]], 2.5).first
    base, top, *sides = shape.polygons
    assert_equal 4, sides.length
    assert(base.all? { |point| point[2].zero? })
    assert(top.all? { |point| (point[2] - 2.5).abs < 1e-12 })
    assert_in_delta 30.0, PRISM.volume_m3([shape], 2.5), 1e-9
  end

  def test_the_outline_is_each_floor_edge_each_top_edge_and_one_vertical_per_corner
    shape = PRISM.call([[rectangle(0, 0, 4, 3)]], 2.5).first
    lines = PRISM.outline([shape])
    assert_equal 12, lines.length
    floor, top, vertical = lines.first(3)
    assert_equal [0.0, 0.0], floor.map { |point| point[2].round(9) }
    assert_equal [2.5, 2.5], top.map { |point| point[2].round(9) }
    assert_equal [0.0, 2.5], vertical.map { |point| point[2].round(9) }
    assert_equal vertical.first[0, 2], vertical.last[0, 2]
  end

  def test_the_outline_rings_a_hole_and_shows_none_of_the_bases_cuts
    outer = rectangle(0, 0, 4, 4)
    hole = rectangle(1, 1, 2, 2)
    shape = PRISM.call([[outer, hole]], 2.0).first
    assert_operator shape.base.length, :>, 1, "the base is cut around the hole"
    assert_equal 24, PRISM.outline([shape]).length, "three lines for each of the eight ring edges"
  end

  def test_an_l_shape_has_one_side_per_edge_and_encloses_the_net_volume
    loop = [[0, 0, 0], [4, 0, 0], [4, 2, 0], [2, 2, 0], [2, 4, 0], [0, 4, 0]]
    shape = PRISM.call([[loop]], 3.0).first
    assert_equal 6, shape.sides.length
    net_area = PhComposer::Spaces::Metrics.projected_area_m2([loop])
    assert_in_delta net_area * 3.0, PRISM.volume_m3([shape], 3.0), 1e-9
  end

  def test_a_sloped_segment_sits_on_its_projected_base_at_its_mean_height
    loop = [[0, 0, 0], [4, 0, 0], [4, 2, 1], [0, 2, 1]]
    shape = PRISM.call([[loop]], 2.0).first
    assert(shape.base.flatten(1).all? { |point| (point[2] - 0.5).abs < 1e-12 })
    assert(shape.top.flatten(1).all? { |point| (point[2] - 2.5).abs < 1e-12 })
    assert_in_delta 16.0, PRISM.volume_m3([shape], 2.0), 1e-9
  end

  def test_world_coordinates_follow_a_rotated_wrapper
    face = floor_face(101, rectangle(1, 0, 2, 1))
    # A quarter turn about z, column-major as SketchUp's Transformation#to_a is.
    turn = Geom::Transformation.new([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    loops = PhComposer::FaceCapture.call(face, turn).loops_m
    base = PRISM.call([loops], 2.5).first.base.first
    xs = base.map { |point| point[0].round(9) }
    ys = base.map { |point| point[1].round(9) }
    assert_equal [-1.0, 0.0], [xs.min, xs.max]
    assert_equal [1.0, 3.0], [ys.min, ys.max]
  end

  def test_a_hole_is_cut_from_the_caps_and_walled_so_the_prism_encloses_the_net_volume
    hole = rectangle(1, 1, 2, 2).reverse
    shape = PRISM.call([[rectangle(0, 0, 4, 4), hole]], 2.5).first
    net_area = PhComposer::Spaces::Metrics.projected_area_m2([rectangle(0, 0, 4, 4), hole])
    assert_in_delta net_area * 2.5, PRISM.volume_m3([shape], 2.5), 1e-9
    assert_in_delta 30.0, PRISM.volume_m3([shape], 2.5), 1e-9
    assert_equal 8, shape.sides.length, "four outer sides and four around the hole"
    assert(shape.base.all? { |polygon| polygon.length.between?(3, 4) }, "convex pieces of three or four points")
  end

  def test_a_volume_with_no_height_has_no_prism
    assert_empty PRISM.call([[rectangle(0, 0, 1, 1)]], nil)
  end
end
