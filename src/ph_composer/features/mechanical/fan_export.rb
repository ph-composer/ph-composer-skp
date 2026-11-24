# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Fan export (context/CONTRACTS.md, "Mechanical equipment"): one record per (Fan, exported Zone) pair, as
    # FanPlan works it out, for the Python section that adds each fan to its served Room as an exhaust ventilator and,
    # when the fan has Power, a linked PhSupportiveDevice of type 10 under the same identifier
    # (python/ph_composer_translation/mechanical_sections.py). The Serves payload is claimed once, by the Ventilator
    # export, whose projection gives every Zone with its slots; this section requires that one and reads it, and
    # Spaces' projection for the Zones a Space names. It reads each fan with its `user_data`, which both objects carry.
    #
    # The preflight's Fan rows come from the same plan (`preflight_rows`).
    module FanExport
      SECTION = "#{FEATURE_ID}.export.fans"
      ZONES = Zones::ExportProjection::SECTION
      SPACES = Spaces::ExportProjection::SECTION
      # One result row per pair: what conformance reads back. `digest` is the SHA-256 of the exhaust ventilator's
      # honeybee-ph dictionary as translated and `supportive_device_digest` the supportive device's (null without
      # Power), which conformance compares with each reloaded Room's own. The flow is the exhaust ventilator's, in
      # m3/s. The Python section's test holds its rows to these keys (tests/fixtures/mechanical/fan_result_fields.json).
      ROW_FIELDS = %w[id item_id zone_id zone_name display_name identifier exhaust_type quantity exhaust_flow_rate_m3s
                      annual_runtime_minutes norm_energy_demand_w in_conditioned_space annual_period_operation_khrs
                      digest supportive_device_digest].freeze
      RESULT_FIELDS = { "fans" => ROW_FIELDS }.freeze
      RESULT = RESULT_FIELDS.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1,
                                            :requires => [ZONES, VentilationExport::SECTION, SPACES],
                                            :result => RESULT) { |reader| records(reader) }
      end

      # The pairs, once the plan finds nothing blocking; every other finding is a note.
      def records(reader)
        fans = reader.records(FAN_KIND, :user_data => true).to_h { |row| [row.fetch("id"), row] }
        plan = FanPlan.call(:zones => reader.section(VentilationExport::SECTION), :fans => fans,
                            :spaced => ExportZones.spaced(reader))
        VentilationExport.raise_blocking!(plan.findings)
        plan.findings.each { |finding| reader.note(finding.code, finding.record_id, finding.message) }
        plan.pairs
      end

      # The preflight's Fan rows: a blocking row for each unreadable fan and each metadata problem the export refuses
      # (a reserved `user_data` key, an extension payload it cannot leave out), then the plan's findings over the live
      # Model, each with the code and object the export notes. `zones` are the live ExportZones and `references` each
      # Zone's occurrence reference by id. The Zones a Space names come from the Spaces read.
      def preflight_rows(request, zones, references)
        engine = request.engine
        records, unreadable = DefinitionLists.read(engine, FAN_KIND, engine.ids(FAN_KIND).sort)
        rows = unreadable.map do |row|
          Preflight.row(row.fetch("code"), SECTION, row.fetch("id"), row.fetch("message"), true)
        end
        rows.concat(Export::MetadataCheck.findings(request, records, :section => SECTION, :user_data => true))
        fans = records.to_h { |record| [record.fetch("id"), record] }
        spaced = ExportZones.live_spaced(request, zones, references, FanPlan::SLOT)
        plan = FanPlan.call(:zones => zones, :fans => fans, :spaced => spaced,
                            :unreadable => unreadable.map { |row| row.fetch("id") })
        rows + plan.findings.map do |found|
          Preflight.row(found.code, SECTION, found.record_id, found.message, found.blocks,
                        Locate.row_locate(found.record_id, references))
        end
      end
    end
  end
end
