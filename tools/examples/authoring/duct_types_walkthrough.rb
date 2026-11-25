# frozen_string_literal: true

require_relative "client"

# Run with the panel closed, through the public API only, in a scratch Model:
#   DuctTypesWalkthrough.run      creates two Duct Types, makes one Rectangular, duplicates it and deletes the other
#   DuctTypesWalkthrough.verify   reads duct_types.all back against the expected catalog
#   DuctTypesWalkthrough.ids      each surviving type's id by name; pass them to verify after Redo or a reopen
# Each action is one native Undo step, five in all; AuthoringExample.undo and .redo step through them in separate
# bridge calls, and `state` shows the catalog between steps. Later ducts store these ids, so verify(ids) also holds
# them to the ids read before.
module DuctTypesWalkthrough
  PREFIX = "ph_composer.ducting.duct_types"

  USER_DATA = { "walkthrough" => { "kept" => ["original"] } }.freeze
  # DT-2 as `run` leaves it: every stored value, a 200 x 100 mm rectangular duct with 50.8 mm of insulation that is
  # not reflective, at 0.035 W/(m K). It was created Round, so its diameter must be gone.
  DT_2 = { "name" => "DT-2", "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" },
           "shape" => "rectangular", "width_mm" => 200.0, "height_mm" => 100.0, "insulation_thickness_mm" => 50.8,
           "insulation_conductivity_w_mk" => 0.035, "insulation_reflective" => false }.freeze
  # The catalog after `run`, one [values, user_data] per record in name order. The copy carries DT-2's values and
  # user_data.
  EXPECTED = [
    [DT_2, USER_DATA],
    [DT_2.merge("name" => "DT-2 (copy)", "source" => { "kind" => "derived" }), USER_DATA]
  ].freeze

  module_function

  def run
    client = AuthoringExample::Client.new
    steps = []
    discovered = PhComposer::API.discover.fetch("features").any? { |row| row["id"] == "ph_composer.ducting" }
    steps << { "step" => "discover", "passed" => discovered }
    first = invoke(client, steps, "create", "values" => { "name" => "DT-1" }).dig("value", "id")
    dt2 = invoke(client, steps, "create",
                 "values" => { "name" => "DT-2", "insulation_thickness_mm" => 50.8,
                               "insulation_conductivity_w_mk" => 0.035, "insulation_reflective" => false },
                 "user_data" => USER_DATA).dig("value", "id")
    invoke(client, steps, "update", "id" => dt2,
                                    "values" => { "shape" => "rectangular", "width_mm" => 200.0, "height_mm" => 100.0 },
                                    "expected_values" => { "shape" => "round", "diameter_mm" => 160.0 })
    invoke(client, steps, "duplicate", "id" => dt2)
    invoke(client, steps, "delete", "id" => first)
    steps << { "step" => "read back", "passed" => verify.fetch("passed") }
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end

  # The catalog as duct_types.all reads it, in EXPECTED's shape: one entry per record, so an extra one shows. An
  # unreadable Duct Type fails the read.
  def state
    records.map { |row| [row.fetch("values"), row.fetch("user_data")] }
           .sort_by { |values, _user_data| values.fetch("name") }
  end

  # Each record's id by its name, as duct_types.all reads them.
  def ids
    records.to_h { |row| [row.dig("values", "name"), row.fetch("id")] }
  end

  # The catalog against EXPECTED and, given `expected_ids` (from `ids`), every id as it was.
  def verify(expected_ids = nil)
    found = state
    found_ids = expected_ids && ids
    { "passed" => found == EXPECTED && (expected_ids.nil? || found_ids == expected_ids), "state" => found,
      "ids" => found_ids }.compact
  end

  def records
    result = AuthoringExample::Client.new.query("#{PREFIX}.all")
    raise "duct_types.all failed: #{result['code']}" unless result["status"] == "completed"

    unreadable = result.dig("value", "unreadable")
    raise "duct_types.all has unreadable records: #{unreadable}" unless unreadable.empty?

    result.dig("value", "records")
  end

  def invoke(client, steps, name, params)
    result = client.invoke("#{PREFIX}.#{name}", params)
    steps << { "step" => name, "passed" => result["effect"] == "committed", "code" => result["code"] }
    result
  end
end
