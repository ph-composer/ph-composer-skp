# frozen_string_literal: true

module PhComposer
  module Programs
    # The Program export's part of the export report (ProgramExport): each Building Segment's set points and its
    # Dwellings' counts, read from the Python result, never the Ruby records.
    module ProgramReport
      module_function

      # Each Building Segment's set points and Dwellings, as the Python result reports them.
      def call(result, display_units)
        points = result.fetch("set_points", [])
        return [] if points.empty?

        unit = PhComposer::Units.label(:quantity => "temperature", :system => display_units)
        temperature = lambda do |value|
          format("%.1f", PhComposer::Units.to_display(value, :quantity => "temperature", :system => display_units))
        end
        html = Export::ReportHtml.table(["Building Segment", "Heating (#{unit})", "Cooling (#{unit})"],
                                        points.map do |row|
                                          [row.fetch("name"), temperature.call(row.fetch("winter_c")),
                                           temperature.call(row.fetch("summer_c"))]
                                        end)
        names = points.to_h { |row| [row.fetch("export_identifier"), row.fetch("name")] }
        dwellings = result.fetch("dwellings", [])
        unless dwellings.empty?
          html += Export::ReportHtml.heading(3, "Dwellings") +
                  Export::ReportHtml.table(%w[Dwelling Building\ Segment Units Bedrooms Occupants],
                                           dwellings.map do |row|
                                             [row.fetch("name"), names.fetch(row.fetch("export_identifier"), ""),
                                              row.fetch("units").to_s, count(row["bedrooms"]),
                                              count(row["occupants"])]
                                           end)
        end
        [Export::ReportHtml.section("Programs", html)]
      end

      def count(value)
        value.nil? ? "—" : format("%g", value)
      end
    end
  end
end
