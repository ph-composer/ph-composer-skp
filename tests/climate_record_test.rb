# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/climate_fixtures"

# The climate record's schema and its pure rules: completeness, edited cells, the limit check and the
# station builder. None of them touches SketchUp.
class ClimateRecordTest < PhComposerTestCase
  CLIMATE = PhComposer::Climate
  SCHEMA = CLIMATE::Schema
  LIMIT = CLIMATE::LimitCheck
  SITE = { "latitude_deg" => 41.0, "longitude_deg" => -74.0, "elevation_m" => 30.0 }.freeze

  def test_a_station_and_a_hand_record_are_valid_and_round_trip_through_json
    hand = { "id" => SCHEMA::RECORD_ID, "schema_version" => 1 }
           .merge(CLIMATE::Record.hand(ClimateFixtures.sparse_values))

    [ClimateFixtures.station_record, hand].each do |record|
      assert_empty SCHEMA::KIND.problems(record), record.fetch("origin")
      assert_equal record, JSON.parse(JSON.generate(record))
    end
  end

  def test_an_unknown_key_a_thirteen_value_month_and_a_wrong_version_are_unreadable
    record = ClimateFixtures.station_record
    nested = PhComposer::DeepCopy.call(record)
    nested["provenance"]["source_uri"] = "/Users/someone/climate/XX/STATION-mon.txt"
    long_month = PhComposer::DeepCopy.call(record)
    long_month["monthly"]["air_c"] << 1.0

    [record.merge("folder" => "/tmp"), nested, long_month, record.merge("schema_version" => 2)].each do |bad|
      refute_empty SCHEMA::KIND.problems(bad)
    end
  end

  # Every object the record holds is closed, so no key outside the schema, a file location included, can be
  # stored, and no listed key names one.
  def test_every_object_in_the_schema_is_closed_and_no_key_names_a_location
    objects = []
    walk = lambda do |schema|
      next unless schema.is_a?(Hash)

      objects << schema if Array(schema["type"]).include?("object")
      schema.fetch("properties", {}).each_value { |child| walk.call(child) }
      walk.call(schema["items"])
    end
    walk.call(SCHEMA::KIND.values_schema)
    keys = objects.flat_map { |schema| schema.fetch("properties", {}).keys }

    assert_operator objects.length, :>=, 9
    assert(objects.all? { |schema| schema["additionalProperties"] == false })
    assert_empty keys.grep(/path|uri|folder|location|file/)
  end

  def test_a_station_needs_its_coordinates_and_copy_and_a_hand_climate_names_no_file
    station = ClimateFixtures.station_record
    hand = { "id" => SCHEMA::RECORD_ID, "schema_version" => 1 }.merge(CLIMATE::Record.hand(ClimateFixtures.hand_values))

    refute_empty SCHEMA::KIND.problems(station.merge("station_latitude_deg" => nil))
    refute_empty SCHEMA::KIND.problems(station.merge("as_read" => nil))
    refute_empty SCHEMA::KIND.problems(station.merge("provenance" => station.fetch("provenance")
                                                                            .merge("dataset_name" => nil)))
    refute_empty SCHEMA::KIND.problems(hand.merge("as_read" => station.fetch("as_read")))
    refute_empty SCHEMA::KIND.problems(hand.merge("provenance" => station.fetch("provenance")))
    refute_empty SCHEMA::KIND.problems(hand.merge("station_latitude_deg" => 40.0))
    assert_empty SCHEMA::KIND.problems(hand.merge("station_latitude_deg" => 40.0, "station_longitude_deg" => -74.0))
  end

  def test_a_full_climate_is_complete_and_each_needed_value_removed_is_named
    full = CLIMATE::Record.hand(ClimateFixtures.hand_values)
    needed = %w[daily_temp_swing_k wind_speed_m_s].map { |row| [row, nil] } +
             SCHEMA.grid_cells(full.fetch("monthly"), full.fetch("peak_loads")).map { |row, column, _| [row, column] }
                   .reject { |row, column| SCHEMA::CASES.include?(column) && %w[dewpoint_c sky_c].include?(row) }

    assert_empty CLIMATE::Completeness.missing(full)
    assert_equal 2 + 96 + 18, needed.length
    needed.each do |row, column|
      gap = without(full, row, column)

      assert_equal [{ "row" => row, "columns" => column ? [column] : [] }], CLIMATE::Completeness.missing(gap),
                   [row, column].inspect
    end
  end

  def test_a_null_dewpoint_or_sky_temperature_in_a_design_case_is_still_complete
    full = CLIMATE::Record.hand(ClimateFixtures.hand_values)

    gap = without(without(full, "dewpoint_c", "heat_1"), "sky_c", "cool_1")

    assert CLIMATE::Completeness.complete?(gap)
  end

  def test_missing_months_and_cases_of_one_key_group_apart_in_grid_order
    sparse = CLIMATE::Record.hand(ClimateFixtures.sparse_values)

    missing = CLIMATE::Completeness.missing(sparse)

    peak_rows = SCHEMA::PEAK_ROWS - %w[dewpoint_c sky_c]
    assert_equal %w[daily_temp_swing_k wind_speed_m_s] + SCHEMA::MONTHLY_ROWS + peak_rows,
                 missing.map { |row| row.fetch("row") }
    assert_equal SCHEMA::MONTHS, missing.find { |row| row.fetch("row") == "air_c" }.fetch("columns")
    assert_equal SCHEMA::CASES, missing.reverse.find { |row| row.fetch("row") == "air_c" }.fetch("columns")
  end

  def test_edited_cells_are_the_differences_from_the_as_read_copy_but_never_the_wind_speed
    station = CLIMATE::Schema::KIND.values(ClimateFixtures.station_record)
    edited = PhComposer::DeepCopy.call(station)
    edited["monthly"]["air_c"][2] = -1.0
    edited["peak_loads"]["cool_1"]["rad_south_w_m2"] = 7.0
    edited["daily_temp_swing_k"] = 12.0
    edited["station_elevation_m"] = 31.0
    edited["wind_speed_m_s"] = 9.0

    cells = CLIMATE::Edits.cells(edited)

    assert_empty CLIMATE::Edits.cells(station)
    assert_equal [["station_elevation_m", nil, 31.0, 30.0], ["daily_temp_swing_k", nil, 12.0, 10.5],
                  ["air_c", "mar", -1.0, 2.5], ["rad_south_w_m2", "cool_1", 7.0, 205.25]],
                 cells.map { |cell| cell.values_at("row", "column", "value", "as_read") }
  end

  def test_a_hand_climate_has_no_edited_cells
    assert_empty CLIMATE::Edits.cells(CLIMATE::Record.hand(ClimateFixtures.hand_values))
  end

  def test_the_limits_are_the_exact_conversions_and_pass_at_the_boundary
    assert_in_delta 50 * 1.609344, LIMIT::DISTANCE_LIMIT_KM, 1e-12
    assert_in_delta 400 * 0.3048, LIMIT::ELEVATION_LIMIT_M, 1e-12

    exact = LIMIT.compare(80.4672, 121.92)
    over_distance = LIMIT.compare(80.4682, 121.92)
    over_elevation = LIMIT.compare(80.4672, 121.93)

    assert_equal ["pass", true, true], exact.values_at("verdict", "distance_ok", "elevation_ok")
    assert_equal ["fail", false, true], over_distance.values_at("verdict", "distance_ok", "elevation_ok")
    assert_equal ["fail", true, false], over_elevation.values_at("verdict", "distance_ok", "elevation_ok")
  end

  def test_a_site_exactly_on_either_limit_passes_through_the_floating_point_arithmetic
    station_latitude = 41.0 + (LIMIT::DISTANCE_LIMIT_KM / LIMIT::EARTH_RADIUS_KM * 180 / Math::PI)
    climate = { "station_latitude_deg" => station_latitude, "station_longitude_deg" => -74.0,
                "station_elevation_m" => 200.0 }
    on_both = SITE.merge("elevation_m" => 321.92)
    metre = 0.001 / LIMIT::EARTH_RADIUS_KM * 180 / Math::PI

    assert_equal ["pass", true, true], LIMIT.call(on_both, climate).values_at("verdict", "distance_ok", "elevation_ok")
    assert_equal "fail", LIMIT.call(on_both.merge("elevation_m" => 321.921), climate).fetch("verdict")
    assert_equal "fail", LIMIT.call(on_both, climate.merge("station_latitude_deg" => station_latitude + metre))
                              .fetch("verdict")
  end

  def test_the_elevation_difference_is_a_magnitude_compared_exactly
    climate = { "station_latitude_deg" => 41.0, "station_longitude_deg" => -74.0, "station_elevation_m" => 0.0 }

    above = LIMIT.call(SITE.merge("elevation_m" => 121.92), climate)
    below = LIMIT.call(SITE.merge("elevation_m" => 0.0), climate.merge("station_elevation_m" => 121.92))
    past = LIMIT.call(SITE.merge("elevation_m" => 122.92), climate)

    assert_equal [121.92, "pass"], above.values_at("elevation_difference_m", "verdict")
    assert_equal [121.92, "pass"], below.values_at("elevation_difference_m", "verdict")
    assert_equal [false, "fail"], past.values_at("elevation_ok", "verdict")
  end

  # Hand values: along a meridian or the equator the distance is the radius times the angle, 6371.0088 km x
  # pi / 180 for one degree, across the antimeridian too; the other two pairs were worked out apart from this
  # code with the same formula and radius.
  def test_distances_match_hand_values_for_three_pairs
    one_degree = 6371.0088 * Math::PI / 180

    assert_in_delta one_degree, LIMIT.distance_km(40.0, -74.0, 41.0, -74.0), 1e-9
    assert_in_delta 304.40301968229886, LIMIT.distance_km(40.6782, -73.9442, 42.3601, -71.0589), 1e-6
    assert_in_delta 144.78091937656316, LIMIT.distance_km(-33.0, 151.0, -34.0, 150.0), 1e-6
    assert_in_delta one_degree, LIMIT.distance_km(0.0, 179.5, 0.0, -179.5), 1e-9
  end

  def test_a_station_within_and_beyond_the_distance_limit
    climate = { "station_latitude_deg" => 41.7, "station_longitude_deg" => -74.0, "station_elevation_m" => 30.0 }

    inside = LIMIT.call(SITE, climate)
    outside = LIMIT.call(SITE, climate.merge("station_latitude_deg" => 41.73))

    assert_equal "pass", inside.fetch("verdict")
    assert_in_delta 77.837, inside.fetch("distance_km"), 1e-3
    assert_equal [false, true, "fail"], outside.values_at("distance_ok", "elevation_ok", "verdict")
  end

  def test_no_site_and_no_station_coordinates_each_read_not_checked_with_their_reason
    station = { "station_latitude_deg" => 41.0, "station_longitude_deg" => -74.0, "station_elevation_m" => 30.0 }
    typed = station.merge("station_latitude_deg" => nil, "station_longitude_deg" => nil)
    no_site = SITE.transform_values { nil }

    assert_equal %w[not_checked no_site], LIMIT.call(no_site, station).values_at("verdict", "reason")
    assert_equal %w[not_checked no_station_coordinates], LIMIT.call(SITE, typed).values_at("verdict", "reason")
    assert_equal "no_station_coordinates", LIMIT.call(no_site, typed).fetch("reason")
    assert_nil LIMIT.call(no_site, station).fetch("distance_km")
  end

  def test_from_station_prefills_the_wind_speed_and_copies_the_values_into_a_separate_as_read
    parsed = ClimateFixtures.parsed_station

    values = CLIMATE::Record.from_station(parsed, ClimateFixtures.source)

    assert_in_delta 3.5, values.fetch("wind_speed_m_s")
    assert_equal parsed.fetch("monthly"), values.dig("as_read", "monthly")
    assert_equal parsed.fetch("peak_loads"), values.fetch("peak_loads")
    refute_same values.fetch("monthly"), values.dig("as_read", "monthly")
    refute_same values.dig("monthly", "air_c"), values.dig("as_read", "monthly", "air_c")
    refute_same parsed.fetch("monthly"), values.fetch("monthly")
    values["monthly"]["air_c"][0] = 99.0
    assert_equal 0.5, values.dig("as_read", "monthly", "air_c", 0)
  end

  def test_from_station_writes_an_approved_provenance_with_the_station_coordinates
    provenance = CLIMATE::Record.from_station(ClimateFixtures.parsed_station, ClimateFixtures.source)
                                .fetch("provenance")

    assert_equal ["Synthetic Dataset", "SYNTHETIC_STATION", "XX", "phius_approved",
                  "Synthetic Dataset: Synthetic Station", "ab" * 32, true, true, nil],
                 provenance.values_at("dataset_name", "station_name", "state", "source_type", "source_name",
                                      "source_checksum", "monthly_data_available", "peak_load_data_available",
                                      "is_certification_approved")
    assert_equal({ "station_latitude_deg" => 41.0, "station_longitude_deg" => -74.0, "edited_values" => [] },
                 provenance.dig("assumptions", "ph_composer"))
  end

  def test_an_edit_makes_the_provenance_user_defined_and_restoring_makes_it_approved_again
    station = CLIMATE::Record.from_station(ClimateFixtures.parsed_station, ClimateFixtures.source)
    editable = station.slice(*SCHEMA::EDITABLE)
    editable["monthly"] = PhComposer::DeepCopy.call(editable.fetch("monthly"))
    editable["monthly"]["sky_c"][0] = -30.0

    edited = CLIMATE::Record.with_values(station, editable)
    restored = CLIMATE::Record.restored(edited)

    assert_equal "user_defined", edited.dig("provenance", "source_type")
    assert_equal [{ "row" => "sky_c", "column" => "jan", "value" => -30.0, "as_read" => 20.5 }],
                 edited.dig("provenance", "assumptions", "ph_composer", "edited_values")
    assert_equal station, restored
  end

  def test_a_hand_climate_is_user_defined_and_named_as_typed
    values = CLIMATE::Record.hand(ClimateFixtures.hand_values(:name => "Typed", :latitude => 40.0, :longitude => -74.0))

    assert_equal %w[user_defined Typed], values.fetch("provenance").values_at("source_type", "source_name")
    assert_equal 40.0, values.dig("provenance", "assumptions", "ph_composer", "station_latitude_deg")
    assert_equal "Retyped", CLIMATE::Record.with_values(values, "name" => "Retyped").dig("provenance", "source_name")
  end

  private

  def without(values, row, column)
    copy = PhComposer::DeepCopy.call(values)
    if column.nil?
      copy[row] = nil
    elsif SCHEMA::CASES.include?(column)
      copy["peak_loads"][column][row] = nil
    else
      copy["monthly"][row][SCHEMA::MONTHS.index(column)] = nil
    end
    copy
  end
end
