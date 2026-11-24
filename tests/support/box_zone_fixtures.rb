# frozen_string_literal: true

# Box-shaped Zones for export tests: each a 3 m high box of classified Faces with a ground floor, optionally one
# Space on that floor. The including test provides SpaceFixtures, `@model`, `@assembly_id` (an Assembly every Face
# names), `query`, `invoke` and `completed`.
module BoxZoneFixtures
  Z = PhComposer::Zones

  def box(base, letter, name, segment, (x_min, x_max, y_min, y_max), space: true, split_west: false,
          adiabatic_north: false, net_area_factor: 1.0, weighting_factor: 1.0, airflows: {})
    children = box_faces(x_min, x_max, y_min, y_max, split_west).each_with_index.map do |(type, normal, loop), index|
      face = Sketchup::Face.new(base + index + 1, {}, :points => loop.map { |xyz| metres(xyz) },
                                                      :normal => Geom::Vector3d.new(*normal))
      boundary = if type == "Floor" then "Ground"
                 elsif adiabatic_north && normal == [0, 1, 0] then "Adiabatic"
                 else "Outdoors"
                 end
      Z::Faces::FACE_STORE.write(face, "id" => format("fac_%<letter>s%<number>011d", :letter => letter,
                                                                                     :number => index + 1),
                                       "schema_version" => 1, "face_type" => type, "boundary_condition" => boundary,
                                       "assembly_id" => @assembly_id, "user_data" => {}, "extension_data" => {})
      face
    end
    faces = children.dup
    if space
      # The Zone's floor Face is its Space's Floor Segment, as Create Space leaves it.
      floor = children.shift
      floor_record = segment_record(letter, :net_area_factor => net_area_factor, :weighting_factor => weighting_factor)
      SpaceFixtures::SPACES::FLOOR_SEGMENT_STORE.write(floor, floor_record)
      children << space_group(base + 50, space_record(letter, :number => "1", :name => name, :airflows => airflows),
                              [volume_group(base + 60, volume_record(letter), [floor], :locked => false)])
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(children), :name => name)
    zone = { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name, "building_segment" => segment,
             "level" => "L1", "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {} }
    Z::ZONE_STORE.write(group, zone)
    stamp = Z::Schema.stamp(zone)
    faces.each { |face| Z::STAMP_STORE.write(face, stamp) }
    host_children(children, zone.fetch("id"))
    group
  end

  # Floor, roof, then the walls west, east, south and north, outward normals; with `split_west` the west wall
  # is two Faces, split at y = 4 m.
  def box_faces(x0, x1, y0, y1, split_west)
    west = if split_west
             [[[x0, y0, 0], [x0, y0, 3], [x0, 4, 3], [x0, 4, 0]], [[x0, 4, 0], [x0, 4, 3], [x0, y1, 3], [x0, y1, 0]]]
           else
             [[[x0, y0, 0], [x0, y0, 3], [x0, y1, 3], [x0, y1, 0]]]
           end
    [["Floor", [0, 0, -1], [[x0, y0, 0], [x0, y1, 0], [x1, y1, 0], [x1, y0, 0]]],
     ["RoofCeiling", [0, 0, 1], [[x0, y0, 3], [x1, y0, 3], [x1, y1, 3], [x0, y1, 3]]]] +
      west.map { |loop| ["Wall", [-1, 0, 0], loop] } +
      [["Wall", [1, 0, 0], [[x1, y0, 0], [x1, y1, 0], [x1, y1, 3], [x1, y0, 3]]],
       ["Wall", [0, -1, 0], [[x0, y0, 0], [x1, y0, 0], [x1, y0, 3], [x0, y0, 3]]],
       ["Wall", [0, 1, 0], [[x0, y1, 0], [x0, y1, 3], [x1, y1, 3], [x1, y1, 0]]]]
  end

  def metres(xyz)
    Geom::Point3d.new(*xyz.map { |value| value * SpaceFixtures::INCHES })
  end

  # Each Surface pair's Assembly from its first side by id, so the other side holds it reversed.
  def assign_pair_assemblies
    rows = query("ph_composer.zones.faces.all").fetch("faces")
    pairs = rows.select { |row| row.dig("values", "boundary_condition") == "Surface" }
    pairs.group_by { |row|
      [row.dig("reference", "entity_id"), row.dig("values", "adjacency", "counterpart", "entity_id")].sort
    }.each_value do |sides|
      side = sides.min_by { |row| row.dig("reference", "entity_id") }
      completed(invoke("ph_composer.zones.faces.assign_assembly",
                       "assembly_id" => @assembly_id,
                       "targets" => [{ "reference" => side.fetch("reference"),
                                       "expected_values" => side.fetch("values") }]))
    end
  end

  def box_group(name)
    @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) && entity.name == name }
  end

  # Every classified Face in the Zone, its Space's floor among them.
  def zone_faces(name, entities = box_group(name).entities.to_a)
    entities.flat_map do |entity|
      next zone_faces(name, entity.entities.to_a) if entity.is_a?(Sketchup::Group)

      entity.is_a?(Sketchup::Face) && Z::Faces::FACE_STORE.read(entity) ? [entity] : []
    end
  end
end
