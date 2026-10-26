# frozen_string_literal: true

require_relative "test_helper"

class PickPointTest < PhComposerTestCase
  def setup
    super
    @view = Sketchup.active_model.active_view
    @face = Sketchup::Face.new(9_501, {}, :points => [Geom::Point3d.new(0, 0, 0),
                                                      Geom::Point3d.new(20, 0, 0), Geom::Point3d.new(20, 20, 0)])
    @view.picks[[4, 5]] = [@face]
    def @view.pickray(_x, _y)
      [Geom::Point3d.new(4, 5, 100), Geom::Vector3d.new(0, 0, -1)]
    end
  end

  def test_world_point_uses_one_pick_and_the_same_face_path
    helper = @view.pick_helper
    helper.instance_variable_set(:@calls, 0)
    def helper.do_pick(x, y)
      @calls += 1
      super
    end
    picked = PhComposer::Pick.face_point(@view, 4, 5)
    assert_equal [@face], picked.fetch(:path)
    assert_equal [4.0, 5.0, 0.0], coordinates(picked.fetch(:point))
    assert_equal 1, helper.instance_variable_get(:@calls)
  end

  def test_active_path_and_nonuniform_transform_return_world_intersection
    parent = Sketchup::Group.new(9_502, Sketchup::Entities.new([@face]))
    parent.transformation = Geom::Transformation.translation([0, 0, 12]) * Geom::Transformation.scaling(2, 3, 4)
    Sketchup.active_model.entities << parent
    Sketchup.active_model.active_path = [parent]
    picked = PhComposer::Pick.face_point(@view, 4, 5)
    assert_equal [parent, @face], picked.fetch(:path)
    assert_equal [4.0, 5.0, 12.0], coordinates(picked.fetch(:point))
  end

  def test_an_edge_pick_skips_faces_and_a_face_pick_skips_edges
    edge = Sketchup::Edge.new(9_503, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(20, 0, 0))
    parent = Sketchup::Group.new(9_504, Sketchup::Entities.new([@face, edge]))
    Sketchup.active_model.entities << parent
    Sketchup.active_model.active_path = [parent]
    @view.picks[[6, 7]] = [[@face], [edge]]
    @view.picks[[8, 9]] = [[edge], [@face]]

    assert_equal [parent, edge], PhComposer::Pick.edge_path(@view, 6, 7)
    assert_equal [parent, @face], PhComposer::Pick.face_path(@view, 8, 9)
    assert_nil PhComposer::Pick.edge_path(@view, 4, 5)
  end

  def test_no_face_parallel_ray_and_plane_behind_camera_return_no_point
    assert_nil PhComposer::Pick.face_point(@view, 8, 9)
    def @view.pickray(_x, _y)
      [Geom::Point3d.new(4, 5, 100), Geom::Vector3d.new(1, 0, 0)]
    end
    assert_nil PhComposer::Pick.face_point(@view, 4, 5)
    def @view.pickray(_x, _y)
      [Geom::Point3d.new(4, 5, 100), Geom::Vector3d.new(0, 0, 1)]
    end
    assert_nil PhComposer::Pick.face_point(@view, 4, 5)
  end

  def test_sheared_face_plane_uses_inverse_transpose_not_a_vector_transform
    matrix = Geom::Transformation.scaling(2, 3, 4).to_a
    matrix[2] = 1.0
    matrix[14] = 12.0
    parent = Sketchup::Group.new(9_503, Sketchup::Entities.new([@face]))
    parent.transformation = Geom::Transformation.new(matrix)
    @view.picks[[4, 5]] = [parent, @face]
    picked = PhComposer::Pick.face_point(@view, 4, 5)
    assert_equal [4.0, 5.0, 14.0], coordinates(picked.fetch(:point))
  end

  def coordinates(point)
    [point.x, point.y, point.z]
  end
end
