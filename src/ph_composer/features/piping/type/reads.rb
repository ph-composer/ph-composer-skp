# frozen_string_literal: true

module PhComposer
  module Piping
    module PipeType
      # Detached rows for the list and the panel. Stored values are returned as stored; the colour a type draws in
      # sits in `display`, so a client can copy `values` into `expected_values` as read.
      module Reads
        LIST = "#{FEATURE_ID}.pipe_types.list".freeze

        module_function

        def all(request)
          DefinitionLists.all(request.engine, KIND_ID) { |record| row(request.engine, record) }
        end

        def list(request)
          DefinitionLists.list(request, LIST, KIND_ID) { |record| row(request.engine, record) }
        end

        def row(engine, record)
          blockers = PipeType.export_blockers(record)
          engine.view(KIND_ID, record).merge("export_ready" => blockers.empty?, "export_blockers" => blockers,
                                             "display" => { "color" => PipeType.color(record) })
        end
      end
    end
  end
end
