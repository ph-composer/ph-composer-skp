# frozen_string_literal: true

module PhComposer
  module Climate
    # The Model's one climate: a record of its own kind under one fixed id, so no record means no climate and
    # Clear is a delete. Every object in it is closed, so no key the schema does not list, a file location
    # among them, can be stored by accident. Values are SI and each key names its unit.
    #
    # The values form a grid in the order of a Phius climate file: eight monthly rows of twelve months, and
    # the same eight rows for the three peak-load cases. A cell is addressed by `row`, the record key, and
    # `column`, a month or a case; a single value such as the daily temperature swing has a null column.
    module Schema
      KIND_ID = "#{FEATURE_ID}.climate".freeze
      RECORD_ID = "clm_AAAAAAAAAAAA"
      MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze
      CASES = %w[heat_1 heat_2 cool_1].freeze
      TEMPERATURE_ROWS = %w[air_c dewpoint_c sky_c].freeze
      DIRECTIONS = %w[north east south west global].freeze
      MONTHLY_ROWS = (TEMPERATURE_ROWS + DIRECTIONS.map { |direction| "rad_#{direction}_kwh_m2" }).freeze
      PEAK_ROWS = (TEMPERATURE_ROWS + DIRECTIONS.map { |direction| "rad_#{direction}_w_m2" }).freeze
      # The single values the grid compares with the as-read copy. Wind speed is typed, prefilled from the file,
      # and is never an edit, so it is not one of them.
      READ_SCALARS = %w[station_elevation_m daily_temp_swing_k].freeze
      # What Enter Values and Edit Values write: everything but the origin, the as-read copy and the provenance.
      EDITABLE = %w[name station_latitude_deg station_longitude_deg station_elevation_m daily_temp_swing_k
                    wind_speed_m_s monthly peak_loads].freeze
      # A station's identity, which comes from its file; Replace changes it, Edit Values does not.
      STATION_IDENTITY = %w[name station_latitude_deg station_longitude_deg].freeze
      # Only a station's file is approved Phius data; an edit or a typed climate is the user's own.
      APPROVED = "phius_approved"
      USER_DEFINED = "user_defined"

      UNITS = { "_c" => "degC", "_kwh_m2" => "kWh/m2", "_w_m2" => "W/m2" }.freeze

      module_function

      def unit(row)
        UNITS.find { |suffix, _unit| row.end_with?(suffix) }.last
      end

      def number(unit, description = nil)
        value = { "type" => %w[number null], "x-unit" => unit }
        description ? described(value, description) : value
      end

      def described(schema, description)
        schema.merge("description" => description)
      end

      def coordinate(unit, range)
        { "type" => %w[number null], "minimum" => -range, "maximum" => range, "x-unit" => unit,
          "description" => "The station's coordinate in decimal degrees; null only for a climate typed without one." }
      end

      def month_row(row)
        { "type" => "array", "minItems" => 12, "maxItems" => 12, "items" => number(unit(row)) }
      end

      # The grid's cells carry no description of their own, since the record repeats them in its as-read copy
      # and a write's params repeat them again; the rows say it once.
      MONTHLY = SchemaShapes.object(MONTHLY_ROWS.to_h { |row| [row, month_row(row)] },
                                    :description => "Eight rows of twelve months, January first; a value is null " \
                                                    "while not entered.").freeze
      PEAK_CASE = SchemaShapes.object(PEAK_ROWS.to_h { |row| [row, number(unit(row))] }).freeze
      PEAK_LOADS = SchemaShapes.object(CASES.to_h { |name| [name, PEAK_CASE] },
                                       :description => "Heating 1, Heating 2 and Cooling, each with the monthly " \
                                                       "rows' eight values in W/m2 for radiation; null while not " \
                                                       "entered, and dewpoint and sky may stay null.").freeze
      STATION_ELEVATION = { "type" => "number", "x-unit" => "m",
                            "description" => "The station's height above sea level; needed." }.freeze
      SWING = number("K", "The summer daily temperature swing; null while not entered.").freeze
      AS_READ = SchemaShapes.object({
        "station_elevation_m" => STATION_ELEVATION, "daily_temp_swing_k" => SWING,
        "monthly" => MONTHLY, "peak_loads" => PEAK_LOADS
      }, :description => "The station file's own values, kept so edits show and Restore works anywhere; null " \
                         "for a climate entered by hand.").freeze
      CELL = SchemaShapes.object({
        "row" => { "type" => "string", "description" => "The record key: a monthly or peak-load row, or a " \
                                                        "single value such as daily_temp_swing_k." },
        "column" => { "type" => %w[string null], "enum" => MONTHS + CASES + [nil],
                      "description" => "A month or a peak-load case; null for a single value." }
      }).freeze
      EDITED_CELL = SchemaShapes.with(CELL, "value" => { "type" => %w[number null] },
                                            "as_read" => { "type" => %w[number null] }).freeze
      NULL_TEXT = { "type" => %w[string null] }.freeze
      ASSUMPTIONS = SchemaShapes.object({
        "ph_composer" => SchemaShapes.object({
          "station_latitude_deg" => { "type" => %w[number null], "x-unit" => "deg" },
          "station_longitude_deg" => { "type" => %w[number null], "x-unit" => "deg" },
          "edited_values" => SchemaShapes.list(EDITED_CELL, :description => "Each value that differs from the " \
                                                                            "station file, with what the file " \
                                                                            "read.")
        })
      }).freeze
      # honeybee-ph's ClimateProvenance fields after the first three, which are the Model's own; export passes
      # them through. honeybee-ph's source_uri is not one of them.
      PROVENANCE = SchemaShapes.object({
        "dataset_name" => NULL_TEXT, "station_name" => NULL_TEXT,
        "state" => described(NULL_TEXT, "The station's state, named as its folder is, such as NY; never a " \
                                        "location on disk. Null for a climate entered by hand."),
        "source_type" => { "type" => "string", "enum" => [APPROVED, USER_DEFINED] },
        "source_name" => NULL_TEXT, "source_version" => NULL_TEXT,
        "source_checksum" => { "type" => %w[string null], "pattern" => "^[0-9a-f]{64}$",
                               "description" => "The station file's SHA-256; null for a climate entered by hand." },
        "conversion_method" => NULL_TEXT, "conversion_method_version" => NULL_TEXT,
        "is_certification_approved" => { "type" => %w[boolean null] },
        "monthly_data_available" => { "type" => "boolean" }, "peak_load_data_available" => { "type" => "boolean" },
        "assumptions" => ASSUMPTIONS
      }).freeze

      FIELDS = [
        Records::Field.new(:key => "name", :required => true, :schema => { "type" => "string", "minLength" => 1 }),
        Records::Field.new(:key => "origin", :required => true,
                           :schema => { "type" => "string", "enum" => %w[station hand] }),
        Records::Field.new(:key => "station_latitude_deg", :required => true, :schema => coordinate("deg", 90)),
        Records::Field.new(:key => "station_longitude_deg", :required => true,
                           :schema => coordinate("deg", 180)),
        Records::Field.new(:key => "station_elevation_m", :required => true, :schema => STATION_ELEVATION),
        Records::Field.new(:key => "daily_temp_swing_k", :required => true, :schema => SWING),
        Records::Field.new(:key => "wind_speed_m_s", :required => true,
                           :schema => number("m/s", "The average wind speed; null while not entered.")),
        Records::Field.new(:key => "monthly", :required => true, :schema => MONTHLY),
        Records::Field.new(:key => "peak_loads", :required => true, :schema => PEAK_LOADS),
        Records::Field.new(:key => "as_read", :required => true,
                           :schema => AS_READ.merge("type" => %w[object null])),
        Records::Field.new(:key => "provenance", :required => true, :schema => PROVENANCE)
      ].freeze

      KIND = Records::RecordKind.new(:id => KIND_ID, :label => "Climate", :schema_version => 1, :id_prefix => "clm",
                                     :fields => FIELDS, :validate => ->(values) { Schema.problems(values) })

      # The rules a schema cannot hold: a station keeps its coordinates and its file's copy, and a climate
      # entered by hand has no file, so it has neither the copy nor a file's identity.
      def problems(values)
        coordinates = values.values_at("station_latitude_deg", "station_longitude_deg").compact.length
        found = []
        found << "station latitude and longitude are given together" if coordinates == 1
        provenance = values.fetch("provenance")
        file_identity = provenance.values_at("dataset_name", "station_name", "state", "source_checksum")
        if values.fetch("origin") == "station"
          found << "a station climate keeps its coordinates" unless coordinates == 2
          found << "a station climate keeps the values its file read" if values.fetch("as_read").nil?
          found << "a station climate names its dataset, station, state and checksum" if file_identity.include?(nil)
        else
          found << "a climate entered by hand has no as-read copy" unless values.fetch("as_read").nil?
          found << "a climate entered by hand names no station file" unless file_identity.compact.empty?
        end
        found
      end

      # Each [row, column, value] of a `monthly` and `peak_loads` pair, months first, in grid order.
      def grid_cells(monthly, peak_loads)
        months = MONTHLY_ROWS.flat_map do |row|
          MONTHS.each_with_index.map { |month, index| [row, month, monthly.fetch(row).fetch(index)] }
        end
        peaks = PEAK_ROWS.flat_map { |row| CASES.map { |name| [row, name, peak_loads.fetch(name).fetch(row)] } }
        months + peaks
      end

      # A grid of nulls, the shape of `monthly` and `peak_loads` before anything is entered.
      def empty_monthly
        MONTHLY_ROWS.to_h { |row| [row, Array.new(12)] }
      end

      def empty_peak_loads
        CASES.to_h { |name| [name, PEAK_ROWS.to_h { |row| [row, nil] }] }
      end
    end
  end
end
