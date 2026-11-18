# frozen_string_literal: true

require_relative "../authoring/client"

# Run with the panel closed, through the public API only, in a scratch Model with no site and no climate:
#   ClimateWalkthrough.run_hand      enters a climate by hand with gaps, completes it, checks that Restore
#                                    refuses for it, and clears it: three Undo steps
#   ClimateStationSeed.seed          (station_seed.rb) writes a synthetic station climate with no file behind
#                                    it: one Undo step
#   ClimateWalkthrough.run_station   sets the site near the station, edits one cell, restores it, then moves
#                                    the site out of the Phius limits: four Undo steps
#   ClimateWalkthrough.run_attach(id) with the site set and no climate: lists the climate data folders, lists
#                                    the folder `id`'s stations nearest first, attaches the nearest one that
#                                    passes the Phius limits and reads its source as found: one Undo step
#   ClimateWalkthrough.state         the compact state the Undo and Redo steps are checked against
#   ClimateWalkthrough.verify        `state` against the last row of TRACE; works in a fresh process
# TRACE is the state after each Undo step in order, newest first, so the host recipe and the offline test read
# the same table.
module ClimateWalkthrough
  PREFIX = "ph_composer.climate"
  EDITABLE = %w[name station_latitude_deg station_longitude_deg station_elevation_m daily_temp_swing_k
                wind_speed_m_s monthly peak_loads].freeze
  MONTHLY_ROWS = %w[air_c dewpoint_c sky_c rad_north_kwh_m2 rad_east_kwh_m2 rad_south_kwh_m2 rad_west_kwh_m2
                    rad_global_kwh_m2].freeze
  PEAK_ROWS = %w[air_c dewpoint_c sky_c rad_north_w_m2 rad_east_w_m2 rad_south_w_m2 rad_west_w_m2
                 rad_global_w_m2].freeze
  CASES = %w[heat_1 heat_2 cool_1].freeze
  # Synthetic values, no project or station data. The seeded station sits at 41.0, -74.0 and 30 m.
  NEAR = { "latitude_deg" => 41.1, "longitude_deg" => -74.0, "elevation_m" => 40.0, "climate_zone" => 14,
           "hours_from_utc" => -5 }.freeze
  FAR = NEAR.merge("latitude_deg" => 42.0).freeze
  EDITED_AIR_JAN = -9.0
  STATION_AIR_JAN = -2.0
  HAND_AIR_JAN = 1.5

  # [Undo name, state after the Undo], from the last step back to the first. After every Redo the state is the
  # one above it; `verify` reads the first row's state before Undo, FINAL.
  FINAL = { "site" => "set", "site_latitude_deg" => 42.0, "climate" => "complete", "origin" => "station",
            "source_type" => "phius_approved", "edited" => 0, "air_c_jan" => STATION_AIR_JAN,
            "as_read_air_c_jan" => STATION_AIR_JAN, "verdict" => "fail" }.freeze
  TRACE = [
    ["Set Site Location", FINAL.merge("site_latitude_deg" => 41.1, "verdict" => "pass")],
    ["Restore Climate Values", FINAL.merge("site_latitude_deg" => 41.1, "source_type" => "user_defined",
                                           "edited" => 1, "air_c_jan" => EDITED_AIR_JAN, "verdict" => "pass")],
    ["Edit Climate Values", FINAL.merge("site_latitude_deg" => 41.1, "verdict" => "pass")],
    ["Set Site Location", FINAL.merge("site" => "not_set", "site_latitude_deg" => nil, "verdict" => "not_checked")],
    ["Seed Station Climate", { "site" => "not_set", "site_latitude_deg" => nil, "climate" => "none",
                               "origin" => nil, "source_type" => nil, "edited" => 0, "air_c_jan" => nil,
                               "as_read_air_c_jan" => nil, "verdict" => nil }],
    ["Clear Climate", { "site" => "not_set", "site_latitude_deg" => nil, "climate" => "complete",
                        "origin" => "hand", "source_type" => "user_defined", "edited" => 0,
                        "air_c_jan" => HAND_AIR_JAN, "as_read_air_c_jan" => nil, "verdict" => "not_checked" }],
    ["Edit Climate Values", { "site" => "not_set", "site_latitude_deg" => nil, "climate" => "incomplete",
                              "origin" => "hand", "source_type" => "user_defined", "edited" => 0,
                              "air_c_jan" => nil, "as_read_air_c_jan" => nil, "verdict" => "not_checked" }],
    ["Enter Climate Values", { "site" => "not_set", "site_latitude_deg" => nil, "climate" => "none",
                               "origin" => nil, "source_type" => nil, "edited" => 0, "air_c_jan" => nil,
                               "as_read_air_c_jan" => nil, "verdict" => nil }]
  ].freeze

  module_function

  def run_hand
    client = AuthoringExample::Client.new
    steps = []
    steps << { "step" => "no climate", "passed" => climate(client).fetch("state") == "none" }
    entered = invoke(client, steps, "climate.enter_values", "values" => sparse)
    steps << { "step" => "incomplete", "passed" => entered.dig("value", "state") == "incomplete" &&
                                                   !entered.dig("value", "missing").empty? }
    invoke(client, steps, "climate.save_values", "values" => complete, "expected_values" => editable(client))
    steps << { "step" => "complete", "passed" => climate(client).fetch("state") == "complete" }
    refused = client.invoke("#{PREFIX}.climate.restore_original", "expected_values" => editable(client))
    steps << { "step" => "restore refuses", "passed" => refused["code"] == "climate.no_original" }
    invoke(client, steps, "climate.clear", "expected_values" => editable(client))
    steps << { "step" => "cleared", "passed" => climate(client).fetch("state") == "none" }
    result(steps)
  end

  def run_station
    client = AuthoringExample::Client.new
    steps = []
    steps << { "step" => "seeded station", "passed" => climate(client).dig("climate", "values", "origin") == "station" }
    near = invoke(client, steps, "site.update", "values" => NEAR, "expected_values" => site(client))
    steps << { "step" => "passes near", "passed" => near.dig("value", "limit_check", "verdict") == "pass" }
    values = editable(client)
    values["monthly"]["air_c"][0] = EDITED_AIR_JAN
    invoke(client, steps, "climate.save_values", "values" => values, "expected_values" => editable(client))
    steps << { "step" => "edited", "passed" => state.values_at("source_type", "edited") == ["user_defined", 1] }
    invoke(client, steps, "climate.restore_original", "expected_values" => editable(client))
    steps << { "step" => "restored", "passed" => state.values_at("source_type", "edited") == ["phius_approved", 0] }
    stored = climate(client).fetch("climate")
    far = invoke(client, steps, "site.update", "values" => FAR, "expected_values" => site(client))
    steps << { "step" => "fails far, nothing stored",
               "passed" => far.dig("value", "limit_check", "verdict") == "fail" &&
                           climate(client).fetch("climate") == stored }
    steps << { "step" => "read back", "passed" => verify.fetch("passed") }
    result(steps)
  end

  # The agent guide's recipe: folders, then stations nearest first, then attach the first that passes. Reads
  # only what the list answers; the station's values go from its file to the Model inside PH-Composer.
  def run_attach(folder_id)
    client = AuthoringExample::Client.new
    steps = []
    folders = client.query("#{PREFIX}.folders.list").fetch("value").fetch("folders")
    folder = folders.find { |row| row.fetch("id") == folder_id }
    steps << { "step" => "folder has stations", "passed" => folder.to_h.fetch("station_count", 0).to_i.positive? }
    listed = client.query("#{PREFIX}.stations.list", "folder_id" => folder_id)
    steps << { "step" => "stations.list", "passed" => listed["status"] == "completed", "code" => listed["code"] }
    nearest = listed.dig("value", "stations").to_a.find { |row| row.dig("limit_check", "verdict") == "pass" }
    steps << { "step" => "a station passes", "passed" => !nearest.nil? }
    return result(steps) unless nearest

    invoke(client, steps, "climate.attach_station", "folder_id" => folder_id, "station_key" => nearest.fetch("key"))
    found = climate(client)
    steps << { "step" => "attached", "passed" => found.dig("climate", "values", "origin") == "station" &&
                                                 found.dig("limit_check", "verdict") == "pass" }
    status = client.query("#{PREFIX}.climate.source_status").fetch("value")
    steps << { "step" => "source found", "passed" => status.values_at("status", "station_key") ==
                                                     ["found", nearest.fetch("key")] }
    result(steps)
  end

  # The site, the climate's state and source, its edited count, one value and its as-read copy, and the verdict,
  # as public reads give them, with string keys so the host bridge returns them as compact JSON.
  def state
    client = AuthoringExample::Client.new
    site = client.query("#{PREFIX}.site.get").fetch("value")
    found = climate(client)
    values = found.dig("climate", "values")
    { "site" => site.fetch("state"), "site_latitude_deg" => site.fetch("latitude_deg"),
      "climate" => found.fetch("state"), "origin" => values&.fetch("origin"),
      "source_type" => values&.dig("provenance", "source_type"), "edited" => found.fetch("edited_cells").length,
      "air_c_jan" => values&.dig("monthly", "air_c", 0),
      "as_read_air_c_jan" => values&.dig("as_read", "monthly", "air_c", 0),
      "verdict" => found.dig("limit_check", "verdict") }
  end

  def verify
    found = state
    { "passed" => found == FINAL, "state" => found }
  end

  def climate(client)
    result = client.query("#{PREFIX}.climate.get")
    raise "climate.get failed: #{result['code']}" unless result["status"] == "completed"

    result.fetch("value")
  end

  def editable(client)
    climate(client).dig("climate", "values").slice(*EDITABLE)
  end

  def site(client)
    client.query("#{PREFIX}.site.get").fetch("value").slice(*NEAR.keys)
  end

  # A typed climate with only the name and the station elevation.
  def sparse
    { "name" => "Walkthrough typed climate", "station_latitude_deg" => nil, "station_longitude_deg" => nil,
      "station_elevation_m" => 15.0, "daily_temp_swing_k" => nil, "wind_speed_m_s" => nil,
      "monthly" => MONTHLY_ROWS.to_h { |row| [row, Array.new(12)] },
      "peak_loads" => CASES.to_h { |name| [name, PEAK_ROWS.to_h { |row| [row, nil] }] } }
  end

  # The same climate with every value typed.
  def complete
    sparse.merge("daily_temp_swing_k" => 9.0, "wind_speed_m_s" => 2.5,
                 "monthly" => MONTHLY_ROWS.each_with_index.to_h { |row, index|
                   [row, Array.new(12) { |month| HAND_AIR_JAN + (index * 10) + month }]
                 },
                 "peak_loads" => CASES.to_h { |name| [name, PEAK_ROWS.to_h { |row| [row, 5.0] }] })
  end

  def invoke(client, steps, name, params)
    result = client.invoke("#{PREFIX}.#{name}", params)
    steps << { "step" => name, "passed" => result["effect"] == "committed", "code" => result["code"] }
    result
  end

  def result(steps)
    { "passed" => steps.all? { |row| row["passed"] }, "steps" => steps }
  end
end
