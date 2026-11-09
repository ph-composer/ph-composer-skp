# frozen_string_literal: true

# Synthetic Spaces fixtures written straight to the entity stores, for tests of reads that need no
# operation. Lengths are given in metres and stored in SketchUp inches.
module SpaceFixtures
  INCHES = 1.0 / 0.0254
  ZONES = PhComposer::Zones
  SPACES = PhComposer::Spaces

  def floor_face(persistent_id, corners_m, record = nil)
    points = corners_m.map { |x, y, z| Geom::Point3d.new(x * INCHES, y * INCHES, (z || 0) * INCHES) }
    face = Sketchup::Face.new(persistent_id, {}, :points => points)
    SPACES::FLOOR_SEGMENT_STORE.write(face, record) if record
    face
  end

  def rectangle(x0, y0, width, depth, z = 0)
    [[x0, y0, z], [x0 + width, y0, z], [x0 + width, y0 + depth, z], [x0, y0 + depth, z]]
  end

  def segment_record(letter, weighting_factor: 1.0, net_area_factor: 1.0)
    { "id" => "fsg_#{letter * 12}", "schema_version" => 1, "display_name" => "",
      "weighting_factor" => weighting_factor, "net_area_factor" => net_area_factor }
  end

  def volume_record(letter, number: 1, height: 2.5)
    record = { "id" => "vol_#{letter * 12}", "schema_version" => 1, "number" => number, "display_name" => "",
               "floor_id" => "flr_#{letter * 12}" }
    height ? record.merge("avg_ceiling_height_m" => height) : record
  end

  def space_record(letter, number:, name: "", airflows: {})
    { "id" => "spc_#{letter * 12}", "schema_version" => 1, "name" => name, "number" => number,
      "default_height_m" => 2.5, "next_volume_sequence" => 2 }.merge(airflows)
  end

  # Locked, as Spaces leaves every Volume it creates: its protection.
  def volume_group(persistent_id, record, faces, locked: true)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(faces), :locked => locked)
    SPACES::VOLUME_STORE.write(group, record) if record
    group
  end

  def space_group(persistent_id, record, children, transformation: nil)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children), :transformation => transformation)
    SPACES::SPACE_STORE.write(group, record) if record
    group
  end

  def zone_group(persistent_id, letter, children, transformation: nil)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children), :transformation => transformation,
                                                                                 :name => "Zone #{letter}")
    ZONES::ZONE_STORE.write(group, { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => "Zone #{letter}",
                                     "building_segment" => "Main Building", "level" => "L1",
                                     "ground_depth_mm" => 0.0 })
    host_children(children, "zon_#{letter * 12}")
    group
  end

  # The Spaces a fixture draws inside a Zone Group are hosted in it, as Create Space leaves them, through
  # any Group between.
  def host_children(children, zone_id)
    children.grep(Sketchup::Group).each do |child|
      record = SPACES::SPACE_STORE.read(child)
      SPACES::SPACE_STORE.write(child, record.merge("zone_id" => zone_id)) if record && !record.key?("zone_id")
      host_children(child.entities.to_a, zone_id)
    end
  end

  # The reference model of the Spaces acceptance register: Zone A with 101 Living, 102 Bath and 103 Hall
  # (two Volumes, one counting nothing), Zone B with 201 Loft on a sloped Floor Segment.
  def reference_model
    living = space_group(1100, space_record("L", :number => "101", :name => "Living",
                                                 :airflows => { "v_sup_m3h" => 60.0 }),
                         [volume_group(1110, volume_record("L"), [floor_face(1111, rectangle(0, 0, 3, 4),
                                                                             segment_record("L"))])])
    bath = space_group(1200, space_record("B", :number => "102", :name => "Bath",
                                               :airflows => { "v_eta_m3h" => 40.0 }),
                       [volume_group(1210, volume_record("B", :height => 2.4),
                                     [floor_face(1211, rectangle(3, 0, 2, 2), segment_record("B"))])])
    hall = space_group(1300, space_record("H", :number => "103", :name => "Hall",
                                               :airflows => { "v_tran_m3h" => 20.0 }),
                       [volume_group(1310, volume_record("H"), [floor_face(1311, rectangle(3, 2, 2, 2),
                                                                           segment_record("H"))]),
                        volume_group(1320, volume_record("I", :number => 2, :height => 5.0),
                                     [floor_face(1321, rectangle(0, 4, 1, 2),
                                                 segment_record("I", :weighting_factor => 0.0))])])
    loft = space_group(2100, space_record("F", :number => "201", :name => "Loft"),
                       [volume_group(2110, volume_record("F", :height => 3.0),
                                     [floor_face(2111, [[10, 0, 0], [13, 0, 0], [13, 4, 2], [10, 4, 2]],
                                                 segment_record("F"))])])
    @model.entities << zone_group(1000, "A", [living, bath, hall]) << zone_group(2000, "B", [loft])
  end
end
