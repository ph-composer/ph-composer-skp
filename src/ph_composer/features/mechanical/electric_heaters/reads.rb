# frozen_string_literal: true

module PhComposer
  module Mechanical
    module ElectricHeaters
      # Detached rows for the reads and the panel snapshot: each Electric Heater as stored, with its metadata, its
      # extension payloads' status and its export readiness, which every stored heater has. `extra` adds what a
      # caller composes beside a row, built from the record.
      module Reads
        LIST = "#{FEATURE_ID}.electric_heaters.list"

        module_function

        def all(request, extra: nil)
          DefinitionLists.all(request.engine, KIND_ID) { |record| row(request.engine, record, extra) }
        end

        def list(request, extra: nil)
          DefinitionLists.list(request, LIST, KIND_ID) { |record| row(request.engine, record, extra) }
        end

        def row(engine, record, extra)
          engine.view(KIND_ID, record).merge("export_ready" => true, "export_blockers" => [])
                .merge(extra ? extra.call(record) : {})
        end
      end
    end
  end
end
