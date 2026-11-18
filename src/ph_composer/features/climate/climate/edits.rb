# frozen_string_literal: true

module PhComposer
  module Climate
    # The edited cells of a station climate: every monthly and peak-load value, the daily temperature swing
    # and the station elevation that differ from the copy its file read. Derived, never stored apart from the
    # provenance's list, which every write rebuilds from this. Wind speed is typed and is never an edit, and a
    # climate entered by hand has no file to differ from. Pure: no SketchUp constant.
    module Edits
      module_function

      # `{ "row", "column", "value", "as_read" }` for each difference, single values first, then grid order.
      def cells(values)
        as_read = values.fetch("as_read")
        return [] if as_read.nil?

        scalars = Schema::READ_SCALARS.map { |row| [row, nil, values.fetch(row), as_read.fetch(row)] }
        grid = Schema.grid_cells(values.fetch("monthly"), values.fetch("peak_loads"))
                     .zip(Schema.grid_cells(as_read.fetch("monthly"), as_read.fetch("peak_loads")))
                     .map { |(row, column, value), (_row, _column, read)| [row, column, value, read] }
        (scalars + grid).reject { |_row, _column, value, read| value == read }.map do |row, column, value, read|
          { "row" => row, "column" => column, "value" => value, "as_read" => read }
        end
      end
    end
  end
end
