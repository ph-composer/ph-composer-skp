# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/climate_station_files"

# The Phius station reader on invented files of the format's shape: exact values, a typed failure naming the row,
# and Windows-1252 read as UTF-8.
class ClimateStationFileTest < PhComposerTestCase
  READER = PhComposer::Climate::Stations::PhiusStationFile
  FILES = ClimateStationFiles

  def bytes(**options)
    FILES.station_bytes(**{ :name => "Invented XA", :latitude => 40.5, :elevation => 612.0, :offset => 1.0 }
      .merge(options))
  end

  def unreadable(**options)
    assert_raises(READER::Unreadable) { READER.parse(bytes(**options)) }
  end

  # The generator's formula: series index i (in file order) month m holds i * 10 + offset + m; numeric design
  # columns hold offset + case * 100 + i; the swing is 9.5 + offset, January wind 3 + offset, July 1 + offset.
  def test_a_well_formed_file_parses_to_exact_values_mapped_by_label
    parsed = READER.parse(bytes)

    assert_equal({ "name" => "Invented XA", "latitude_deg" => 40.5, "longitude_deg" => -100.0,
                   "elevation_m" => 612.0, "daily_temp_swing_k" => 10.5, "wind_speed_january_m_s" => 4.0,
                   "wind_speed_july_m_s" => 2.0 }, parsed.reject { |key, _| %w[monthly peak_loads].include?(key) })
    monthly = parsed.fetch("monthly")
    assert_equal PhComposer::Climate::Schema::MONTHLY_ROWS, monthly.keys
    assert_equal (1..12).map(&:to_f), monthly.fetch("air_c")
    assert_equal (11..22).map(&:to_f), monthly.fetch("rad_north_kwh_m2")
    assert_equal (51..62).map(&:to_f), monthly.fetch("rad_global_kwh_m2")
    assert_equal (61..72).map(&:to_f), monthly.fetch("dewpoint_c")
    assert_equal (71..82).map(&:to_f), monthly.fetch("sky_c")
    heat_2 = parsed.dig("peak_loads", "heat_2")
    assert_equal({ "air_c" => 101.0, "dewpoint_c" => nil, "sky_c" => nil, "rad_north_w_m2" => 102.0,
                   "rad_east_w_m2" => 103.0, "rad_south_w_m2" => 104.0, "rad_west_w_m2" => 105.0,
                   "rad_global_w_m2" => 106.0 }, heat_2)
    assert_equal %w[heat_1 heat_2 cool_1], parsed.fetch("peak_loads").keys
    assert_equal 206.0, parsed.dig("peak_loads", "cool_1", "rad_global_w_m2")
  end

  def test_the_header_alone_gives_what_the_station_list_needs
    assert_equal({ "name" => "Invented XA", "latitude_deg" => 40.5, "longitude_deg" => -100.0, "elevation_m" => 612.0 },
                 READER.header(bytes))
  end

  def test_a_missing_series_row_a_short_row_and_a_non_number_each_fail_naming_the_row
    assert_equal "Global", unreadable(:drop => "Global").row
    assert_equal "Sky temperature", unreadable(:drop => "Sky temperature").row
    assert_equal "East", unreadable(:short => "East").row
    assert_equal "Dewpoint", unreadable(:text => "Dewpoint").row
    assert_equal "header", unreadable(:header => false).row
    assert_equal "header", assert_raises(READER::Unreadable) { READER.header(bytes(:header => false)) }.row
    refute_includes unreadable(:text => "Dewpoint").message, "n/a"
  end

  def test_each_needed_header_value_is_checked_and_a_station_named_like_a_row_still_reads
    no_longitude = bytes.sub("\tLongitude [\xB0]\t-100.0".b, "".b)
    no_height = bytes.sub("\tHeight a.s.l. (m)\t612.0".b, "".b)
    unnamed = bytes(:name => "")
    long_name = bytes(:name => "N" * (READER::MAX_NAME_LENGTH + 1))

    [no_longitude, no_height, unnamed, long_name].each do |raw|
      assert_equal "header", assert_raises(READER::Unreadable) { READER.parse(raw) }.row
    end
    north = READER.parse(bytes(:name => "North"))
    assert_equal ["North", 11.0], [north.fetch("name"), north.dig("monthly", "rad_north_kwh_m2", 0)]
  end

  def test_windows_1252_text_reads_as_utf_8
    raw = bytes(:name => "Café Århus")

    assert_includes raw, "Caf\xE9".b
    name = READER.header(raw).fetch("name")
    assert_equal "Café Århus", name
    assert_equal Encoding::UTF_8, name.encoding
    undefined = bytes(:name => "Odd").sub("Odd".b, "O\x81d".b)
    assert_equal "O\uFFFDd", READER.header(undefined).fetch("name")
  end

  def test_the_first_block_wins_and_absent_optional_values_read_null
    twice = bytes + bytes(:name => "Second XA", :latitude => 10.0, :offset => 50.0)
    parsed = READER.parse(twice)
    assert_equal ["Invented XA", 1.0], [parsed.fetch("name"), parsed.dig("monthly", "air_c", 0)]

    no_wind = bytes.sub(/^Heating degree-hours.*\r\n/, "")
    no_swing = bytes.sub(/\tDaily temperature variation summer \(K\)\t[^\t]+/, "")
    assert_equal [nil, nil], READER.parse(no_wind).values_at("wind_speed_january_m_s", "wind_speed_july_m_s")
    assert_nil READER.parse(no_swing).fetch("daily_temp_swing_k")
  end

  def test_a_file_too_large_or_out_of_range_is_not_a_station
    assert_equal "file", assert_raises(READER::Unreadable) { READER.header(bytes + (" " * READER::MAX_BYTES)) }.row
    assert_equal "header", unreadable(:latitude => 95.0).row
  end

  def test_the_checksum_is_the_sha_256_of_the_bytes
    assert_equal Digest::SHA256.hexdigest(bytes), READER.checksum(bytes)
    assert_match(/\A[0-9a-f]{64}\z/, READER.checksum(bytes))
  end
end
