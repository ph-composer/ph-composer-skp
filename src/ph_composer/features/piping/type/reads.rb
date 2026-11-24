# frozen_string_literal: true

module PhComposer
  module Piping
    module PipeType
      # Detached rows for the list and the panel. Stored values are returned as stored; the colour a type draws in
      # sits in `display`, so a client can copy `values` into `expected_values` as read. `used` maps a type id to the
      # drawn length of the pipes naming it, which the caller measures; a type with none reads zero.
      module Reads
        LIST = "#{FEATURE_ID}.pipe_types.list".freeze

        module_function

        def all(request, used)
          DefinitionLists.all(request.engine, KIND_ID) { |record| row(request.engine, record, used) }
        end

        def list(request, used)
          DefinitionLists.list(request, LIST, KIND_ID) { |record| row(request.engine, record, used) }
        end

        def row(engine, record, used)
          blockers = PipeType.export_blockers(record)
          engine.view(KIND_ID, record).merge("export_ready" => blockers.empty?, "export_blockers" => blockers,
                                             "display" => { "color" => PipeType.color(record) },
                                             "used_length_m" => used.fetch(record.fetch("id"), 0.0))
        end
      end
    end
  end
end
