# frozen_string_literal: true

module PhComposer
  module Ducting
    # The ducting export section (context/CONTRACTS.md, "Translation sections and artifacts"): one record per
    # Ventilator whose Ducting groups hold ducts, read from the export snapshot and never the live Model, for the Python
    # section that appends the Ventilator's duct elements to every PhVentilationSystem the ventilation section built for
    # it, before that section attaches them to their Rooms (python/ph_composer_translation/ducting_sections.py). The
    # runs come from the functions the schedule uses (Runs, Extraction), over the ducts the line-group layer reads from
    # the snapshot (LineGroups::ExportScan).
    #
    # A blocking finding refuses the section, since a partial write would leave one Ventilator's Rooms unequal and
    # honeybee-ph refusing them on reload. Every other finding is a note, and so is a Ventilator whose ducts go nowhere
    # because no exported Zone names it (`ducting.ventilator_unexported`). A duct's user_data rides on its segment; a
    # Ducting group's and a Duct Type's are left out, since no honeybee-ph object stands for either. The preflight reads
    # the same findings live, with the ducts each one locates.
    module ExportProjection
      SECTION = "#{FEATURE_ID}.export.ducting"
      PREFLIGHT = "#{FEATURE_ID}.export_preflight"
      ZONES = Zones::ExportProjection::SECTION
      # The section whose objects this one appends to; its projection gives every Zone with its Serves slots, which
      # Ventilators an exported Zone names. Required, too, so it reads the Ventilators first.
      VENTILATION = Mechanical::VentilationExport::SECTION
      DUCT_FIELDS = %w[duct_type_id direction quantity].freeze
      # What conformance reads back, per element and per Ventilator. An element's shape, sizes and insulation are its
      # segments'.
      RESULT_FIELDS = {
        "elements" => %w[ventilator_id identifier duct_type segment_count length_m shape_type diameter_m width_m
                         height_m insulation_thickness_m insulation_conductivity insulation_reflective],
        "ventilators" => %w[ventilator_id system_identifier room_count supply_length_m exhaust_length_m]
      }.freeze
      RESULT = RESULT_FIELDS.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :preflight => PREFLIGHT,
                                            :requires => [ZONES, VENTILATION],
                                            :result => RESULT) { |reader| records(reader) }
        feature.query(PREFLIGHT, :description => "Ducting export checks: each run's findings with the ducts each " \
                                                 "one locates, each Ventilator missing a run or whose ducts no " \
                                                 "exported Zone takes, and each duct or Ducting group record that " \
                                                 "cannot be read.",
                                 :refuses => ScheduleRegistration::READ, :params => Mechanical::Shapes::NONE,
                                 :result => PhComposer::Export::PREFLIGHT_RESULT, :examples => [{}]) do |request|
          preflight(request)
        end
      end

      # The records, once nothing blocks; every other finding is a note. A Model with no ducts reads no Duct Type and
      # notes nothing.
      def records(reader)
        zone_paths = reader.section(ZONES).map { |row| row.fetch("zone_path") }
        edges, user_data = LineGroups::ExportScan.edges(LINE_GROUP, reader, :zone_paths => zone_paths,
                                                                            :fields => DUCT_FIELDS)
        return [] if edges.empty?

        types = reader.records(DUCT_TYPE_KIND).to_h { |row| [row.fetch("id"), row] }
        ventilators = reader.records(Mechanical::VENTILATOR_KIND).to_h { |row| [row.fetch("id"), row] }
        runs = Runs.call(edges.map { |edge| Scan.fact(edge) })
        findings = Extraction.findings(runs, :types => types, :ventilators => ventilators,
                                             :exported => exported_ventilators(reader.section(VENTILATION)))
        blocking = findings.find { |finding| finding.fetch("blocks_export") }
        raise PhComposer::Export::Blocked.new(blocking.fetch("code"), blocking.fetch("message")) if blocking

        findings.each do |finding|
          reader.note(finding.fetch("code"), finding.fetch("object_id"), finding.fetch("message"))
        end
        Extraction.records(runs, :types => types, :ventilators => ventilators, :user_data => user_data)
      end

      # The ids of the Ventilators an exported Zone names, from Mechanical's ExportZones values.
      def exported_ventilators(zones)
        zones.select(&:exported).filter_map { |zone| zone.slot(Mechanical::VentilationPlan::SLOT) }.uniq
      end

      # The export's findings over the live Model, each with the code and object the export notes and the ducts it
      # locates, a Ventilator's with Mechanical's Locate; each duct or Ducting group record that cannot be read,
      # blocking; and each metadata problem the export refuses. A read that refuses answers one blocking row, as the
      # export would stop on the same cause.
      def preflight(request)
        walked = LineGroups::Scan.walk(LINE_GROUP, request.model)
        groups = walked.first
        facts, unreadable = Scan.call(request, :walked => walked)
        findings = LineGroups::ExportScan.unreadable_findings(LINE_GROUP, unreadable, groups)
        findings = run_findings(request, facts) + findings unless facts.empty?
        rows = findings.map do |finding|
          LineGroups::ExportScan.preflight_row(SECTION, ScheduleRegistration::LOCATE, finding) do |found|
            Mechanical::Locate.row_locate(found.fetch("object_id"), {}) if found.fetch("object_id")
          end
        end
        metadata = LineGroups::ExportScan.metadata_findings(LINE_GROUP, request, SECTION, groups,
                                                            :types => !facts.empty?)
        { "findings" => rows + metadata, "repairs" => [] }
      rescue CodedError => error
        { "findings" => [{ "code" => error.code, "section" => SECTION, "object_id" => nil,
                           "message" => error.message, "blocks_export" => true }], "repairs" => [] }
      end

      # The runs' findings and the Ventilators missing a run or no exported Zone takes, as `records` gives them.
      def run_findings(request, facts)
        zones = Mechanical::ExportZones.live(Mechanical::Serves::State.zones(request))
        Extraction.findings(Runs.call(facts), :types => Scan.records(request.engine, DUCT_TYPE_KIND),
                                              :ventilators => Scan.records(request.engine, Mechanical::VENTILATOR_KIND),
                                              :exported => exported_ventilators(zones))
      end
    end
  end
end
