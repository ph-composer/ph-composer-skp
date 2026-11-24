# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Pumps
      # Detached rows for the reads and the panel snapshot: each Pump as stored, with its metadata, its extension
      # payloads' status, its export readiness, which every stored Pump has, and the usage profile its type gives,
      # which it exports while it names none. `extra` adds what a caller composes beside a row, built from the record.
      module Reads
        LIST = "#{FEATURE_ID}.pumps.list"

        module_function

        def all(request, extra: nil)
          DefinitionLists.all(request.engine, KIND_ID) { |record| row(request.engine, record, extra) }
        end

        def list(request, extra: nil)
          DefinitionLists.list(request, LIST, KIND_ID) { |record| row(request.engine, record, extra) }
        end

        def row(engine, record, extra)
          engine.view(KIND_ID, record)
                .merge("export_ready" => true, "export_blockers" => [],
                       "ihg_usage_profile_default" => Pumps.default_ihg_usage_profile(record.fetch("device_type")))
                .merge(extra ? extra.call(record) : {})
        end
      end
    end
  end
end
