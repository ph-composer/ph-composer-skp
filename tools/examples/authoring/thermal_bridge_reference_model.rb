# frozen_string_literal: true

require_relative "client"
require_relative "windows_walkthrough"

# The thermal-bridge reference model, built in an empty Model for a host gate. Geometry and the native
# selection are development setup outside the product API; Zones, types and the Window Unit are made
# through public actions. Run each line in its own bridge call:
#   ThermalBridgeReferenceModel.build        two adjacent Zones, a Zone in a turned wrapper, the five types,
#                                            a Window Unit on Zone A's south wall, the Balcony line across
#                                            Zone B's south wall and a line at the Model root, every Face
#                                            classified as Zones suggests; answers the named Edge paths
#   ThermalBridgeReferenceModel.paths        the same names, read again from the live Model
#   ThermalBridgeReferenceModel.select("zone_a_roof")
#                                            opens the Zone and selects those Edges, as a user would
# Zone A is 5 x 4 x 3 m from the origin and Zone B 4 x 4 x 3 m beside it at x = 5 m; Zone W is
# 2 x 2 x 2 m inside a Group turned 30 degrees about z at x = 20 m. Paths and selection are read with the
# edit path closed, since positions read inside an open context are world coordinates
# (context/SKETCHUP_HOST_BEHAVIOR.md); both close it first.
module ThermalBridgeReferenceModel
  API = PhComposer::API
  TYPES = [["Parapet", 0.05, "15-Ambient"], ["Slab edge", 0.12, "16-Perimeter"], ["Footing", -0.02, "17-FS/BC"],
           ["Balcony", 0.25, "15-Ambient"], ["Draft", nil, "15-Ambient"]].freeze

  module_function

  def build
    model = Sketchup.active_model
    # The blank template's scale figure may stay; any geometry would confuse the named paths.
    unless model.entities.grep(Sketchup::Group).empty? && model.entities.grep(Sketchup::Edge).empty?
      raise "Build the reference model in an empty Model."
    end

    client = AuthoringExample::Client.new
    zone_a = AuthoringExample.box(model.entities, "Zone A", [0, 0, 0], 5000.mm, 4000.mm, 3000.mm)
    zone_b = AuthoringExample.box(model.entities, "Zone B", [5000.mm, 0, 0], 4000.mm, 4000.mm, 3000.mm)
    wrapper = model.entities.add_group
    wrapper.name = "Turned wrapper"
    wrapper.transformation = Geom::Transformation.translation([20_000.mm, 0, 0]) *
                             Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
    zone_w = AuthoringExample.box(wrapper.entities, "Zone W", [0, 0, 0], 2000.mm, 2000.mm, 2000.mm)
    # Drawn before classification, so the two halves of the wall it splits are each classified.
    zone_b.entities.add_line([0, 0, 1500.mm], [4000.mm, 0, 1500.mm])
    model.entities.add_line([0, -2000.mm, 0], [3000.mm, -2000.mm, 0])
    # Make Zone acts in the open edit context, so Zone W is made with the wrapper open.
    [[nil, zone_a], [nil, zone_b], [wrapper, zone_w]].each do |parent, group|
      model.active_path = parent && [parent]
      checked(client, "ph_composer.zones.make", "parent_path" => parent ? [parent.persistent_id] : [],
                                                "entity_ids" => [group.persistent_id], "name" => group.name)
    end
    model.active_path = nil
    TYPES.each do |name, psi, group|
      checked(client, "ph_composer.thermal_bridges.types.create",
              "values" => { "name" => name, "psi_w_mk" => psi, "group" => group })
    end
    classify(client)
    place_window(client, zone_a)
    paths
  end

  # Every Face of every Zone, classified with the face type and boundary condition Zones suggests. Make Zone
  # may have classified some already.
  def classify(client)
    query(client, "ph_composer.zones.faces.all").fetch("faces").each do |face|
      next if face.fetch("values").slice("face_type", "boundary_condition") == face.fetch("suggested")

      intent = %w[face_type boundary_condition].to_h do |field|
        [field, { "mode" => "set", "value" => face.dig("suggested", field) }]
      end
      checked(client, "ph_composer.zones.faces.classify", "faces" => [face.fetch("reference")], "intent" => intent,
                                                          "expected_values" => face.fetch("values"))
    end
  end

  # Named root-to-Edge paths in the live Model.
  def paths
    model = Sketchup.active_model
    model.active_path = nil if model.active_path
    zones = %w[Zone\ A Zone\ B].to_h { |name| [name, model.entities.grep(Sketchup::Group).find { |g| g.name == name }] }
    wrapper = model.entities.grep(Sketchup::Group).find { |group| group.name == "Turned wrapper" }
    zone_w = wrapper.entities.grep(Sketchup::Group).first
    unit = zones.fetch("Zone A").entities.grep(Sketchup::ComponentInstance).first
    {
      "zone_a_roof" => sides(zones.fetch("Zone A"), 3000.mm, %w[south west north]),
      "zone_a_roof_east" => sides(zones.fetch("Zone A"), 3000.mm, %w[east]),
      "zone_a_ground" => sides(zones.fetch("Zone A"), 0, %w[south west north]),
      "zone_b_roof" => sides(zones.fetch("Zone B"), 3000.mm, %w[south east north]),
      "zone_b_roof_west" => sides(zones.fetch("Zone B"), 3000.mm, %w[west]),
      "zone_b_ground" => sides(zones.fetch("Zone B"), 0, %w[south east north]),
      "zone_b_balcony" => sides(zones.fetch("Zone B"), 1500.mm, %w[south]),
      "zone_w_roof" => sides(zone_w, 2000.mm, %w[south east north west]).map { |path| [wrapper.persistent_id] + path },
      "window_edge" => unit && [[zones.fetch("Zone A").persistent_id, unit.persistent_id,
                                 unit.definition.entities.grep(Sketchup::Edge).first.persistent_id]],
      "root_edge" => [[model.entities.grep(Sketchup::Edge).first.persistent_id]]
    }
  end

  # Opens the Zone holding the named Edges and selects them there, as a user would before assigning.
  def select(name)
    model = Sketchup.active_model
    targets = paths.fetch(name)
    containers = resolve(model, targets.first[0...-1])
    model.active_path = containers.empty? ? nil : containers
    model.selection.clear
    model.selection.add(targets.map { |path| resolve(model, path).last })
    targets.length
  end

  def resolve(model, path)
    entities = model.entities
    path.map do |id|
      entity = entities.find { |item| item.persistent_id == id }
      entities = entity.entities if entity.is_a?(Sketchup::Group)
      entities = entity.definition.entities if entity.is_a?(Sketchup::ComponentInstance)
      entity
    end
  end

  # The roof or ground perimeter Edges of a box Group on the named sides, as root-to-Edge paths from the
  # Group, in the Group's own coordinates.
  def sides(group, height, names)
    depth = group.entities.grep(Sketchup::Edge).map { |edge| edge.end.position.y }.max
    width = group.entities.grep(Sketchup::Edge).map { |edge| edge.end.position.x }.max
    tests = { "south" => ->(a, b) { a.y.zero? && b.y.zero? }, "north" => ->(a, b) { a.y == depth && b.y == depth },
              "west" => ->(a, b) { a.x.zero? && b.x.zero? }, "east" => ->(a, b) { a.x == width && b.x == width } }
    names.map do |side|
      edge = group.entities.grep(Sketchup::Edge).find do |item|
        a = item.start.position
        b = item.end.position
        a.z == height && b.z == height && tests.fetch(side).call(a, b)
      end
      [group.persistent_id, edge.persistent_id]
    end
  end

  # A Window Unit centred on Zone A's south wall, through the Windows walkthrough's synthetic type.
  def place_window(client, zone_a)
    authored = WindowAuthoringWalkthrough.run
    wall = zone_a.entities.grep(Sketchup::Face).find do |face|
      face.vertices.all? { |vertex| vertex.position.y.zero? }
    end
    faces = query(client, "ph_composer.zones.faces.list", "zone_paths" => [[zone_a.persistent_id]]).fetch("faces")
    host = faces.find { |row| row.dig("reference", "entity_path") == [wall.persistent_id] }.fetch("reference")
    checked(client, "ph_composer.windows.units.place", "host" => host, "type_id" => authored.fetch("type_id"),
                                                       "anchor" => "sill_center",
                                                       "offsets" => { "x_m" => 2.5, "y_m" => 0.9 })
  end

  def query(client, name, params = {})
    result = client.query(name, params)
    raise "#{name}: #{result['code']} #{result['message']}" unless result["status"] == "completed"

    result.fetch("value")
  end

  def checked(client, name, params)
    result = client.invoke(name, params)
    raise "#{name}: #{result['code']} #{result['message']}" unless result["effect"] == "committed"

    result
  end
end
