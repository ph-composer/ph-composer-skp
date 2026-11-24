# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Ventilators
      # Detached rows for the reads and the panel snapshot: each Ventilator as stored, with its metadata, its
      # extension payloads' status and whether it can export. `extra` adds what a caller composes beside a row,
      # built from the record.
      module Reads
        LIST = "#{FEATURE_ID}.ventilators.list".freeze

        module_function

        def all(request, extra: nil)
          DefinitionLists.all(request.engine, VENTILATOR_KIND) { |record| row(request.engine, record, extra) }
        end

        def list(request, extra: nil)
          DefinitionLists.list(request, LIST, VENTILATOR_KIND) { |record| row(request.engine, record, extra) }
        end

        def row(engine, record, extra = nil)
          blockers = Ventilators.export_blockers(record)
          engine.view(VENTILATOR_KIND, record).merge("export_ready" => blockers.empty?, "export_blockers" => blockers)
                .merge(extra ? extra.call(record) : {})
        end
      end
    end
  end
end
