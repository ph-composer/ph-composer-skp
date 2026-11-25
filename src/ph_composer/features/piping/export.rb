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
      # path. A Piping group a Zone holds is `in_zone`, from the Zones section's occurrences. A pipe is `shared` when a
      # ComponentInstance holds it or the snapshot reaches its Edge at two paths, as a pasted Piping group does: the
      # live scan reads that from the Group's definition, which the snapshot does not keep. A record that cannot be read
      # refuses the export, as the schedule's unreadable rows block it; an Edge outside every Piping group is not
      # read, as the live scan does not read it.
      def facts(reader)
        snapshot = reader.snapshot
        groups = groups(reader)
        pipes = snapshot.entries.filter_map do |entry|
          next unless entry.kind == "edge" && groups.key?(entry.path[0...-1])

          record = entry.record(Assignment::STORE.dictionary)
          [entry, record] if record
        end
        reached = pipes.map { |entry, _record| entry.path.last }.tally
        storage = snapshot.entries.select { |entry| entry.kind == "component_instance" }
                          .to_h { |entry| [entry.path, true] }
        user_data = {}
        facts = pipes.map do |entry, record|
          readable!(record, Assignment::RECORD_KIND, "pipe")
          read = reader.entity_record(record, :fields => PIPE_FIELDS, :target_kind => PIPE_KIND, :user_data => true,
                                              :path => entry.path)
          user_data[entry.path] = read.fetch("user_data", {})
          geometry = entry.geometry
          role = record.fetch("role")
          Runs::Fact.new(:path => entry.path, :group => groups.fetch(entry.path[0...-1]),
                         :record_id => record.fetch("id"), :pipe_type_id => record.fetch("pipe_type_id"),
                         :role => role, :values => record.slice(*Assignment::ROLE_VALUES.fetch(role).keys),
                         :points_m => geometry.points_m, :vertex_ids => geometry.vertex_ids,
                         :shared => reached.fetch(entry.path.last) > 1 ||
                                    (1...entry.path.length).any? { |length| storage.key?(entry.path[0, length]) })
        end
        [facts, user_data]
      end

      # Each Piping group occurrence by path, detached as the live scan detaches it. This section is the source of a
      # claim another contributor makes on a Piping group or a pipe, so each read passes its occurrence path and the
      # claimed payload is captured for its claimant.
      def groups(reader)
        zone_paths = reader.section(ZONES).map { |row| row.fetch("zone_path") }
        reader.snapshot.records(Group::STORE.dictionary, :kind => "group").to_h do |entry, record|
          readable!(record, Group::RECORD_KIND, "Piping group")
          reader.entity_record(record, :fields => %w[hot_water_system_id], :target_kind => GROUP_KIND,
                                       :path => entry.path)
          [entry.path, { "group_id" => record.fetch("id"), "group_path" => entry.path, "name" => entry.native_name,
                         "hot_water_system_id" => record["hot_water_system_id"],
                         "in_zone" => zone_paths.any? { |path| inside?(path, entry.path) } }]
        end
      end

      def readable!(record, kind, noun)
        problem = kind.problems(record).first
        return unless problem

        raise PhComposer::Export::Blocked.new("record.unreadable", "A #{noun} record cannot be read: #{problem}.")
      end

      def inside?(parent, path)
        path.length > parent.length && path[0, parent.length] == parent
      end

      # The export's findings over the live Model, each with the code and object the export notes and the pipes it
      # locates; each pipe or Piping group record that cannot be read, blocking; and each metadata problem the export
      # refuses. A read that refuses answers one blocking row, as the export would stop on the same cause.
      def preflight(request)
        walked = Scan.walk(request.model)
        groups = walked.first
        facts, unreadable = Scan.call(request, :walked => walked)
        findings = unreadable_findings(unreadable, groups)
        findings = run_findings(request, facts) + findings unless facts.empty?
        rows = findings.map { |finding| preflight_row(finding) }
        { "findings" => rows + metadata_findings(request, groups, :types => !facts.empty?), "repairs" => [] }
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

      # The scan's unreadable rows as blocking findings. A pipe is read only inside a readable Piping group, so a row
      # whose parent is one is a pipe, which runs.locate selects; any other is a Piping group.
      def unreadable_findings(unreadable, groups)
        group_paths = groups.map(&:path)
        unreadable.map do |row|
          path = row.fetch("path")
          pipe = group_paths.include?(path[0...-1])
          { "code" => row.fetch("code"), "object_id" => nil, "blocks_export" => true,
            "message" => "A #{pipe ? 'pipe' : 'Piping group'} record cannot be read: #{row.fetch('message')}",
            "locate" => pipe ? { "edge_paths" => [path] } : nil }
        end
      end

      def preflight_row(finding)
        row = { "code" => finding.fetch("code"), "section" => SECTION, "object_id" => finding.fetch("object_id"),
                "message" => finding.fetch("message"), "blocks_export" => finding.fetch("blocks_export") }
        if (locate = finding["locate"])
          row.merge("locate" => { "name" => ScheduleRegistration::LOCATE, "params" => locate })
        elsif finding.fetch("code") == Codes::SYSTEM_UNEXPORTED
          row.merge("locate" => Mechanical::Locate.row_locate(finding.fetch("object_id"), {}))
        else
          row
        end
      end

      # The metadata problems extraction refuses, read as `records` and `facts` read them: each Pipe Type and each
      # Piping group, whose user_data are left out, and each pipe, whose user_data ride. Pipe Types only when there
      # are pipes, as `records` reads them.
      def metadata_findings(request, groups, types:)
        check = PhComposer::Export::MetadataCheck
        pipes = groups.flat_map(&:edges).uniq.filter_map { |edge| Group.read(edge, Assignment::STORE).first }
        (types ? check.findings(request, check.definitions(request, PIPE_TYPE_KIND), :section => SECTION) : []) +
          check.findings(request, groups.map(&:record), :section => SECTION, :target_kind => GROUP_KIND) +
          check.findings(request, pipes, :section => SECTION, :target_kind => PIPE_KIND, :user_data => true)
      end
    end
  end
end
