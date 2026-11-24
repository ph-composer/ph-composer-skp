# frozen_string_literal: true

require_relative "client"

# Run with the panel closed, through the public API only, in a scratch Model:
#   VentilatorsWalkthrough.run      creates two Ventilators, edits one, duplicates one and deletes one
#   VentilatorsWalkthrough.verify   reads ventilators.all back against the expected catalog
# Each action is one native Undo step, five in all; AuthoringExample.undo and .redo step through them in
# separate bridge calls, and `state` shows the catalog between steps.
module VentilatorsWalkthrough
  PREFIX = "ph_composer.mechanical.ventilators"

  USER_DATA = { "walkthrough" => { "kept" => ["original"] } }.freeze
  # The catalog after `run`, by name: sensible and latent recovery, electric efficiency in Wh/m³, quantity,
  # subsoil heat exchanger efficiency, source kind and user_data. The copy carries ERV-1's values and user_data.
  EXPECTED = {
    "ERV-1" => [0.85, 0.6, 0.45, 2, nil, "manual", USER_DATA],
    "ERV-1 (copy)" => [0.85, 0.6, 0.45, 2, nil, "derived", USER_DATA]
  }.freeze

  module_function

  def run
    client = AuthoringExample::Client.new
    steps = []
    discovered = PhComposer::API.discover.fetch("features").any? { |row| row["id"] == "ph_composer.mechanical" }
    steps << { "step" => "discover", "passed" => discovered }
    erv = invoke(client, steps, "create",
                 "values" => { "name" => "ERV-1", "sensible_heat_recovery" => 0.85, "latent_heat_recovery" => 0.6,
                               "electric_efficiency_wh_m3" => 0.45 },
                 "user_data" => USER_DATA).dig("value", "id")
    second = invoke(client, steps, "create",
                    "values" => { "name" => "ERV-2", "sensible_heat_recovery" => 0.75,
                                  "subsoil_heat_exchange_efficiency" => 0.2 }).dig("value", "id")
    invoke(client, steps, "update", "id" => erv, "values" => { "quantity" => 2 },
                                    "expected_values" => { "quantity" => 1 })
    invoke(client, steps, "duplicate", "id" => erv)
    invoke(client, steps, "delete", "id" => second)
    steps << { "step" => "read back", "passed" => verify.fetch("passed") }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # The catalog as ventilators.all reads it, in EXPECTED's shape.
  def state
    result = AuthoringExample::Client.new.query("#{PREFIX}.all")
    raise "ventilators.all failed: #{result['code']}" unless result["status"] == "completed"

    result.dig("value", "records").to_h do |row|
      values = row.fetch("values")
      [values.fetch("name"),
       values.values_at("sensible_heat_recovery", "latent_heat_recovery", "electric_efficiency_wh_m3", "quantity",
                        "subsoil_heat_exchange_efficiency") + [values.dig("source", "kind"), row.fetch("user_data")]]
    end
  end

  def verify
    found = state
    { "passed" => found == EXPECTED, "state" => found }
  end

  def invoke(client, steps, name, params)
    result = client.invoke("#{PREFIX}.#{name}", params)
    steps << { "step" => name, "passed" => result["effect"] == "committed", "code" => result["code"] }
    result
  end
end
