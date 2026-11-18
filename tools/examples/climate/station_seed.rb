# frozen_string_literal: true

# Development only. Writes a synthetic station climate into the active Model as one native Undo step, "Seed
# Station Climate", built by PhComposer::Climate::Record.from_station from a hand-made parsed station with no
# file behind it, so the climate walkthrough reaches the station half (edited cells, Restore) without a climate
# data folder; ClimateWalkthrough.run_attach attaches a real station file. It reaches into the feature on
# purpose, so it is kept apart from the public-only walkthrough.
#   ClimateStationSeed.seed   refuses with a message when the Model already holds a climate
module ClimateStationSeed
  STATION_AIR_JAN = -2.0
  MONTHLY_ROWS = %w[air_c dewpoint_c sky_c rad_north_kwh_m2 rad_east_kwh_m2 rad_south_kwh_m2 rad_west_kwh_m2
                    rad_global_kwh_m2].freeze
  PEAK_ROWS = %w[air_c dewpoint_c sky_c rad_north_w_m2 rad_east_w_m2 rad_south_w_m2 rad_west_w_m2
                 rad_global_w_m2].freeze

  module_function

  def parsed_station
    { "name" => "Walkthrough Station", "latitude_deg" => 41.0, "longitude_deg" => -74.0, "elevation_m" => 30.0,
      "daily_temp_swing_k" => 10.5,
      "monthly" => MONTHLY_ROWS.each_with_index.to_h { |row, index|
        [row, Array.new(12) { |month| STATION_AIR_JAN + (index * 10) + month }]
      },
      "peak_loads" => %w[heat_1 heat_2 cool_1].each_with_index.to_h { |name, index|
        [name, PEAK_ROWS.to_h { |row| [row, (index * 100.0) + 1.0] }]
      },
      "wind_speed_january_m_s" => 4.0, "wind_speed_july_m_s" => 3.0 }
  end

  def source
    { "dataset_name" => "Walkthrough Dataset", "station_name" => "WALKTHROUGH_STATION", "state" => "XX",
      "checksum" => "0" * 64 }
  end

  def seed
    climate = PhComposer::Climate
    model = Sketchup.active_model
    kind = climate::Schema::KIND
    return { "seeded" => false, "message" => "The Model already holds a climate." } unless kind.store.ids(model).empty?

    record = { "id" => climate::Schema::RECORD_ID, "schema_version" => kind.schema_version }
             .merge(climate::Record.from_station(parsed_station, source))
    problems = kind.problems(record)
    return { "seeded" => false, "message" => problems.first } unless problems.empty?

    model.start_operation("Seed Station Climate", true)
    kind.store.write(model, record)
    model.commit_operation
    { "seeded" => true }
  end
end
