# frozen_string_literal: true

module PhComposer
  module Mechanical
    module HeatPumps
      # Detached rows for the four tables' reads and the panel snapshot: each record as stored, with its metadata,
      # its extension payloads' status and its export readiness. `extra` adds what a caller composes beside a row,
      # built from the record (HeatPumpReads).
      module Reads
        LISTS = { OutdoorEquipment::KIND_ID => "#{FEATURE_ID}.heat_pumps.outdoor_equipment.list",
                  IndoorEquipment::KIND_ID => "#{FEATURE_ID}.heat_pumps.indoor_equipment.list",
                  OutdoorUnits::KIND_ID => "#{FEATURE_ID}.heat_pumps.outdoor_units.list",
                  IndoorUnits::KIND_ID => "#{FEATURE_ID}.heat_pumps.indoor_units.list" }.freeze

        module_function

        def all(request, kind, extra: nil)
          DefinitionLists.all(request.engine, kind) { |record| row(request.engine, kind, record, extra) }
        end

        def list(request, kind, extra: nil)
          DefinitionLists.list(request, LISTS.fetch(kind), kind) do |record|
            row(request.engine, kind, record, extra)
          end
        end

        # An outdoor model lacking a value the blend needs is not export ready; every other record is.
        def row(engine, kind, record, extra)
          missing = kind == OutdoorEquipment::KIND_ID ? OutdoorEquipment.missing_inputs(record) : []
          blockers = missing.empty? ? [] : [Codes::HP_EQUIPMENT_INCOMPLETE]
          view = engine.view(kind, record).merge("export_ready" => missing.empty?, "export_blockers" => blockers)
          extra ? view.merge(extra.call(record)) : view
        end
      end
    end
  end
end
