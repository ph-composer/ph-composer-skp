# frozen_string_literal: true

# Writes Phius-shaped station files of invented stations, so every value is plainly made up: no station name,
# coordinate or value comes from a Phius file. The layout follows the format's structure (a blank first line, a
# packed header row, eight series rows of twelve months and three design columns, the degree-hour and wind row,
# then the trailing notes), tab-delimited, Windows-1252, CRLF.
#
#   ClimateStationFiles.station_bytes(...)   one file's bytes
#   ClimateStationFiles.write_folder(dir)    the reference folder ACCEPTANCE lists
#   ClimateStationFiles.write_second(dir)    the second folder: one station of the same name and state, changed
#
# The committed copies under tests/fixtures/climate/ are this module's output; `make fixtures` rewrites them and
# tests/climate_folder_scan_test.rb fails when they drift.
module ClimateStationFiles
  # The reference site the fixture stations sit around. Distances are along the meridian, so a station `d` km
  # north is `d / 6371.0088 * 180 / PI` degrees of latitude away.
  SITE = { "latitude_deg" => 40.0, "longitude_deg" => -100.0, "elevation_m" => 500.0 }.freeze
  FILE_ORDER = [
    ["Temperature outdoor", "air_c"], ["North", "rad_north"], ["East", "rad_east"], ["South", "rad_south"],
    ["West", "rad_west"], ["Global", "rad_global"], ["Dewpoint", "dewpoint_c"], ["Sky temperature", "sky_c"]
  ].freeze
  DEGREE = "°"

  # Stations of the reference folder: [relative path, name, latitude, elevation, offset]. Each sits on the site's
  # meridian, so its distance is exact; the offset makes its values its own.
  STATIONS = [
    ["XA/INSIDE_BOTH-mon.txt", "Inside Both XA", 40.70, 621.0, 1.0], # 77.84 km, 121 m: pass
    ["XA/OUTSIDE_DISTANCE-mon.txt", "Outside Distance XA", 40.74, 500.0, 2.0], # 82.29 km: fail on distance
    ["XB/OUTSIDE_ELEVATION-mon.txt", "Outside Elevation XB", 40.10, 623.0, 3.0], # 123 m: fail on elevation
    ["XB/CAFE_STATION-mon.txt", "Café Station XB", 40.05, 380.0, 4.0], # 120 m below, a Windows-1252 name: pass
    ["XB/XC/NESTED-mon.txt", "Nested XC", 39.90, 500.0, 5.0] # in a nested folder: its state is XC
  ].freeze

  module_function

  def number(value)
    value.round(2).to_s
  end

  def monthly(base, offset)
    Array.new(12) { |month| number(base + offset + month) }
  end

  # One station file. `drop` leaves a series row out; `short` cuts the named row to eleven months; `text` puts a
  # word in the named row's first month; `header` false writes no latitude.
  def station_bytes(name:, latitude:, longitude: SITE.fetch("longitude_deg"), elevation:, offset:, drop: nil,
                    short: nil, text: nil, header: true)
    location = header ? ["Latitude [#{DEGREE}]", number(latitude)] : []
    head = [name, *location, "Longitude [#{DEGREE}]", number(longitude), "Height a.s.l. (m)", number(elevation),
            "", "", "Daily temperature variation summer (K)", number(9.5 + offset), "", "", "Heating load 1",
            "Heating load 2", "Cooling load"]
    rows = FILE_ORDER.each_with_index.filter_map do |(label, _key), index|
      next if label == drop

      values = monthly(index * 10.0, offset)
      values[0] = "n/a" if label == text
      design = Array.new(3) { |case_index| number(offset + (case_index * 100) + index) }
      design = ["3d", "w1: 5/1", "c: 7/7"] if ["Dewpoint", "Sky temperature"].include?(label)
      cells = label == short ? values.first(11) : values + design
      [label, *cells]
    end
    lines = [[""], head, *rows,
             ["Heating degree-hours (12/20)", "100", "Cooling degree-hours (24)", "50", "Wind speed", "Jan",
              number(3.0 + offset), "Jul", number(1.0 + offset), "m/s"],
             ["12-h Temperaturmin.", "-1 #{DEGREE}C", "Anteil Nachtstunden < 18 #{DEGREE}C", "10%"], [""],
             ["Heating loads (time constant for buildings, number of cold days): Statistics based on: invented"],
             ["Cooling (number of hot days): Statistics based on: invented"], [""], ["Albedo = 0.2"]]
    lines.map { |cells| cells.join("\t") }.join("\r\n").concat("\r\n").encode("Windows-1252").b
  end

  def write(path, bytes)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
  end

  # The reference folder: the five stations, a near-duplicate `-mon2.txt`, a `-mon.txt` with no latitude, an
  # `.xls`-named file, an unrelated note and a hidden file, which is never counted.
  def folder_files
    files = STATIONS.to_h do |path, name, latitude, elevation, offset|
      [path, station_bytes(:name => name, :latitude => latitude, :elevation => elevation, :offset => offset)]
    end
    files.merge(
      "XA/INSIDE_BOTH-mon2.txt" => station_bytes(:name => "Inside Both XA", :latitude => 40.70, :elevation => 621.0,
                                                 :offset => 9.0),
      "XA/MALFORMED-mon.txt" => station_bytes(:name => "Malformed XA", :latitude => 0.0, :elevation => 0.0,
                                              :offset => 0.0, :header => false),
      "XA/INVENTED.xls" => "not a workbook\n".b,
      "notes.md" => "Invented stations for PH-Composer's tests.\n".b,
      "XA/.hidden" => "hidden\n".b
    )
  end

  # The second folder: INSIDE_BOTH in XA again, with other values, so its checksum differs.
  def second_files
    { "XA/INSIDE_BOTH-mon.txt" => station_bytes(:name => "Inside Both XA", :latitude => 40.70, :elevation => 621.0,
                                                :offset => 7.0) }
  end

  def write_folder(dir)
    folder_files.each { |path, bytes| write(File.join(dir, path), bytes) }
    dir
  end

  def write_second(dir)
    second_files.each { |path, bytes| write(File.join(dir, path), bytes) }
    dir
  end
end
