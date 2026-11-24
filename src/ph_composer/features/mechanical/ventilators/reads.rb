# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Ventilators
      # Detached rows for the reads and the panel snapshot: each Ventilator as stored, with its metadata, its
      # extension payloads' status and whether it can export.
      module Reads
        LIST = "#{FEATURE_ID}.ventilators.list".freeze

        module_function

        def all(request)
          DefinitionLists.all(request.engine, VENTILATOR_KIND) { |record| row(request.engine, record) }
        end

        def list(request)
          DefinitionLists.list(request, LIST, VENTILATOR_KIND) { |record| row(request.engine, record) }
        end

        def row(engine, record)
          blockers = Ventilators.export_blockers(record)
          engine.view(VENTILATOR_KIND, record).merge("export_ready" => blockers.empty?, "export_blockers" => blockers)
        end
      end
    end
  end
end
