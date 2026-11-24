# frozen_string_literal: true

require_relative "client"

# Run with the panel closed, through the public API only, in a scratch Model:
#   VentilatorsWalkthrough.run      creates two Ventilators, edits one, duplicates one and deletes one
#   VentilatorsWalkthrough.verify   reads ventilators.all back against the expected catalog
# Each action is one native Undo step, five in all; AuthoringExample.undo and .redo step through them in
# separate bridge calls, and `state` shows the catalog between steps.
#
# Then, in a Model with Zones named "Zone A" and "Zone B" (one may sit in a turned Group, and a copy made
# independent keeps its name, so every occurrence of each name is served):
#   VentilatorsWalkthrough.serve          creates ERV-2 again, assigns ERV-1 to Zone A and ERV-2 to Zone B,
#                                         replaces Zone A's with ERV-2, clears Zone B, assigns ERV-1 to it, and
#                                         deletes ERV-1 with ERV-2 as its replacement: seven Undo steps
#   VentilatorsWalkthrough.serve_verify   reads serves.all and the catalog back: every occurrence served by ERV-2
module VentilatorsWalkthrough
  PREFIX = "ph_composer.mechanical.ventilators"
  SERVES = "ph_composer.mechanical.serves"
  ZONES = ["Zone A", "Zone B"].freeze
  SERVE_STEPS = 7

  USER_DATA = { "walkthrough" => { "kept" => ["original"] } }.freeze
  # ERV-1 as `run` leaves it: every stored value, efficiency in Wh/m³ and temperatures in °C.
  ERV_1 = { "name" => "ERV-1", "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" },
            "quantity" => 2, "sensible_heat_recovery" => 0.85, "latent_heat_recovery" => 0.6,
            "electric_efficiency_wh_m3" => 0.45, "frost_protection_reqd" => true,
            "temperature_below_defrost_used_c" => -5.0, "in_conditioned_space" => true }.freeze
  # The catalog after `run`, one [values, user_data] per record in name order. The copy carries ERV-1's values and
  # user_data.
  EXPECTED = [
    [ERV_1, USER_DATA],
    [ERV_1.merge("name" => "ERV-1 (copy)", "source" => { "kind" => "derived" }), USER_DATA]
  ].freeze

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

  # The catalog as ventilators.all reads it, in EXPECTED's shape: one entry per record, so an extra one shows. An
  # unreadable Ventilator fails the read.
  def state
    result = AuthoringExample::Client.new.query("#{PREFIX}.all")
    raise "ventilators.all failed: #{result['code']}" unless result["status"] == "completed"

    unreadable = result.dig("value", "unreadable")
    raise "ventilators.all has unreadable records: #{unreadable}" unless unreadable.empty?

    result.dig("value", "records").map { |row| [row.fetch("values"), row.fetch("user_data")] }
          .sort_by { |values, _user_data| values.fetch("name") }
  end

  def verify
    found = state
    { "passed" => found == EXPECTED, "state" => found }
  end

  def invoke(client, steps, name, params, prefix = PREFIX)
    result = client.invoke("#{prefix}.#{name}", params)
    steps << { "step" => name, "passed" => result["effect"] == "committed", "code" => result["code"] }
    result
  end

  # ---------------------------------------------------------------- what serves the Zones

  def serve(names = ZONES)
    client = AuthoringExample::Client.new
    steps = []
    zone_a, zone_b = names
    erv1 = ventilator_id("ERV-1")
    erv2 = invoke(client, steps, "create", "values" => { "name" => "ERV-2" }).dig("value", "id")
    assign = lambda do |name, item, replace = false|
      params = { "zones" => targets(name), "slot" => "ventilator_id", "item_id" => item }
      params["replace"] = true if replace
      invoke(client, steps, "assign", params, SERVES)
    end
    assign.call(zone_a, erv1)
    assign.call(zone_b, erv2)
    assign.call(zone_a, erv2, true)
    invoke(client, steps, "clear", { "zones" => targets(zone_b) }, SERVES)
    assign.call(zone_b, erv1)
    invoke(client, steps, "delete", "id" => erv1, "replacement_id" => erv2)
    steps << { "step" => "read back", "passed" => serve_verify(names).fetch("passed") }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # Each occurrence of the named Zones as [name, occurrence path, the name of its Ventilator or nil], and the
  # catalog's names.
  def serve_state(names = ZONES)
    zones = serves_rows.select { |row| names.include?(row.fetch("name")) }.map do |row|
      [row.fetch("name"), row.dig("reference", "zone_path"), row.fetch("items").first&.fetch("name")]
    end
    { "zones" => zones.sort_by { |name, path, _item| [name, path] },
      "ventilators" => state.map { |values, _user_data| values.fetch("name") } }
  end

  def serve_verify(names = ZONES)
    found = serve_state(names)
    passed = names.all? { |name| found.fetch("zones").any? { |row| row.first == name } } &&
             found.fetch("zones").all? { |row| row.last == "ERV-2" } &&
             found.fetch("ventilators") == ["ERV-1 (copy)", "ERV-2"]
    { "passed" => passed, "state" => found }
  end

  # Every occurrence of the Zone named `name`, with its slots as last read.
  def targets(name)
    serves_rows.select { |row| row.fetch("name") == name }.map do |row|
      { "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }
    end
  end

  def serves_rows
    result = AuthoringExample::Client.new.query("#{SERVES}.all")
    raise "serves.all failed: #{result['code']}" unless result["status"] == "completed"

    result.dig("value", "zones")
  end

  def ventilator_id(name)
    result = AuthoringExample::Client.new.query("#{PREFIX}.all")
    result.dig("value", "records").find { |row| row.dig("values", "name") == name }.fetch("id")
  end
end
