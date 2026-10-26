# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Type
      # Detached rows for the list and the panel. Stored values are returned as stored; the colour a
      # type draws in sits in `display`, so a client can copy `values` into `expected_values` as read.
      module Reads
        module_function

        def all(request)
          rows, unreadable = rows(request, request.engine.ids(TYPE_KIND).sort)
          { "records" => rows, "unreadable" => unreadable }
        end

        def list(request)
          ids = request.engine.ids(TYPE_KIND).sort
          ids &= request.params["ids"] if request.params.key?("ids")
          page, cursor = Pages.slice(request, "#{FEATURE_ID}.types.list", ids, :key => ->(id) { id })
          rows, unreadable = rows(request, page)
          { "records" => rows, "unreadable" => unreadable, "next_cursor" => cursor, "total" => ids.length }
        end

        # A record the engine cannot read is reported beside the rows, never repaired or dropped silently.
        def rows(request, ids)
          rows = []
          unreadable = []
          ids.each do |id|
            rows << row(request.engine, request.engine.find(TYPE_KIND, id))
          rescue CodedError => error
            raise unless error.code == "record.unreadable"

            unreadable << { "id" => id, "code" => error.code, "message" => error.message }
          end
          [rows, unreadable]
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
