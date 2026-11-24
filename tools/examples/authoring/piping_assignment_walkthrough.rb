# frozen_string_literal: true

require_relative "client"

# Piping groups and pipe assignment with the panel closed, through the public API only, in a scratch Model with a Hot
# Water System and a Pipe Type (PipeTypesWalkthrough.run makes PT-1):
#   PipingAssignmentWalkthrough.create("HWS-1")       a new Piping group linked to that System, opened for drawing
#   PipingAssignmentWalkthrough.draw                  three connected lines in the open group, selected; on the host
#                                                     draw them with the Line tool instead (case M13b, H2)
#   PipingAssignmentWalkthrough.assign("PT-1", "trunk", "multiplier" => 12)
#                                                     the selection as pipes, one Undo step
#   PipingAssignmentWalkthrough.selection             the selected Edges as pipes.selection reads them
#   PipingAssignmentWalkthrough.clear                 clears the selection's pipes, one Undo step
#   PipingAssignmentWalkthrough.groups                every Piping group with its System and pipe count
# Each write sends the references and values the selection read returned, so an Edge changed since refuses.
module PipingAssignmentWalkthrough
  PREFIX = "ph_composer.piping"
  RISER = [[0, 0, 0], [0, 0, 3000], [0, 0, 6000], [0, 0, 9000]].freeze

  module_function

  def create(system_name)
    systems = read("ph_composer.mechanical.hot_water_systems.all").fetch("records")
    system = systems.find { |row| row.dig("values", "name") == system_name }
    raise ArgumentError, "No Hot Water System is named #{system_name}." unless system

    AuthoringExample::Client.new.invoke("#{PREFIX}.groups.create", "hot_water_system_id" => system.fetch("id"))
  end

  # Three connected lines up a 9 m riser, given in millimetres, in `entities` (the open group), selected. SketchUp's
  # internal unit is the inch.
  def draw(entities = Sketchup.active_model.active_entities)
    points = RISER.map { |point| Geom::Point3d.new(*point.map { |mm| mm / 25.4 }) }
    lines = points.each_cons(2).map { |start, finish| entities.add_line(start, finish) }
    selection = Sketchup.active_model.selection
    selection.clear
    selection.add(lines)
    lines.map(&:persistent_id)
  end

  def assign(type_name, role, role_values = {})
    write("pipes.assign", { "pipe_type_id" => type_id(type_name), "role" => role }.merge(role_values))
  end

  def clear
    write("pipes.clear")
  end

  # The selected Edges, each as `{ path, type, role, values, copied, reason, refusal }` with the type's name.
  def selection
    names = type_names
    selected_rows.map do |row|
      values = row.fetch("values")
      { "path" => row.fetch("path"), "type" => names[values["pipe_type_id"]], "role" => values["role"],
        "values" => values, "copied" => row.fetch("copied"), "reason" => row.fetch("reason"),
        "refusal" => row.dig("write_refusal", "code") }
    end
  end

  def groups
    read("#{PREFIX}.groups.all").fetch("groups").map do |row|
      { "path" => row.fetch("path"), "system" => row.dig("values", "hot_water_system_id"),
        "pipes" => row.fetch("pipe_count"), "findings" => row.fetch("findings") }
    end
  end

  def write(name, params = {})
    rows = selected_rows
    if (unreachable = rows.find { |row| row["reference"].nil? || row["write_refusal"] })
      return { "status" => "refused", "code" => unreachable["reason"] || unreachable.dig("write_refusal", "code"),
               "effect" => "none" }
    end

    targets = rows.map { |row| { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") } }
    AuthoringExample::Client.new.invoke("#{PREFIX}.#{name}", params.merge("targets" => targets))
  end

  # Every selected Edge, read a bounded page at a time as an agent would.
  def selected_rows
    rows = []
    params = {}
    loop do
      page = read("#{PREFIX}.pipes.selection", params)
      rows.concat(page.fetch("edges"))
      break unless page.fetch("next_cursor")

      params = { "cursor" => page.fetch("next_cursor") }
    end
    rows
  end

  def type_id(name)
    type_names.key(name) || raise(ArgumentError, "No Pipe Type is named #{name}.")
  end

  def type_names
    read("#{PREFIX}.pipe_types.all").fetch("records").to_h { |row| [row.fetch("id"), row.dig("values", "name")] }
  end

  def read(name, params = {})
    result = AuthoringExample::Client.new.query(name, params)
    raise "#{name} failed: #{result['code']} #{result['message']}" unless result["status"] == "completed"

    result.fetch("value")
  end
end
