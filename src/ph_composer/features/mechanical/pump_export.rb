# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Pump export (context/CONTRACTS.md, "Mechanical equipment"): one record per (Pump, exported Zone) pair, as
    # PumpPlan works it out, for the Python section that adds each pump to its served Room as a PhSupportiveDevice
    # (python/ph_composer_translation/mechanical_sections.py). The Serves payload is claimed once, by the Ventilator
    # export, whose projection gives every Zone with its slots; this section requires that one and reads it, and
    # Spaces' projection for the Zones a Space names. It reads each pump with its `user_data`, which the supportive
    # device carries.
    #
    # The preflight's Pump rows come from the same plan (`preflight_rows`).
    module PumpExport
      SECTION = "#{FEATURE_ID}.export.pumps"
      ZONES = Zones::ExportProjection::SECTION
      SPACES = Spaces::ExportProjection::SECTION
      # One result row per pair: what conformance reads back. `digest` is the SHA-256 of the supportive device's
      # honeybee-ph dictionary as translated, which conformance compares with each reloaded Room's own. The Python
      # section's test holds its rows to these keys (tests/fixtures/mechanical/pump_result_fields.json).
      ROW_FIELDS = (%w[id item_id zone_id zone_name display_name identifier] + PumpPlan::VALUES +
                    %w[ihg_usage_profile digest]).freeze
      RESULT_FIELDS = { "pumps" => ROW_FIELDS }.freeze
      RESULT = RESULT_FIELDS.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1,
                                            :requires => [ZONES, VentilationExport::SECTION, SPACES],
                                            :result => RESULT) { |reader| records(reader) }
      end

      # The pairs, once the plan finds nothing blocking; every other finding is a note.
      def records(reader)
        pumps = reader.records(PUMP_KIND, :user_data => true).to_h { |row| [row.fetch("id"), row] }
        plan = PumpPlan.call(:zones => reader.section(VentilationExport::SECTION), :pumps => pumps,
                             :spaced => ExportZones.spaced(reader))
        VentilationExport.raise_blocking!(plan.findings)
        plan.findings.each { |finding| reader.note(finding.code, finding.record_id, finding.message) }
        plan.pairs
      end

      # The preflight's Pump rows: a blocking row for each unreadable pump and each metadata problem the export
      # refuses (a reserved `user_data` key, an extension payload it cannot leave out), then the plan's findings over
      # the live Model, each with the code and object the export notes. `zones` are the live ExportZones and
      # `references` each Zone's occurrence reference by id. The Zones a Space names come from the Spaces read.
      def preflight_rows(request, zones, references)
        engine = request.engine
        records, unreadable = DefinitionLists.read(engine, PUMP_KIND, engine.ids(PUMP_KIND).sort)
        rows = unreadable.map do |row|
          Preflight.row(row.fetch("code"), SECTION, row.fetch("id"), row.fetch("message"), true)
        end
        rows.concat(Export::MetadataCheck.findings(request, records, :section => SECTION, :user_data => true))
        pumps = records.to_h { |record| [record.fetch("id"), record] }
        spaced = ExportZones.live_spaced(request, zones, references, PumpPlan::SLOT)
        plan = PumpPlan.call(:zones => zones, :pumps => pumps, :spaced => spaced,
                             :unreadable => unreadable.map { |row| row.fetch("id") })
        rows + plan.findings.map do |found|
          Preflight.row(found.code, SECTION, found.record_id, found.message, found.blocks,
                        Locate.row_locate(found.record_id, references))
        end
      end
    end
  end
end
