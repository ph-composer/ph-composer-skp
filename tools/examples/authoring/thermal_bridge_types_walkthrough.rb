# frozen_string_literal: true

require_relative "client"

# Run with the panel closed, through the public API only, in a scratch Model:
#   ThermalBridgeTypesWalkthrough.run      creates three types, edits, duplicates and deletes one
#   ThermalBridgeTypesWalkthrough.verify   reads types.all back against the expected catalog
# Each action is one native Undo step, six in all; AuthoringExample.undo and .redo step through them
# in separate bridge calls, and `state` shows the catalog between steps.
module ThermalBridgeTypesWalkthrough
  PREFIX = "ph_composer.thermal_bridges.types"

  # The catalog after `run`, by name: psi-value, group and source kind.
  EXPECTED = {
    "Walkthrough parapet" => [0.15, "15-Ambient", "manual"],
    "Walkthrough slab edge" => [-0.02, "16-Perimeter", "manual"],
    "Walkthrough parapet (copy)" => [0.15, "15-Ambient", "derived"]
  }.freeze

  module_function

  def run
    client = AuthoringExample::Client.new
    steps = []
    discovered = PhComposer::API.discover.fetch("features").any? { |row| row["id"] == "ph_composer.thermal_bridges" }
    steps << { "step" => "discover", "passed" => discovered }
    parapet = create(client, steps, "name" => "Walkthrough parapet", "psi_w_mk" => 0.12)
    create(client, steps, "name" => "Walkthrough slab edge", "psi_w_mk" => -0.02, "group" => "16-Perimeter")
    balcony = create(client, steps, "name" => "Walkthrough balcony")
    invoke(client, steps, "update", "id" => parapet, "values" => { "psi_w_mk" => 0.15 },
                                    "expected_values" => { "psi_w_mk" => 0.12 })
    invoke(client, steps, "duplicate", "id" => parapet)
    invoke(client, steps, "delete", "id" => balcony)
    steps << { "step" => "read back", "passed" => verify.fetch("passed") }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # The catalog as types.all reads it: name to psi-value, group and source kind.
  def state
    result = AuthoringExample::Client.new.query("#{PREFIX}.all")
    raise "types.all failed: #{result['code']}" unless result["status"] == "completed"

    result.dig("value", "records").to_h do |row|
      values = row.fetch("values")
      [values.fetch("name"), [values["psi_w_mk"], values.fetch("group"), values.dig("source", "kind")]]
    end
  end

  def verify
    found = state
    { "passed" => found == EXPECTED, "state" => found }
  end

  def create(client, steps, values)
    invoke(client, steps, "create", "values" => values).dig("value", "id")
  end

  def invoke(client, steps, name, params)
    result = client.invoke("#{PREFIX}.#{name}", params)
    steps << { "step" => name, "passed" => result["effect"] == "committed", "code" => result["code"] }
    result
  end
end
