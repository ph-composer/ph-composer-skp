# frozen_string_literal: true

module PhComposer
  module Piping
    # The piping export section (context/CONTRACTS.md, "Translation sections and artifacts"): one record per Hot
    # Water System whose Piping groups hold pipes, read from the export snapshot and never the live Model, for the
    # Python section that adds the System's trunks and recirculation elements to every PhHotWaterSystem the hot water
    # section built for it, before that section attaches them to their Rooms
    # (python/ph_composer_translation/piping_sections.py). The runs come from the functions the schedule uses
    # (Runs::Tree, Runs::Extraction), over facts the snapshot gives instead of the live walk: the Piping group
    # entries and the pipe entries directly inside them.
    #
    # A blocking finding refuses the section, since a partial write would leave one System's Rooms unequal. Every
    # other finding is a note, and so is a System whose pipes go nowhere because no exported Zone names it
    # (`piping.system_unexported`). A pipe's user_data rides on its segment; a Piping group's and a Pipe Type's are
    # left out, since no honeybee-ph object stands for either. The preflight reads the same findings live, with the
    # pipes each one locates.
    module ExportProjection
      SECTION = "#{FEATURE_ID}.export.piping"
      PREFLIGHT = "#{FEATURE_ID}.export_preflight"
      ZONES = Zones::ExportProjection::SECTION
      # The Zones with their Serves slots: which Systems an exported Zone names.
      SERVES = Mechanical::VentilationExport::SECTION
      # The section whose objects this one adds to; required so it reads the Systems first, and names any of their
      # findings.
      HOT_WATER = Mechanical::HotWaterExport::SECTION
      PIPE_FIELDS = (%w[pipe_type_id role] + Assignment::ROLE_SCHEMAS.keys).freeze
      # What conformance reads back, per trunk, recirculation element and System. A trunk's `twig_counts` are its
      # branches' twig counts in identifier order.
      RESULT_FIELDS = {
        "trunks" => %w[system_id identifier multiplier demand_recirculation length_m branch_count twig_counts],
        "recirculation" => %w[system_id identifier length_m],
        "systems" => %w[system_id room_count recirculation_temperature_c recirculation_hours]
      }.freeze
      RESULT = RESULT_FIELDS.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :preflight => PREFLIGHT,
                                            :requires => [ZONES, SERVES, HOT_WATER],
                                            :result => RESULT) { |reader| records(reader) }
        feature.query(PREFLIGHT, :description => "Piping export checks: each run's findings with the pipes each " \
                                                 "one locates, each pipe or Piping group record that cannot be " \
                                                 "read, and each Hot Water System whose pipes no exported Zone " \
                                                 "takes.",
                                 :refuses => ScheduleRegistration::READ, :params => Shapes::NONE,
                                 :result => PhComposer::Export::PREFLIGHT_RESULT, :examples => [{}]) do |request|
          preflight(request)
        end
      end

      # The records, once nothing blocks; every other finding is a note. A Model with no pipes reads no Pipe Type.
      def records(reader)
        facts, user_data = facts(reader)
        return [] if facts.empty?

        types = reader.records(PIPE_TYPE_KIND).to_h { |row| [row.fetch("id"), row] }
        systems = reader.records(Mechanical::HOT_WATER_SYSTEM_KIND).to_h { |row| [row.fetch("id"), row] }
        runs = Runs::Tree.call(facts)
        findings = Runs::Extraction.findings(runs, :types => types, :systems => systems,
                                                   :exported => exported_systems(reader.section(SERVES)))
        blocking = findings.find { |finding| finding.fetch("blocks_export") }
        raise PhComposer::Export::Blocked.new(blocking.fetch("code"), blocking.fetch("message")) if blocking

        findings.each do |finding|
          reader.note(finding.fetch("code"), finding.fetch("object_id"), finding.fetch("message"))
        end
        Runs::Extraction.records(runs, :types => types, :systems => systems, :user_data => user_data)
      end

      # The ids of the Systems an exported Zone names, from Mechanical's ExportZones values.
      def exported_systems(zones)
        zones.select(&:exported).filter_map { |zone| zone.slot(Mechanical::HotWaterPlan::SLOT) }.uniq
      end

      # Every pipe the snapshot holds directly inside a Piping group, as a Runs::Fact, and each pipe's user_data by
      # path, read through the line-group layer's snapshot read (LineGroups::ExportScan.edges), which says what is
      # `in_zone` and `shared` and which records refuse the export.
      def facts(reader)
        zone_paths = reader.section(ZONES).map { |row| row.fetch("zone_path") }
        edges, user_data = LineGroups::ExportScan.edges(LINE_GROUP, reader, :zone_paths => zone_paths,
                                                                            :fields => PIPE_FIELDS)
        facts = edges.map do |edge|
          record = edge.record
          role = record.fetch("role")
          Runs::Fact.new(:path => edge.path, :group => edge.group, :record_id => record.fetch("id"),
                         :pipe_type_id => record.fetch("pipe_type_id"), :role => role,
                         :values => record.slice(*Assignment::ROLE_VALUES.fetch(role).keys),
                         :points_m => edge.points_m, :vertex_ids => edge.vertex_ids, :shared => edge.shared)
        end
        [facts, user_data]
      end

      # The export's findings over the live Model, each with the code and object the export notes and the pipes it
      # locates; each pipe or Piping group record that cannot be read, blocking; and each metadata problem the export
      # refuses. A read that refuses answers one blocking row, as the export would stop on the same cause.
      def preflight(request)
        walked = Scan.walk(request.model)
        groups = walked.first
        facts, unreadable = Scan.call(request, :walked => walked)
        findings = LineGroups::ExportScan.unreadable_findings(LINE_GROUP, unreadable, groups)
        findings = run_findings(request, facts) + findings unless facts.empty?
        rows = findings.map do |finding|
          LineGroups::ExportScan.preflight_row(SECTION, ScheduleRegistration::LOCATE, finding) do |found|
            next unless found.fetch("code") == Codes::SYSTEM_UNEXPORTED

            Mechanical::Locate.row_locate(found.fetch("object_id"), {})
          end
        end
        metadata = LineGroups::ExportScan.metadata_findings(LINE_GROUP, request, SECTION, groups,
                                                            :types => !facts.empty?)
        { "findings" => rows + metadata, "repairs" => [] }
      rescue CodedError => error
        { "findings" => [{ "code" => error.code, "section" => SECTION, "object_id" => nil,
                           "message" => error.message, "blocks_export" => true }], "repairs" => [] }
      end

      # The runs' findings and the Systems no exported Zone takes, as `records` gives them.
      def run_findings(request, facts)
        zones = Mechanical::ExportZones.live(Mechanical::Serves::State.zones(request))
        Runs::Extraction.findings(Runs::Tree.call(facts),
                                  :types => Scan.records(request.engine, PIPE_TYPE_KIND),
                                  :systems => Scan.records(request.engine, Mechanical::HOT_WATER_SYSTEM_KIND),
                                  :exported => exported_systems(zones))
      end
    end
  end
end
