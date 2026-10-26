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
          DefinitionLists.all(request.engine, TYPE_KIND) { |record| row(request.engine, record) }
        end

        def list(request)
          DefinitionLists.list(request, LIST, TYPE_KIND) { |record| row(request.engine, record) }
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
