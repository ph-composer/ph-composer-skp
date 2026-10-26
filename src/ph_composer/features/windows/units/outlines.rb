# frozen_string_literal: true

require_relative "read_context"

module PhComposer
  module Windows
    module Units
      # Each placed Unit's world outline in metres, with its reference and the Zone Face it is glued to (or nil),
      # from the same geometry the placement and glue checks use. It names no reader's purpose: a feature that
      # needs to know where Windows sit in the Model reads this rather than Windows' own records. A Unit whose
      # native geometry is unknown has no outline and is left out. Writes nothing; rows come in bounded pages.
      module Outlines
        QUERY = "#{FEATURE_ID}.units.outlines"

        module_function

        # A bad limit or cursor refuses before the Model is walked.
        def read(request)
          Pages.limit(request.params)
          Pages.position(request, QUERY)
          reads = ReadContext.new(request)
          rows = reads.occurrences.sort_by(&:path).filter_map do |item|
            polygon = reads.read_polygon(item)
            next unless polygon

            { "reference" => item.reference, "host" => reads.glued_reference(item), "outline_m" => polygon }
          end
          key = ->(row) { row.dig("reference", "entity_path") }
          page, next_cursor = Pages.bounded(request, QUERY, rows, :key => key)
          { "units" => page, "next_cursor" => next_cursor, "total" => rows.length }
        end
      end
    end
  end
end
