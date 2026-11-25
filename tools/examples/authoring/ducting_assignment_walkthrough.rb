# frozen_string_literal: true

require_relative "client"

# Ducting groups and duct assignment with the panel closed, through the public API only, in a scratch Model with a
# Ventilator and a Duct Type (DuctTypesWalkthrough.run leaves DT-2):
#   DuctingAssignmentWalkthrough.create("ERV-1")      a new Ducting group linked to that Ventilator, opened for drawing
#   DuctingAssignmentWalkthrough.draw                 two connected lines in the open group, selected; on the host
#                                                     draw them with the Line tool instead (case M14c)
#   DuctingAssignmentWalkthrough.assign("DT-2", "outdoor_air")
#                                                     the selection as Outdoor air ducts, one Undo step
#   DuctingAssignmentWalkthrough.assign(nil, nil, 2)  the same ducts at quantity 2, their type and direction kept
#   DuctingAssignmentWalkthrough.selection            the selected Edges as ducts.selection reads them
#   DuctingAssignmentWalkthrough.clear                clears the selection's ducts, one Undo step
#   DuctingAssignmentWalkthrough.groups               every Ducting group with its Ventilator and duct count
# Each write sends the references and values the selection read returned, so an Edge changed since refuses.
module DuctingAssignmentWalkthrough
  PREFIX = "ph_composer.ducting"
  # From the ventilator up through the roof: 1.2 m along, then 0.6 m up.
  INTAKE = [[0, 0, 2400], [1200, 0, 2400], [1200, 0, 3000]].freeze

  module_function

  def create(ventilator_name)
    ventilators = read("ph_composer.mechanical.ventilators.all").fetch("records")
    ventilator = ventilators.find { |row| row.dig("values", "name") == ventilator_name }
    raise ArgumentError, "No Ventilator is named #{ventilator_name}." unless ventilator

    AuthoringExample::Client.new.invoke("#{PREFIX}.groups.create", "ventilator_id" => ventilator.fetch("id"))
  end

  # Two connected lines, given in millimetres, in `entities` (the open group), selected. SketchUp's internal unit is
  # the inch.
  def draw(entities = Sketchup.active_model.active_entities)
    points = INTAKE.map { |point| Geom::Point3d.new(*point.map { |mm| mm / 25.4 }) }
    lines = points.each_cons(2).map { |start, finish| entities.add_line(start, finish) }
    selection = Sketchup.active_model.selection
    selection.clear
    selection.add(lines)
    lines.map(&:persistent_id)
  end

  # Any of the three may be nil, which keeps each selected duct's own; a line with no assignment needs a type and a
  # direction.
  def assign(type_name, direction, quantity = nil)
    params = { "duct_type_id" => type_name && type_id(type_name), "direction" => direction, "quantity" => quantity }
    write("ducts.assign", params.compact)
  end

  def clear
    write("ducts.clear")
  end

  # The selected Edges, each as `{ path, type, direction, quantity, copied, reason, refusal }` with the type's name.
  def selection
    names = type_names
    selected_rows.map do |row|
      values = row.fetch("values")
      { "path" => row.fetch("path"), "type" => names[values["duct_type_id"]], "direction" => values["direction"],
        "quantity" => values["quantity"], "copied" => row.fetch("copied"), "reason" => row.fetch("reason"),
        "refusal" => row.dig("write_refusal", "code") }
    end
  end

  def groups
    read("#{PREFIX}.groups.all").fetch("groups").map do |row|
      { "path" => row.fetch("path"), "ventilator" => row.dig("values", "ventilator_id"),
        "ducts" => row.fetch("duct_count"), "findings" => row.fetch("findings") }
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
      page = read("#{PREFIX}.ducts.selection", params)
      rows.concat(page.fetch("edges"))
      break unless page.fetch("next_cursor")

      params = { "cursor" => page.fetch("next_cursor") }
    end
    rows
  end

  def type_id(name)
    type_names.key(name) || raise(ArgumentError, "No Duct Type is named #{name}.")
  end

  def type_names
    read("#{PREFIX}.duct_types.all").fetch("records").to_h { |row| [row.fetch("id"), row.dig("values", "name")] }
  end

  def read(name, params = {})
    result = AuthoringExample::Client.new.query(name, params)
    raise "#{name} failed: #{result['code']} #{result['message']}" unless result["status"] == "completed"

    result.fetch("value")
  end
end
