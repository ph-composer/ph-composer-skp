# frozen_string_literal: true

require_relative "client"

# Edge assignment with the panel closed, through the public API only. Select Edges natively first (in
# SketchUp, or with the bridge's development eval), then:
#   ThermalBridgeAssignmentWalkthrough.selection                the selected Edges as edges.selection reads them
#   ThermalBridgeAssignmentWalkthrough.assign("Parapet")        assigns the selection that type, one Undo step
#   ThermalBridgeAssignmentWalkthrough.clear                    clears the selection's assignments, one Undo step
#   ThermalBridgeAssignmentWalkthrough.replace("Footing", "Slab edge")
#                                                               deletes a type, moving its Edges to another
# Each write sends the references and values the selection read returned, so an Edge changed since refuses.
module ThermalBridgeAssignmentWalkthrough
  PREFIX = "ph_composer.thermal_bridges"

  module_function

  # The selected Edges, each as `{ path, type, quantity, copied, reason, refusal }` with the type's name.
  def selection
    names = type_names
    { "edges" => selected_rows.map do |row|
      values = row.fetch("values")
      { "path" => row.fetch("path"), "type" => names[values["thermal_bridge_type_id"]],
        "quantity" => values["quantity"], "copied" => row.fetch("copied"), "reason" => row.fetch("reason"),
        "refusal" => row.dig("write_refusal", "code") }
    end }
  end

  def assign(type_name, quantity: 1)
    write("edges.assign", "thermal_bridge_type_id" => type_id(type_name), "quantity" => quantity)
  end

  def clear
    write("edges.clear")
  end

  def replace(type_name, replacement_name)
    client = AuthoringExample::Client.new
    params = { "id" => type_id(type_name), "replacement_id" => replacement_name && type_id(replacement_name) }
    client.invoke("#{PREFIX}.types.delete", params)
  end

  def write(name, params = {})
    client = AuthoringExample::Client.new
    rows = selected_rows
    # An Edge no Zone holds has no reference to send; its reason is the refusal.
    if (unreachable = rows.find { |row| row["reference"].nil? })
      return { "status" => "refused", "code" => unreachable.fetch("reason"), "effect" => "none" }
    end

    targets = rows.map { |row| { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") } }
    client.invoke("#{PREFIX}.#{name}", params.merge("targets" => targets))
  end

  # Every selected Edge, read a bounded page at a time as an agent would.
  def selected_rows
    rows = []
    params = {}
    loop do
      page = read("#{PREFIX}.edges.selection", params)
      rows.concat(page.fetch("edges"))
      break unless page.fetch("next_cursor")

      params = { "cursor" => page.fetch("next_cursor") }
    end
    rows
  end

  def type_id(name)
    type_names.key(name) || raise(ArgumentError, "No Thermal Bridge Type is named #{name}.")
  end

  def type_names
    read("#{PREFIX}.types.all").fetch("records").to_h { |row| [row.fetch("id"), row.dig("values", "name")] }
  end

  def read(name, params = {})
    result = AuthoringExample::Client.new.query(name, params)
    raise "#{name} failed: #{result['code']} #{result['message']}" unless result["status"] == "completed"

    result.fetch("value")
  end
end
