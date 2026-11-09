# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "support/assembly_assignment_fixtures"

class WindowConvertReviewTest < PhComposerTestCase
  include WindowRecordFixtures
  include AssemblyAssignmentFixtures

  QUERY = "ph_composer.windows.units.convert_review"
  WALL = [[0, 0], [8, 0], [8, 6], [0, 6]].freeze

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([W]) unless PhComposer::Registry.installed?(W::FEATURE_ID)
    @next_id = 5000
  end

  def inches(x, z, y = 0)
    Geom::Point3d.new(x / 0.0254, y / 0.0254, z / 0.0254)
  end

  def ring(left, bottom, width, height)
    [[left, bottom], [left + width, bottom], [left + width, bottom + height], [left, bottom + height]]
  end

  def next_id
    @next_id += 1
  end

  def edges_of(rings, shared)
    rings.map do |points|
      points.each_with_index.map do |point, index|
        following = points[(index + 1) % points.length]
        key = [point, following].sort
        shared[key] ||= Sketchup::Edge.new(next_id, inches(*point), inches(*following))
      end
    end
  end

  # A wall with holes in a new Zone; the holes' Edges are shared with the rectangles drawn in them.
  def zone_with(rectangles, outer: WALL, holes: nil)
    shared = {}
    rectangle_edges = edges_of(rectangles, shared)
    host = Sketchup::Face.new(next_id, {}, :points => outer.map { |point| inches(*point) },
                                           :holes => (holes || hole_rings(rectangles)).map { |ring|
                                             ring.map { |point| inches(*point) }
                                           },
                                           :edges => outer_edges(rectangles, rectangle_edges))
    faces = rectangles.zip(rectangle_edges).map do |points, edges|
      Sketchup::Face.new(next_id, {}, :points => points.map { |point| inches(*point) }, :edges => edges)
    end
    @group = Sketchup::Group.new(next_id, Sketchup::Entities.new([host] + faces + rectangle_edges.flatten.uniq))
    @model.entities << @group
    result = assignment_invoke("ph_composer.zones.make", "parent_path" => [], "entity_ids" => [@group.persistent_id])
    assert_equal "completed", result.fetch("status"), result.inspect
    @host = host
    faces
  end

  # The Edges not shared by two rectangles: those the host's hole holds.
  def outer_edges(_rectangles, rectangle_edges)
    all = rectangle_edges.flatten
    all.select { |edge| all.count(edge) == 1 }
  end

  def hole_rings(rectangles)
    rectangles.length == 1 ? rectangles : []
  end

  def path(face)
    [@group.persistent_id, face.persistent_id]
  end

  def review(*paths)
    assignment_query(QUERY, "paths" => paths)
  end

  def left_out_codes(result)
    result.fetch("left_out").map { |row| row.fetch("code") }
  end

  def host_reference
    assignment_faces.find { |row| row.dig("reference", "entity_path") == [@host.persistent_id] }.fetch("reference")
  end

  def test_one_rectangle_on_a_zone_wall_reads_its_size_host_and_geometry_and_writes_nothing
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    before = @model.operations.length
    result = review(path(face))
    group = result.fetch("groups").first
    assert_empty result.fetch("left_out")
    assert_equal [[1.2], [1.5]], [group.fetch("columns_m"), group.fetch("rows_m")]
    assert_equal host_reference, group.fetch("host")
    assert_equal 0, group.fetch("layout_index")
    assert_nil group.fetch("preselected_type_id")
    source = group.fetch("sources").first
    assert_equal path(face), source.fetch("path")
    assert_equal [[0, 0], [0, 0]], source.values_at("row_span", "column_span")
    assert_match(/\Asha256:/, source.fetch("digest"))
    assert_equal 4, source.fetch("outline_m").length
    assert_equal before, @model.operations.length
  end

  def test_three_rectangles_sharing_edges_are_one_group_of_three_columns
    faces = zone_with([ring(1, 1, 0.6, 1.5), ring(1.6, 1, 1.2, 1.5), ring(2.8, 1, 0.6, 1.5)],
                      :holes => [ring(1, 1, 2.4, 1.5)])
    result = review(*faces.map { |face| path(face) })
    assert_equal 1, result.fetch("groups").length
    group = result.fetch("groups").first
    assert_equal [0.6, 1.2, 0.6], group.fetch("columns_m")
    assert_equal [[0, 0], [1, 1], [2, 2]], group.fetch("sources").map { |row| row.fetch("column_span") }
  end

  def test_an_l_is_one_left_out_row_naming_its_faces
    faces = zone_with([ring(1, 1, 1, 1), ring(2, 1, 1, 1), ring(1, 2, 1, 1)], :holes => [])
    result = review(*faces.map { |face| path(face) })
    assert_empty result.fetch("groups")
    row = result.fetch("left_out").first
    assert_equal "window.mull_not_rectangular", row.fetch("code")
    assert_equal faces.map { |face| path(face) }.sort, row.fetch("paths").sort
  end

  def test_a_tall_rectangle_beside_two_stacked_uses_the_t_junction_as_one_side
    tall = ring(1, 1, 1, 2)
    t_tall = [[1, 1], [2, 1], [2, 2], [2, 3], [1, 3]]
    faces = zone_with([t_tall, ring(2, 1, 0.5, 1), ring(2, 2, 0.5, 1)], :holes => [ring(1, 1, 1.5, 2)])
    result = review(*faces.map { |face| path(face) })
    assert_empty result.fetch("left_out"), tall.inspect
    group = result.fetch("groups").first
    assert_equal [[1, 0.5], [1, 1]], [group.fetch("columns_m"), group.fetch("rows_m")]
    assert_equal [0, 1], group.fetch("sources").find { |row| row.fetch("path") == path(faces.first) }.fetch("row_span")
  end

  def test_a_face_that_is_no_rectangle_and_a_missing_path_are_each_left_out
    face = zone_with([[[2, 1], [3, 1], [3, 2], [2.5, 3], [2, 2]]]).first
    result = review(path(face), [@group.persistent_id, 999_999])
    assert_equal %w[target.not_found window.not_rectangle].sort, left_out_codes(result).sort
  end

  def test_a_rectangle_with_a_hole_a_non_face_and_a_locked_group_are_each_left_out
    face = zone_with([ring(2, 1, 1, 1)]).first
    holed = Sketchup::Face.new(next_id, {}, :points => ring(5, 1, 2, 2).map { |point| inches(*point) },
                                            :holes => [ring(5.5, 1.5, 0.5, 0.5).map { |point| inches(*point) }])
    edge = Sketchup::Edge.new(next_id, inches(0, 0), inches(1, 0))
    @model.entities << holed << edge
    @group.locked = true
    assert_equal %w[target.locked target.wrong_kind window.not_rectangle],
                 left_out_codes(review(path(face), [holed.persistent_id], [edge.persistent_id])).sort
  end

  def test_the_review_reads_alike_in_any_order
    faces = zone_with([ring(4, 1, 1, 1), ring(1, 1, 1, 1)], :holes => [])
    forward = review(*faces.map { |face| path(face) })
    assert_equal forward, review(*faces.reverse.map { |face| path(face) })
  end

  def test_a_neighbour_left_unselected_counts_as_the_hosts_edge
    faces = zone_with([ring(1, 1, 0.6, 1.5), ring(1.6, 1, 0.6, 1.5)], :holes => [ring(1, 1, 1.2, 1.5)])
    assert_equal ["window.convert_on_boundary"], left_out_codes(review(path(faces.first)))
  end

  def test_a_rotated_rectangle_is_left_out
    a = Math::PI / 6
    across = [Math.cos(a), Math.sin(a)]
    up = [-Math.sin(a), Math.cos(a)]
    points = [[2, 2], [2 + across[0], 2 + across[1]], [2 + across[0] + up[0], 2 + across[1] + up[1]],
              [2 + up[0], 2 + up[1]]]
    face = zone_with([points]).first
    assert_equal ["window.not_aligned"], left_out_codes(review(path(face)))
  end

  def test_a_rectangle_on_the_floor_line_is_left_out_as_on_boundary
    u_shape = [[0, 0], [2, 0], [2, 2], [3, 2], [3, 0], [8, 0], [8, 6], [0, 6]]
    face = zone_with([ring(2, 0, 1, 2)], :outer => u_shape, :holes => []).first
    row = review(path(face)).fetch("left_out").first
    assert_equal "window.convert_on_boundary", row.fetch("code")
    assert_includes row.fetch("message"), "inset"
  end

  def test_a_whole_zone_face_is_not_drawn_on_one
    face = Sketchup::Face.new(next_id, {}, :points => WALL.map { |point| inches(*point) }, :edges => [])
    @group = Sketchup::Group.new(next_id, Sketchup::Entities.new([face]))
    @model.entities << @group
    assignment_invoke("ph_composer.zones.make", "parent_path" => [], "entity_ids" => [@group.persistent_id])
    assert_equal ["target.wrong_zone"], left_out_codes(review(path(face)))
  end

  def loose_rectangle(left, bottom, width, height, offset_y: 0.0)
    points = ring(left, bottom, width, height).map { |x, z| inches(x, z, offset_y) }
    face = Sketchup::Face.new(next_id, {}, :points => points)
    @model.entities << face
    [face.persistent_id]
  end

  def test_a_rectangle_outside_every_zone_coplanar_and_within_finds_its_host_by_geometry
    zone_with([ring(2, 1, 1, 1)])
    result = review(loose_rectangle(5, 2, 1.2, 1.5))
    assert_empty result.fetch("left_out")
    assert_equal host_reference, result.fetch("groups").first.fetch("host")
    assert_equal [[1.2], [1.5]], result.fetch("groups").first.values_at("columns_m", "rows_m")
  end

  def test_a_rectangle_outside_every_zone_off_plane_or_at_the_edge_is_left_out
    zone_with([ring(2, 1, 1, 1)])
    off_plane = loose_rectangle(5, 2, 1, 1, :offset_y => 0.5)
    at_edge = loose_rectangle(7, 2, 1, 1)
    past = loose_rectangle(7.5, 2, 1, 1)
    assert_equal %w[target.wrong_zone window.convert_on_boundary window.overhang],
                 left_out_codes(review(off_plane, at_edge, past)).sort
  end

  def test_a_rectangle_touching_a_hole_is_on_the_boundary_and_one_across_it_overhangs
    zone_with([], :holes => [ring(2, 1, 1, 1)])
    touching = loose_rectangle(3, 1, 1, 1)
    across = loose_rectangle(2.5, 1, 1, 1)
    assert_equal %w[window.convert_on_boundary window.overhang], left_out_codes(review(touching, across)).sort
  end

  def test_rectangles_outside_every_zone_mull_by_their_shared_edge
    zone_with([ring(2, 1, 1, 1)])
    shared = {}
    rings = [ring(5, 2, 0.6, 1.5), ring(5.6, 2, 0.6, 1.5)]
    faces = rings.zip(edges_of(rings, shared)).map do |points, edges|
      face = Sketchup::Face.new(next_id, {}, :points => points.map { |point| inches(*point) }, :edges => edges)
      @model.entities << face
      face
    end
    groups = review(*faces.map { |face| [face.persistent_id] }).fetch("groups")
    assert_equal [[0.6, 0.6]], groups.map { |group| group.fetch("columns_m") }
  end

  def test_two_walls_of_a_corner_sharing_an_edge_stay_two_rows
    shared_edge = Sketchup::Edge.new(next_id, inches(1, 1), inches(1, 2))
    # One rectangle in the wall plane, one square to it, sharing the vertical Edge at x = 1.
    wall = Sketchup::Face.new(next_id, {}, :points => ring(0, 1, 1, 1).map { |point| inches(*point) },
                                           :edges => [shared_edge])
    side = Sketchup::Face.new(next_id, {}, :points => [inches(1, 1), inches(1, 1, 1), inches(1, 2, 1), inches(1, 2)],
                                           :edges => [shared_edge])
    @model.entities << wall << side
    assert_equal 2, review([wall.persistent_id], [side.persistent_id]).fetch("left_out").length
  end

  def two_zone_faces
    left = Sketchup::Face.new(next_id, {}, :points => ring(0, 0, 4, 6).map { |point| inches(*point) })
    right = Sketchup::Face.new(next_id, {}, :points => ring(4, 0, 4, 6).map { |point| inches(*point) })
    @group = Sketchup::Group.new(next_id, Sketchup::Entities.new([left, right]))
    @model.entities << @group
    assignment_invoke("ph_composer.zones.make", "parent_path" => [], "entity_ids" => [@group.persistent_id])
  end

  def test_a_rectangle_across_two_coplanar_zone_faces_is_ambiguous
    two_zone_faces
    assert_equal ["window.host_ambiguous"], left_out_codes(review(loose_rectangle(3, 2, 2, 1)))
  end

  def test_surface_host_is_refused_with_placements_code
    assignment_pair(7000)
    @group = @model.entities.to_a.find { |entity| entity.persistent_id == 7000 }
    host = @group.entities.to_a.grep(Sketchup::Face).first
    points = [[1, 1], [2, 1], [2, 2], [1, 2]].map { |y, z| Geom::Point3d.new(0, y / 0.0254, z / 0.0254) }
    edges = points.each_with_index.map { |point, index| Sketchup::Edge.new(next_id, point, points[(index + 1) % 4]) }
    edges.each { |edge| edge.attach_face(host) }
    face = Sketchup::Face.new(next_id, {}, :points => points, :edges => edges)
    @group.entities << face
    assert_equal ["window.surface_host"], left_out_codes(review(path(face)))
  end

  def test_same_size_groups_share_a_layout_and_a_matching_type_is_preselected_alphabetically
    faces = zone_with([ring(1, 1, 1.2, 1.5), ring(4, 1, 1.2, 1.5), ring(4, 3.5, 2, 1)], :holes => [])
    [%w[Zebra 1.2], %w[alpha 1.2005], ["Too wide", "1.21"]].each do |name, width|
      result = assignment_invoke("ph_composer.windows.types.create",
                                 "values" => { "name" => name, "columns_m" => [width.to_f], "rows_m" => [1.5] })
      assert_equal "completed", result.fetch("status"), result.inspect
    end
    groups = review(*faces.map { |face| path(face) }).fetch("groups")
    assert_equal [0, 0, 2], groups.map { |group| group.fetch("layout_index") }
    assert_equal %w[alpha Zebra], groups.first.fetch("matching_types").map { |row| row.fetch("name") }
    assert_equal groups.first.fetch("matching_types").first.fetch("id"), groups.first.fetch("preselected_type_id")
    assert_empty groups.last.fetch("matching_types")
  end

  def test_a_mixed_selection_keeps_every_good_group_and_lists_the_rest
    faces = zone_with([ring(1, 1, 1, 1), [[3, 1], [4, 1], [4, 2], [3.5, 3], [3, 2]]], :holes => [])
    result = review(*faces.map { |face| path(face) })
    assert_equal 1, result.fetch("groups").length
    assert_equal ["window.not_rectangle"], left_out_codes(result)
  end

  def test_an_existing_window_on_the_plane_is_left_out_as_overlap
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    type = assignment_invoke("ph_composer.windows.types.create", "values" => { "name" => "Placed" })
    placed = assignment_invoke("ph_composer.windows.units.place",
                               "host" => host_reference, "type_id" => type.dig("value", "id"),
                               "anchor" => "sill_center", "offsets" => { "x_m" => 6.0, "y_m" => 1.0 })
    assert_equal "completed", placed.fetch("status"), placed.inspect
    assert_empty review(path(face)).fetch("left_out")
    assert_equal ["window.overlap"], left_out_codes(review(loose_rectangle(5.5, 1.5, 1, 0.5)))
  end
end
