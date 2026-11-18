# frozen_string_literal: true

module PhComposer
  module Climate
    # Whether a climate is complete, and if not, what is missing by row and column. Complete is what
    # honeybee-ph's monthly and peak-load readiness checks ask for: the station elevation, the daily
    # temperature swing and the wind speed; all 96 monthly values; and in each peak-load case the air
    # temperature and the five radiation values. A case's dewpoint and sky temperature may stay null, as
    # honeybee-ph allows. The name and the station elevation are needed to save at all, so they are never
    # missing. Pure: no SketchUp constant.
    module Completeness
      SCALARS = %w[daily_temp_swing_k wind_speed_m_s].freeze
      OPTIONAL_PEAK_ROWS = %w[dewpoint_c sky_c].freeze

      module_function

      # One row per row with a gap, in grid order: `{ "row", "columns" }`, the columns being the months or
      # cases missing, and empty for a single value.
      def missing(values)
        scalars = SCALARS.select { |row| values.fetch(row).nil? }.map { |row| { "row" => row, "columns" => [] } }
        cells = Schema.grid_cells(values.fetch("monthly"), values.fetch("peak_loads")).select do |row, column, value|
          value.nil? && !(Schema::CASES.include?(column) && OPTIONAL_PEAK_ROWS.include?(row))
        end
        scalars + grouped(cells)
      end

      def complete?(values)
        missing(values).empty?
      end

      # Monthly and peak-load rows share keys such as air_c, so a row's months and its cases group apart.
      def grouped(cells)
        groups = cells.group_by { |row, column, _value| [row, Schema::CASES.include?(column)] }
        groups.map { |(row, _peak), group| { "row" => row, "columns" => group.map { |cell| cell.fetch(1) } } }
      end
    end
  end
end
