# frozen_string_literal: true

require "digest"

module PhComposer
  module Climate
    module Stations
      # The one built-in reader of Phius station files (`<STATION>-mon.txt`). Pure: bytes in, a parsed station or
      # an Unreadable naming the row out, and no SketchUp constant. The format, from its structure only
      # (context/CONTRACTS.md, "The Phius station reader"): tab-delimited Windows-1252 text; a packed header row
      # holding the station's name in its first cell and label, value pairs for latitude, longitude, height above
      # sea level and the summer daily temperature variation; eight series rows by label, each twelve months and
      # three design columns (Heating 1, Heating 2, Cooling), where the dewpoint and sky rows' design cells are
      # notes rather than numbers; and a packed row with the January and July wind speeds. The first occurrence of
      # a row wins, since a file may repeat its block. Nothing is guessed: a needed value that is missing or not a
      # number is Unreadable, and an optional one that is absent reads null.
      module PhiusStationFile
        SUFFIX = "-mon.txt"
        # Real station files are a few kilobytes; a larger file is not read at all.
        MAX_BYTES = 64 * 1024
        MAX_NAME_LENGTH = 120
        # Series rows by their normalized label: the record's monthly row and, for rows whose design cells are
        # numbers, the peak-load row they fill. The file's order differs from the record's, so rows are matched by
        # label.
        SERIES = {
          "temperature outdoor" => %w[air_c air_c], "dewpoint" => ["dewpoint_c", nil],
          "sky temperature" => ["sky_c", nil],
          "north" => %w[rad_north_kwh_m2 rad_north_w_m2], "east" => %w[rad_east_kwh_m2 rad_east_w_m2],
          "south" => %w[rad_south_kwh_m2 rad_south_w_m2], "west" => %w[rad_west_kwh_m2 rad_west_w_m2],
          "global" => %w[rad_global_kwh_m2 rad_global_w_m2]
        }.freeze
        LABELS = { "temperature outdoor" => "Temperature outdoor", "dewpoint" => "Dewpoint",
                   "sky temperature" => "Sky temperature", "north" => "North", "east" => "East", "south" => "South",
                   "west" => "West", "global" => "Global" }.freeze
        HEADER_LABELS = { "latitude" => "latitude_deg", "longitude" => "longitude_deg",
                          "height a.s.l" => "elevation_m",
                          "daily temperature variation summer" => "daily_temp_swing_k" }.freeze
        MONTHS = 12
        DESIGN_CASES = Schema::CASES
        NUMBER = /\A[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?\z/.freeze

        # A file that is not a station file, with the row that failed: "header", a series label such as
        # "Temperature outdoor", or "Wind speed". The message names the row and never a value of the file.
        class Unreadable < UserError
          attr_reader :row

          def initialize(row, message)
            @row = row
            super("#{row}: #{message}")
          end
        end

        module_function

        # The station's name, latitude_deg, longitude_deg and elevation_m: what the station list needs.
        def header(bytes)
          rows = lines(bytes)
          read_header(rows.fetch(header_index(rows))).slice("name", "latitude_deg", "longitude_deg", "elevation_m")
        end

        # The whole station in the shape Record.from_station takes: name, latitude_deg, longitude_deg,
        # elevation_m, daily_temp_swing_k, monthly, peak_loads, wind_speed_january_m_s and wind_speed_july_m_s.
        def parse(bytes)
          rows = lines(bytes)
          index = header_index(rows)
          station = read_header(rows.fetch(index))
          # The rows after the header, so a station named like a series row is never read as one.
          body = rows.drop(index + 1)
          series = read_series(body)
          monthly = Schema::MONTHLY_ROWS.to_h { |key| [key, nil] }
          series.each { |label, row| monthly[SERIES.fetch(label).first] = row.fetch(:months) }
          station.merge("monthly" => monthly, "peak_loads" => peak_loads(series)).merge(read_wind(body))
        end

        # The SHA-256 of the file's bytes, the form honeybee-ph's source_checksum documents.
        def checksum(bytes)
          Digest::SHA256.hexdigest(bytes)
        end

        # The file's lines, each split into cells, after reading its bytes as Windows-1252. A byte that encoding
        # leaves undefined becomes U+FFFD rather than failing the whole file.
        def lines(bytes)
          if bytes.bytesize > MAX_BYTES
            raise Unreadable.new("file", "is larger than #{MAX_BYTES / 1024} KiB, so it is not a station file")
          end

          text = bytes.dup.force_encoding(Encoding::Windows_1252)
                      .encode(Encoding::UTF_8, :invalid => :replace, :undef => :replace)
          text.split(/\r\n|\r|\n/).map { |line| line.split("\t", -1).map(&:strip) }
        end

        # A label as the file may write it, compared without its unit: "Latitude [°]" and "Height a.s.l. (m)"
        # read as "latitude" and "height a.s.l".
        def normalized(label)
          label.gsub(/[\[(].*?[\])]/, " ").downcase.split.join(" ").chomp(".")
        end

        # The header row is the first that labels a latitude after its first cell.
        def header_index(rows)
          index = rows.index { |row| row.drop(1).any? { |cell| normalized(cell) == "latitude" } }
          raise Unreadable.new("header", "no row gives the station's latitude") if index.nil?

          index
        end

        def read_header(cells)
          name = cells.first.to_s
          if name.empty? || name.length > MAX_NAME_LENGTH
            raise Unreadable.new("header", "the station name is empty or longer than #{MAX_NAME_LENGTH} characters")
          end

          # The labels follow the name cell, so a station named "Latitude" is not read as its own label.
          values = HEADER_LABELS.to_h { |label, key| [key, labelled(cells.drop(1), label, "header")] }
          %w[latitude_deg longitude_deg elevation_m].each do |key|
            raise Unreadable.new("header", "#{key} is missing") if values.fetch(key).nil?
          end
          unless values.fetch("latitude_deg").abs <= 90 && values.fetch("longitude_deg").abs <= 180
            raise Unreadable.new("header", "the latitude or longitude is out of range")
          end

          { "name" => name }.merge(values)
        end

        # The number in the first non-empty cell after `label`, or nil when the label is absent.
        def labelled(cells, label, row)
          index = cells.index { |cell| normalized(cell) == label }
          return nil if index.nil?

          value = cells.drop(index + 1).find { |cell| !cell.empty? }
          raise Unreadable.new(row, "#{label} has no value") if value.nil?

          number(value, row)
        end

        # Each series row's twelve months and, where the design cells are numbers, its three design values.
        def read_series(rows)
          found = {}
          rows.each do |cells|
            label = normalized(cells.first.to_s)
            next unless SERIES.key?(label) && !found.key?(label)

            found[label] = series_row(label, cells.drop(1))
          end
          missing = SERIES.keys - found.keys
          raise Unreadable.new(LABELS.fetch(missing.first), "the row is missing") unless missing.empty?

          found
        end

        def series_row(label, cells)
          design = SERIES.fetch(label).last
          needed = design ? MONTHS + DESIGN_CASES.length : MONTHS
          row = LABELS.fetch(label)
          if cells.length < needed || cells.first(needed).any?(&:empty?)
            raise Unreadable.new(row, "the row has #{cells.count { |cell| !cell.empty? }} values; #{needed} " \
                                      "are needed")
          end

          values = cells.first(needed).map { |cell| number(cell, row) }
          { :months => values.first(MONTHS), :design => design && values.drop(MONTHS) }
        end

        # Heating 1, Heating 2 and Cooling from the design columns. The dewpoint and sky design cells are notes in
        # the file, so those two values are null in each case, which the climate allows.
        def peak_loads(series)
          DESIGN_CASES.each_with_index.to_h do |name, index|
            values = Schema::PEAK_ROWS.to_h { |key| [key, nil] }
            series.each do |label, row|
              key = SERIES.fetch(label).last
              values[key] = row.fetch(:design).fetch(index) if key
            end
            [name, values]
          end
        end

        # The January and July wind speeds from the row that names "Wind speed"; each null when absent.
        def read_wind(rows)
          cells = rows.find { |row| row.any? { |cell| normalized(cell) == "wind speed" } }
          winds = { "wind_speed_january_m_s" => nil, "wind_speed_july_m_s" => nil }
          return winds if cells.nil?

          after = cells.drop(cells.index { |cell| normalized(cell) == "wind speed" } + 1)
          { "wind_speed_january_m_s" => labelled(after, "jan", "Wind speed"),
            "wind_speed_july_m_s" => labelled(after, "jul", "Wind speed") }
        end

        def number(text, row)
          value = NUMBER.match?(text) ? Float(text) : nil
          raise Unreadable.new(row, "a value is not a number") unless value&.finite?

          value
        end
        private_class_method :lines, :normalized, :header_index, :read_header, :labelled, :read_series,
                             :series_row, :peak_loads, :read_wind, :number
      end
    end
  end
end
