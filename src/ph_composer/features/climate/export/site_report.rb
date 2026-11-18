# frozen_string_literal: true

module PhComposer
  module Climate
    # The Export report's climate section (board 18), rendered from the Site section's result fields in the
    # display units the run captured: the site; the dataset and station; the Phius limit check; the edited
    # values with what the file read; the peak-load cases, with the line that Cooling 2 repeats Cooling 1; the
    # wind speed; and the design temperatures, kept in the Model and not written to the HBJSON. A climate left
    # out says why. A Model with no climate shows the site, if set, and "No climate", and nothing more (E1).
    # No folder location is in the fields, so none can appear here.
    module SiteReport
      TITLE = "Climate"
      MONTH_NAMES = %w[January February March April May June July August September October November
                       December].freeze
      CASE_NAMES = { "heat_1" => "Heating 1", "heat_2" => "Heating 2", "cool_1" => "Cooling 1",
                     "cool_2" => "Cooling 2" }.freeze
      ROW_NAMES = {
        "air_c" => "Air", "dewpoint_c" => "Dewpoint", "sky_c" => "Sky", "rad_north" => "North radiation",
        "rad_east" => "East radiation", "rad_south" => "South radiation", "rad_west" => "West radiation",
        "rad_global" => "Global radiation", "station_elevation_m" => "Station elevation",
        "daily_temp_swing_k" => "Daily temperature swing"
      }.freeze
      LEFT_OUT = {
        "site_not_set" => "Left out of the HBJSON: the site location is not set.",
        "incomplete" => "Left out of the HBJSON: %<count>d %<noun>s missing."
      }.freeze
      COOLING_2_LINE = "A Phius file has one cooling case, so Cooling 2 repeats Cooling 1."
      KEPT_LINE = "Kept in the Model; not written to the HBJSON."
      # Phius states its limits in miles and feet; these are their display labels.
      LIMITS = { "SI" => "Limits 80 km and 122 m.", "IP" => "Limits 50 mi and 400 ft." }.freeze

      module_function

      # `view` is the section's ResultView; nothing renders when the section added no fields.
      def call(view, display_units)
        return [] if view.fetch("building_segments", nil).nil?

        rows = [["Site", site(view.fetch("location"), display_units)]]
        identity = view.fetch("climate")
        rows += identity ? climate_rows(view, identity, display_units) : [%w[Climate No\ climate]]
        [PhComposer::Export::ReportHtml.section(TITLE, PhComposer::Export::ReportHtml.table(%w[Item Value], rows))]
      end

      def climate_rows(view, identity, units)
        rows = [["Climate", climate(identity, !view.fetch("edited_cells").empty?)]]
        left_out = view.fetch("climate_left_out")
        if left_out
          count = view.fetch("missing_values")
          rows << ["Exported", Kernel.format(LEFT_OUT.fetch(left_out), :count => count,
                                                                       :noun => count == 1 ? "value" : "values")]
        end
        rows << ["Phius limit check", limit_check(view.fetch("limit_check"), units)]
        rows << ["Edited values", edited(view.fetch("edited_cells"), view.fetch("climate_written"), units)]
        if view.fetch("climate_written")
          rows << ["Peak loads", peak_loads(view.fetch("peak_load_temperatures_c"), units)]
          rows << ["Wind speed", figure(identity.fetch("wind_speed_m_s"), "wind_speed", units)]
        end
        rows << ["Design temperatures",
                 design(view.fetch("design_temperatures"), view.fetch("design_temperature_source"), units)]
      end

      def site(location, units)
        return "Not set" unless location

        latitude, longitude = location.values_at("latitude_deg", "longitude_deg")
        zone = ClimateZones.label(location.fetch("climate_zone"))
        offset = location.fetch("hours_from_utc")
        ["#{degrees(latitude, 'N', 'S')}, #{degrees(longitude, 'E', 'W')}",
         figure(location.fetch("elevation_m"), "length", units),
         "climate zone #{zone}", "hours from UTC #{offset.nil? ? 'not set' : offset}"].join(" · ")
      end

      def degrees(value, positive, negative)
        "#{Kernel.format('%.3f', value.abs)}° #{value.negative? ? negative : positive}"
      end

      def climate(identity, edited)
        named = if identity.fetch("origin") == "hand"
                  "#{identity.fetch('name')}, entered by hand"
                else
                  "#{identity.fetch('dataset_name')} · #{identity.fetch('name')} (#{identity.fetch('state')})"
                end
        edited ? "#{named}, edited" : named
      end

      def limit_check(check, units)
        case check.fetch("verdict")
        when "not_checked"
          return "Not checked, entered by hand" if check.fetch("reason") == "no_station_coordinates"

          "Not checked: the site location is not set"
        else
          limits = LIMITS.fetch(units.to_s.upcase == "IP" ? "IP" : "SI")
          "#{check.fetch('verdict') == 'pass' ? 'Pass' : 'Outside the Phius limits'}. " \
            "#{figure(check.fetch('distance_km'), 'distance', units)} and " \
            "#{figure(check.fetch('elevation_difference_m'), 'length', units)} from the site. #{limits}"
        end
      end

      def edited(cells, written, units)
        return "None" if cells.empty?

        listed = cells.map do |cell|
          quantity = cell_quantity(cell)
          "#{cell_name(cell)} #{value(cell.fetch('value'), quantity, units)} " \
            "(file #{value(cell.fetch('as_read'), quantity, units)})"
        end
        noun = cells.length == 1 ? "value differs" : "values differ"
        text = "#{cells.length} #{noun} from the station file: #{listed.join('; ')}."
        written ? "#{text} Exported as a user-defined climate." : text
      end

      def cell_name(cell)
        row = cell.fetch("row")
        name = ROW_NAMES.fetch(row.sub(/_(kwh|w)_m2\z/, ""))
        column = cell.fetch("column")
        return name if column.nil?

        month = Schema::MONTHS.index(column)
        "#{name}, #{month ? MONTH_NAMES.fetch(month) : CASE_NAMES.fetch(column)}"
      end

      def cell_quantity(cell)
        row = cell.fetch("row")
        return "length" if row == "station_elevation_m"
        return "temperature_difference" if row == "daily_temp_swing_k"
        return "irradiation" if row.end_with?("_kwh_m2")
        return "irradiance" if row.end_with?("_w_m2")

        "temperature"
      end

      def peak_loads(temperatures, units)
        cases = CASE_NAMES.map { |key, name| "#{name} #{figure(temperatures.fetch(key), 'temperature', units)}" }
        "#{cases.join(' · ')}. #{COOLING_2_LINE}"
      end

      def design(temperatures, source, units)
        heating, cooling = temperatures.values_at("heating_99_c", "cooling_1_c")
        parts = ["99% heating #{value(heating, 'temperature', units)}",
                 "1% cooling #{value(cooling, 'temperature', units)}"]
        parts << source unless source.nil? || source.empty?
        "#{parts.join(' · ')}. #{KEPT_LINE}"
      end

      def value(number, quantity, units)
        number.nil? ? "not set" : figure(number, quantity, units)
      end

      def figure(number, quantity, units)
        return "not set" if number.nil?

        Units.format(number, :quantity => quantity, :system => units)
      end
    end
  end
end
