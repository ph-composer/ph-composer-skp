# frozen_string_literal: true

require_relative "client"

# The D3b-13 measurement: a Model of 50,000 Edges with 5,000 assigned, then the cost of the live schedule
# read and of a whole panel snapshot. Geometry is development setup; Zones, types and assignments are made
# through public actions. Run each line in its own bridge call, in an empty Model:
#   ThermalBridgeMeasurement.build      ten Zones of 417 one-metre boxes (50,040 Edges)
#   ThermalBridgeMeasurement.assign     the top perimeter of 125 boxes per Zone, five types, 250 Edges a call
#   ThermalBridgeMeasurement.measure    median milliseconds of each phase and of a snapshot, over `repeat` reads
module ThermalBridgeMeasurement
  API = PhComposer::API
  PREFIX = "ph_composer.thermal_bridges"
  ZONES = 10
  BOXES = 417
  ASSIGNED_BOXES = 125
  SIZE = 1000.mm
  PITCH = 2000.mm
  COLUMNS = 21
  TYPES = [["Parapet", 0.05], ["Slab edge", 0.12], ["Footing", -0.02], ["Balcony", 0.25], ["Corner", 0.03]].freeze

  module_function

  def build
    model = Sketchup.active_model
    unless model.entities.grep(Sketchup::Group).empty? && model.entities.grep(Sketchup::Edge).empty?
      raise "Build the measurement model in an empty Model."
    end

    model.start_operation("Build thermal-bridge measurement model", true)
    groups = Array.new(ZONES) do |index|
      group = model.entities.add_group
      group.name = "Measure #{index}"
      group.transformation = Geom::Transformation.translation([0, index * (BOXES / COLUMNS + 2) * PITCH, 0])
      group.entities.build { |builder| BOXES.times { |box| add_box(builder, box) } }
      group
    end
    model.commit_operation
    client = AuthoringExample::Client.new
    groups.each do |group|
      checked(client, "ph_composer.zones.make", "parent_path" => [], "entity_ids" => [group.persistent_id],
                                                "name" => group.name)
    end
    TYPES.each do |name, psi|
      checked(client, "#{PREFIX}.types.create", "values" => { "name" => name, "psi_w_mk" => psi })
    end
    { "zones" => groups.length, "edges" => edge_count(model) }
  end

  def add_box(builder, index)
    x = (index % COLUMNS) * PITCH
    y = (index / COLUMNS) * PITCH
    corners = [[0, 0], [SIZE, 0], [SIZE, SIZE], [0, SIZE]].map { |dx, dy| [x + dx, y + dy] }
    bottom = corners.map { |cx, cy| Geom::Point3d.new(cx, cy, 0) }
    top = corners.map { |cx, cy| Geom::Point3d.new(cx, cy, SIZE) }
    builder.add_face(bottom.reverse)
    builder.add_face(top)
    4.times { |side| builder.add_face(bottom[side], bottom[(side + 1) % 4], top[(side + 1) % 4], top[side]) }
  end

  # The four top Edges of the first ASSIGNED_BOXES boxes in each Zone, each Zone one type.
  def assign
    model = Sketchup.active_model
    client = AuthoringExample::Client.new
    types = client.query("#{PREFIX}.types.all").dig("value", "records").map { |row| row.fetch("id") }.sort
    zones = client.query("ph_composer.zones.all").dig("value", "zones")
    written = 0
    zones.each_with_index do |zone, index|
      group_id = zone.dig("reference", "zone_path").last
      group = model.entities.grep(Sketchup::Group).find { |item| item.persistent_id == group_id }
      tops = group.entities.grep(Sketchup::Edge).select do |edge|
        edge.start.position.z == SIZE && edge.end.position.z == SIZE && box_of(edge) < ASSIGNED_BOXES
      end
      tops.each_slice(PhComposer::ThermalBridges::Assignment::GESTURE_EDGE_LIMIT) do |slice|
        targets = slice.map do |edge|
          { "reference" => zone.fetch("reference").merge("entity_path" => [edge.persistent_id], "entity_id" => nil) }
        end
        result = checked(client, "#{PREFIX}.edges.assign", "targets" => targets,
                                                           "thermal_bridge_type_id" => types[index % types.length])
        written += result.dig("value", "edge_ids").length
      end
    end
    { "assigned" => written, "edges" => edge_count(model) }
  end

  def box_of(edge)
    point = edge.start.position
    ((point.y / PITCH).floor * COLUMNS) + (point.x / PITCH).floor
  end

  # Median milliseconds of each phase of the read, and of the whole panel snapshot, which the panel waits
  # for on every refresh. The phases are the walk, Zones' containment and Face reads in pages, and the
  # pure schedule; `schedule_all` is the registered read end to end.
  def measure(repeat: 5)
    model = Sketchup.active_model
    client = AuthoringExample::Client.new
    scan = PhComposer::ThermalBridges::Scan
    tagged = nil
    phases = {
      "walk" => -> { tagged = scan.walk(model).first },
      "containment" => -> { pages(client, "ph_composer.zones.containment", tagged.map(&:path)) },
      "host_context" => lambda {
        paths = tagged.flat_map { |edge| edge.face_ids.map { |id| edge.path[0...-1] + [id] } }.uniq
        pages(client, "ph_composer.zones.faces.host_context", paths)
      },
      "schedule_all" => -> { client.query("#{PREFIX}.schedule.all") },
      "schedule_list" => -> { client.query("#{PREFIX}.schedule.list") },
      "snapshot" => -> { PhComposer::Snapshot.build(client.context) }
    }
    timings = phases.transform_values { |phase| median(Array.new(repeat) { elapsed(&phase) }) }
    whole = client.query("#{PREFIX}.schedule.all").fetch("value")
    timings.merge("edges" => edge_count(model), "assigned" => tagged.length, "runs" => whole.fetch("runs").length,
                  "sketchup" => Sketchup.version, "repeat" => repeat)
  end

  def pages(client, name, paths)
    paths.each_slice(PhComposer::Pages::MAXIMUM_LIMIT) do |slice|
      result = client.query(name, "paths" => slice)
      raise "#{name}: #{result['code']} #{result['message']}" unless result["status"] == "completed"
    end
  end

  def elapsed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
  end

  def median(values)
    sorted = values.sort
    sorted[sorted.length / 2]
  end

  def edge_count(model)
    model.entities.grep(Sketchup::Group).sum { |group| group.entities.grep(Sketchup::Edge).length }
  end

  def checked(client, name, params)
    result = client.invoke(name, params)
    raise "#{name}: #{result['code']} #{result['message']}" unless result["effect"] == "committed"

    result
  end
end
