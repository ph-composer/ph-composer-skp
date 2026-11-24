# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Electric Heater export (context/CONTRACTS.md, "Mechanical equipment"): one record per (Electric Heater,
    # exported Zone) pair, as ElectricHeaterPlan works it out, for the Python section that adds each heater to its
    # served Room as a PhHeatingDirectElectric (python/ph_composer_translation/mechanical_sections.py). The Serves
    # payload is claimed once, by the Ventilator export, whose projection gives every Zone with its slots; this
    # section requires that one and reads it. It reads each heater with its `user_data`, which the heating system
    # carries.
    #
    # The preflight's Electric Heater rows come from the same plan (`preflight_rows`).
    module ElectricHeaterExport
      SECTION = "#{FEATURE_ID}.export.electric_heaters"
      ZONES = Zones::ExportProjection::SECTION
      # One result row per pair: what conformance reads back. `digest` is the SHA-256 of the heating system's
      # honeybee-ph dictionary as translated, which conformance compares with each reloaded Room's own. The Python
      # section's test holds its rows to these keys (tests/fixtures/mechanical/electric_heater_result_fields.json).
      ROW_FIELDS = %w[id item_id zone_id zone_name display_name identifier percent_coverage digest].freeze
      RESULT_FIELDS = { "electric_heaters" => ROW_FIELDS }.freeze
      RESULT = RESULT_FIELDS.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :requires => [ZONES, VentilationExport::SECTION],
                                            :result => RESULT) { |reader| records(reader) }
      end

      # The pairs, once the plan finds nothing blocking; every other finding is a note.
      def records(reader)
        heaters = reader.records(ELECTRIC_HEATER_KIND, :user_data => true).to_h { |row| [row.fetch("id"), row] }
        plan = ElectricHeaterPlan.call(:zones => reader.section(VentilationExport::SECTION), :heaters => heaters)
        VentilationExport.raise_blocking!(plan.findings)
        plan.findings.each { |finding| reader.note(finding.code, finding.record_id, finding.message) }
        plan.pairs
      end

      # The preflight's Electric Heater rows: a blocking row for each unreadable heater and each metadata problem the
      # export refuses (a reserved `user_data` key, an extension payload it cannot leave out), then the plan's
      # findings over the live Model, each with the code and object the export notes. `zones` are the live
      # ExportZones and `references` each Zone's occurrence reference by id.
      def preflight_rows(request, zones, references)
        engine = request.engine
        records, unreadable = DefinitionLists.read(engine, ELECTRIC_HEATER_KIND,
                                                   engine.ids(ELECTRIC_HEATER_KIND).sort)
        rows = unreadable.map do |row|
          Preflight.row(row.fetch("code"), SECTION, row.fetch("id"), row.fetch("message"), true)
        end
        rows.concat(Export::MetadataCheck.findings(request, records, :section => SECTION, :user_data => true))
        heaters = records.to_h { |record| [record.fetch("id"), record] }
        plan = ElectricHeaterPlan.call(:zones => zones, :heaters => heaters,
                                       :unreadable => unreadable.map { |row| row.fetch("id") })
        rows + plan.findings.map do |found|
          Preflight.row(found.code, SECTION, found.record_id, found.message, found.blocks,
                        Locate.row_locate(found.record_id, references))
        end
      end
    end
  end
end
