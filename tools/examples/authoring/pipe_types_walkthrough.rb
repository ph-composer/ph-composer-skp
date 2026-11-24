# frozen_string_literal: true

require_relative "client"

# Run with the panel closed, through the public API only, in a scratch Model:
#   PipeTypesWalkthrough.run      creates two Pipe Types, edits one, duplicates one and deletes one
#   PipeTypesWalkthrough.verify   reads pipe_types.all back against the expected catalog
# Each action is one native Undo step, five in all; AuthoringExample.undo and .redo step through them in separate
# bridge calls, and `state` shows the catalog between steps.
module PipeTypesWalkthrough
  PREFIX = "ph_composer.piping.pipe_types"

  USER_DATA = { "walkthrough" => { "kept" => ["original"] } }.freeze
  # PT-1 as `run` leaves it: every stored value, a 3/4 in PEX pipe with 25.4 mm of insulation.
  PT_1 = { "name" => "PT-1", "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" },
           "material" => 6, "diameter_mm" => 19.05, "insulation_thickness_mm" => 25.4,
           "insulation_conductivity_w_mk" => 0.035, "insulation_reflective" => true, "insulation_quality" => 1 }.freeze
  # The catalog after `run`, one [values, user_data] per record in name order. The copy carries PT-1's values and
  # user_data.
  EXPECTED = [
    [PT_1, USER_DATA],
    [PT_1.merge("name" => "PT-1 (copy)", "source" => { "kind" => "derived" }), USER_DATA]
  ].freeze

  module_function

  def run
    client = AuthoringExample::Client.new
    steps = []
    discovered = PhComposer::API.discover.fetch("features").any? { |row| row["id"] == "ph_composer.piping" }
    steps << { "step" => "discover", "passed" => discovered }
    pt1 = invoke(client, steps, "create",
                 "values" => { "name" => "PT-1", "material" => 6, "insulation_thickness_mm" => 25.4,
                               "insulation_conductivity_w_mk" => 0.035 },
                 "user_data" => USER_DATA).dig("value", "id")
    second = invoke(client, steps, "create",
                    "values" => { "name" => "PT-2", "insulation_thickness_mm" => 0.0 }).dig("value", "id")
    invoke(client, steps, "update", "id" => pt1, "values" => { "diameter_mm" => 19.05 },
                                    "expected_values" => { "diameter_mm" => 12.7 })
    invoke(client, steps, "duplicate", "id" => pt1)
    invoke(client, steps, "delete", "id" => second)
    steps << { "step" => "read back", "passed" => verify.fetch("passed") }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # The catalog as pipe_types.all reads it, in EXPECTED's shape: one entry per record, so an extra one shows. An
  # unreadable Pipe Type fails the read.
  def state
    result = AuthoringExample::Client.new.query("#{PREFIX}.all")
    raise "pipe_types.all failed: #{result['code']}" unless result["status"] == "completed"

    unreadable = result.dig("value", "unreadable")
    raise "pipe_types.all has unreadable records: #{unreadable}" unless unreadable.empty?

    result.dig("value", "records").map { |row| [row.fetch("values"), row.fetch("user_data")] }
          .sort_by { |values, _user_data| values.fetch("name") }
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
