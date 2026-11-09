# frozen_string_literal: true

# The drawn-rectangle Zones the Convert to Window Type tests share.
module WindowConvertFixtures
  WALL = [[0, 0], [8, 0], [8, 6], [0, 6]].freeze

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

  def host_reference
    assignment_faces.find { |row| row.dig("reference", "entity_path") == [@host.persistent_id] }.fetch("reference")
  end
end
