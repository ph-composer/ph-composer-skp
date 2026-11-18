# frozen_string_literal: true

# Synthetic climate values in the climate record's shape. No station name, coordinate or value comes from a
# Phius file: every number is a formula of its row and column.
module ClimateFixtures
  SCHEMA = PhComposer::Climate::Schema

  module_function

  def monthly
    SCHEMA::MONTHLY_ROWS.each_with_index.to_h do |row, row_index|
      [row, Array.new(12) { |month| (row_index * 10.0) + month + 0.5 }]
    end
  end

  def peak_loads
    SCHEMA::CASES.each_with_index.to_h do |name, case_index|
      [name, SCHEMA::PEAK_ROWS.each_with_index.to_h { |row, row_index| [row, (case_index * 100.0) + row_index + 0.25] }]
    end
  end

  # A Phius-shaped parsed station, as the station reader will hand it to Record.from_station.
  def parsed_station(name: "Synthetic Station", latitude: 41.0, longitude: -74.0, elevation: 30.0)
    { "name" => name, "latitude_deg" => latitude, "longitude_deg" => longitude, "elevation_m" => elevation,
      "daily_temp_swing_k" => 10.5, "monthly" => monthly, "peak_loads" => peak_loads,
      "wind_speed_january_m_s" => 4.0, "wind_speed_july_m_s" => 3.0 }
  end

  def source
    { "dataset_name" => "Synthetic Dataset", "station_name" => "SYNTHETIC_STATION", "state" => "XX",
      "checksum" => "ab" * 32 }
  end

  # The editable fields of a complete climate typed by hand.
  def hand_values(name: "Typed climate", latitude: nil, longitude: nil)
    { "name" => name, "station_latitude_deg" => latitude, "station_longitude_deg" => longitude,
      "station_elevation_m" => 12.0, "daily_temp_swing_k" => 9.0, "wind_speed_m_s" => 2.5,
      "monthly" => monthly, "peak_loads" => peak_loads }
  end

  # The editable fields with only the two values Enter Values needs.
  def sparse_values(name: "Typed climate")
    { "name" => name, "station_latitude_deg" => nil, "station_longitude_deg" => nil, "station_elevation_m" => 12.0,
      "daily_temp_swing_k" => nil, "wind_speed_m_s" => nil,
      "monthly" => SCHEMA.empty_monthly, "peak_loads" => SCHEMA.empty_peak_loads }
  end

  def station_record(**station)
    { "id" => SCHEMA::RECORD_ID, "schema_version" => 1 }
      .merge(PhComposer::Climate::Record.from_station(parsed_station(**station), source))
  end
end
