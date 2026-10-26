# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Type
      # Detached rows for the list and the panel. Stored values are returned as stored; the colour a
      # type draws in sits in `display`, so a client can copy `values` into `expected_values` as read.
      module Reads
        LIST = "#{FEATURE_ID}.types.list".freeze

        module_function

        def all(request)
          split(entries(request.engine, request.engine.ids(TYPE_KIND).sort))
        end

        # A page is cut by row count and by the size of the rows it carries, so the bounded read stays
        # within a caller's reply budget at its default limit (Pages.bounded).
        def list(request)
          ids = request.engine.ids(TYPE_KIND).sort
          ids &= request.params["ids"] if request.params.key?("ids")
          page, cursor = Pages.bounded(request, LIST, entries(request.engine, ids),
                                       :key => ->(entry) { entry.first },
                                       :size => ->(entry) { JSON.generate(entry.last).bytesize + 1 })
          split(page).merge("next_cursor" => cursor, "total" => ids.length)
        end

        # Each id with its row, or with the reason the engine cannot read it: an unreadable record is
        # reported beside the rows, never repaired or dropped silently.
        def entries(engine, ids)
          ids.map do |id|
            [id, row(engine, engine.find(TYPE_KIND, id))]
          rescue CodedError => error
            raise unless error.code == "record.unreadable"

            [id, { "id" => id, "code" => error.code, "message" => error.message }]
          end
        end

        def split(entries)
          rows, unreadable = entries.map(&:last).partition { |entry| entry.key?("values") }
          { "records" => rows, "unreadable" => unreadable }
        end

        def row(engine, record)
          blockers = Type.export_blockers(record)
          engine.view(TYPE_KIND, record).merge("export_ready" => blockers.empty?, "export_blockers" => blockers,
                                               "display" => { "color" => Type.color(record) })
        end
      end
    end
  end
end
