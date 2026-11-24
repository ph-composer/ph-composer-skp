# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Fans
      # Detached rows for the reads and the panel snapshot: each Fan as stored, with its metadata, its extension
      # payloads' status, its export readiness, which every stored Fan has, and the operation its runtime gives,
      # which its supportive device exports while it names none. `extra` adds what a caller composes beside a row,
      # built from the record.
      module Reads
        LIST = "#{FEATURE_ID}.fans.list"

        module_function

        def all(request, extra: nil)
          DefinitionLists.all(request.engine, KIND_ID) { |record| row(request.engine, record, extra) }
        end

        def list(request, extra: nil)
          DefinitionLists.list(request, LIST, KIND_ID) { |record| row(request.engine, record, extra) }
        end

        def row(engine, record, extra)
          default = Fans.default_annual_period_operation_khrs(record.fetch("annual_runtime_minutes"))
          engine.view(KIND_ID, record)
                .merge("export_ready" => true, "export_blockers" => [],
                       "annual_period_operation_khrs_default" => default)
                .merge(extra ? extra.call(record) : {})
        end
      end
    end
  end
end
