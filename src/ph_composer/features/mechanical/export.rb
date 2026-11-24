# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Ventilator export (context/CONTRACTS.md, "Mechanical equipment"): one record per (Ventilator, exported
    # Zone) pair, as VentilationPlan works it out, for the Python section that sets each served Room's ventilation
    # system (python/ph_composer_translation/mechanical_sections.py). The section claims the Serves payload on the
    # Zone record (`entity_projections`), as Programs claims its assignment, and reads each Ventilator with its
    # `user_data`, which the unit carries. A Zone in no Building Segment is left out with its Room: its Serves
    # payload is read from the Zone record only to name what leaves with it.
    #
    # The section claims the payload for the whole feature: its projection gives every Zone once with its slots
    # (ExportZones), which each other mechanical section requires this one to read. `ph_composer.mechanical.preflight`
    # (Preflight) runs the same plan over the live Model. The report's Mechanical section reads the Python result and
    # the findings the run reported against this section.
    module VentilationExport
      SECTION = "#{FEATURE_ID}.export.ventilation"
      ZONES = Zones::ExportProjection::SECTION
      CLAIM = { "namespace" => Serves::NAMESPACE, "target_kind" => Zones::REFERENCE_KIND, "source_section" => ZONES,
                "fields" => Serves::KEYS }.freeze
      # One result row per pair: what conformance reads back and the report shows. The Python section's test holds
      # its rows to these keys (tests/fixtures/mechanical/result_fields.json).
      ROW_FIELDS = %w[id item_id zone_id zone_name display_name system_identifier unit_identifier].freeze
      RESULT_FIELDS = { "ventilation" => (ROW_FIELDS + VentilationPlan::UNIT_FIELDS).freeze }.freeze
      RESULT = RESULT_FIELDS.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze
      # A blocked export names this many of its reasons, and counts the rest.
      BLOCKING_SHOWN = 3
      # Findings about a Zone the export writes as it is, which the preflight alone reports; the run carries its
      # warnings into the result. The export notes only what it leaves out or writes for an item.
      PREFLIGHT_ONLY = [Codes::ZONE_UNVENTILATED].freeze
      REPORT_COLUMNS = ["Ventilator", "Serves", "Quantity", "Sensible recovery", "Latent recovery"].freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :requires => [ZONES], :result => RESULT,
                                            :preflight => Preflight::NAME, :entity_projections => [CLAIM],
                                            :projection => method(:zones),
                                            :report => method(:report)) { |reader| records(reader) }
      end

      # The pairs, once the plan finds nothing blocking; every other finding but the preflight's own is a note.
      def records(reader)
        plan = VentilationPlan.call(:zones => zones(reader), :ventilators => ventilators(reader))
        raise_blocking!(plan.findings)
        plan.findings.reject { |finding| PREFLIGHT_ONLY.include?(finding.code) }.each do |finding|
          reader.note(finding.code, finding.record_id, finding.message)
        end
        plan.pairs
      end

      # Every Zone once with its Serves slots (ExportZones), read once per export: this section's own plan reads it,
      # and so does every mechanical section that requires this one, through `reader.section`.
      def zones(reader)
        reader.projection(:mechanical_export_zones) { ExportZones.read(reader) }
      end

      # Stops the export on a plan's blocking findings, naming a few of them and counting the rest.
      def raise_blocking!(findings)
        blocking = findings.select(&:blocks)
        return if blocking.empty?

        messages = blocking.map(&:message).uniq
        more = messages.length > BLOCKING_SHOWN ? " And #{messages.length - BLOCKING_SHOWN} more." : ""
        raise PhComposer::Export::Blocked.new(blocking.first.code, messages.first(BLOCKING_SHOWN).join(" ") + more)
      end

      def ventilators(reader)
        reader.records(VENTILATOR_KIND, :user_data => true).to_h { |row| [row.fetch("id"), row] }
      end

      # ---------------------------------------------------------------- the preflight

      # The preflight's Ventilator rows: a blocking row for each unreadable Ventilator and each Ventilator metadata
      # problem the export refuses (a reserved `user_data` key, an extension payload it cannot leave out), then the
      # plan's findings over the live Model, each where the export reports it. `zones` are the live ExportZones and
      # `references` each Zone's occurrence reference by id.
      def preflight_rows(request, zones, references)
        records, unreadable = DefinitionLists.read(request.engine, VENTILATOR_KIND,
                                                   request.engine.ids(VENTILATOR_KIND).sort)
        rows = unreadable.map do |row|
          Preflight.row(row.fetch("code"), SECTION, row.fetch("id"), row.fetch("message"), true)
        end
        rows.concat(PhComposer::Export::MetadataCheck.findings(request, records, :section => SECTION,
                                                                                 :user_data => true))
        ventilators = records.to_h { |record| [record.fetch("id"), record] }
        plan = VentilationPlan.call(:zones => zones, :ventilators => ventilators,
                                    :unreadable => unreadable.map { |row| row.fetch("id") })
        rows + plan.findings.map do |found|
          Preflight.row(found.code, SECTION, found.record_id, found.message, found.blocks,
                        Locate.row_locate(found.record_id, references))
        end
      end

      # ---------------------------------------------------------------- the report

      # The Mechanical: Ventilators section: each exported Ventilator with the Zones it serves, as the Python result
      # reports them, and one line naming those that serve none.
      def report(result, display_units)
        rows = result.fetch("ventilation", [])
        unserved = result.findings.select { |row| row.fetch("code") == Codes::ITEM_UNSERVED }
        return [] if rows.empty? && unserved.empty?

        html = ""
        unless rows.empty?
          body = rows.group_by { |row| row.fetch("item_id") }.sort_by { |_id, pairs| pairs.first.fetch("display_name") }
                     .map { |_id, pairs| report_row(pairs, display_units) }
          efficiency = "Electric efficiency (#{Units.label(:quantity => 'electric_efficiency',
                                                           :system => display_units)})"
          html += Export::ReportHtml.table(REPORT_COLUMNS + [efficiency], body)
        end
        html += Export::ReportHtml.paragraph(unserved.map { |row| row.fetch("message") }.join(" ")) unless
          unserved.empty?
        [Export::ReportHtml.section("Mechanical: Ventilators", html)]
      end

      # Electric efficiency in the report's display units: Wh/m³, or W/cfm under IP.
      def report_row(pairs, display_units)
        unit = pairs.first
        efficiency = Units.to_display(unit.fetch("electric_efficiency_wh_m3"), :quantity => "electric_efficiency",
                                                                               :system => display_units)
        [unit.fetch("display_name"), pairs.map { |row| row.fetch("zone_name") }.sort.join(", "),
         unit.fetch("quantity").to_s, format("%.2f", unit.fetch("sensible_heat_recovery")),
         format("%.2f", unit.fetch("latent_heat_recovery")), format("%.2f", efficiency)]
      end
    end
  end
end
