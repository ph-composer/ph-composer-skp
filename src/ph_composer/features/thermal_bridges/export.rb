# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # The thermal-bridge export section (context/CONTRACTS.md, "Translation sections and artifacts"): one record
    # per run, read from the export snapshot and never the live Model, for the Python section that adds each
    # honeybee-ph PhThermalBridge to its Zone's Building-Segment. The runs come from the same Runs functions
    # the schedule uses, over facts the snapshot gives instead of the live walk: the assigned Edge entries,
    # the Zones section's Zone occurrences and the Faces section's classification. The Apertures section's
    # Window outlines add the window-perimeter finding.
    #
    # A missing type or psi-value refuses the section: no canonical pair is written. Every other finding is a
    # non-blocking note, so it reaches the report, and an Edge no Zone holds is left out with its note. The
    # preflight reads the same findings live, with the Edges each one locates.
    module ExportProjection
      SECTION = "#{FEATURE_ID}.export.thermal_bridges"
      PREFLIGHT = "#{FEATURE_ID}.export_preflight"
      ZONES = "ph_composer.zones.export.zones"
      FACES = "ph_composer.zones.faces.export.faces"
      APERTURES = "ph_composer.windows.export.apertures"
      OUTLINES = "ph_composer.windows.units.outlines"
      RUN_FIELDS = %w[identifier display_name zone_id type_id type_name group psi_w_mk quantity length_m
                      heat_loss_w_k].freeze
      RESULT = { "thermal_bridge_runs" => [Export::Privacy.fields(RUN_FIELDS)] }.freeze
      # METr's words for honeybee-ph's group strings (context/UBIQUITOUS_LANGUAGE.md, "Thermal bridge group").
      GROUP_WORDS = { "15-Ambient" => "Ambient", "16-Perimeter" => "Perimeter",
                      "17-FS/BC" => "Basement floor" }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :preflight => PREFLIGHT,
                                            :requires => [ZONES, FACES, APERTURES],
                                            :user_data_keys => ["ph_composer.thermal_bridge_type_id"],
                                            :result => RESULT,
                                            :report => method(:report)) { |reader| records(reader) }
        feature.query(PREFLIGHT, :description => "Thermal-bridge export checks: each run's and assigned Edge's " \
                                                 "findings, with the Edges each one locates.",
                                 :refuses => ScheduleRegistration::READ, :params => Shapes::NONE,
                                 :result => Export::PREFLIGHT_RESULT, :examples => [{}]) do |request|
          preflight(request)
        end
      end

      # Every finding the schedule gives, the window-perimeter warning included, and each unreadable assignment
      # as a blocking row, each locating its Edges with runs.locate.
      def preflight(request)
        facts, unreadable = Scan.call(request)
        outlines, skipped = facts.empty? ? [[], nil] : outlines(request)
        schedule = Runs::Schedule.call(facts, :types => Scan.types(request.engine), :outlines => outlines)
        findings = skipped ? [skipped] : []
        findings += schedule.fetch("runs").flat_map do |run|
          run.fetch("findings").map do |finding|
            preflight_row(finding, run.fetch("identifier"), "#{run.fetch('display_name')}: ")
          end
        end
        ids = facts.to_h { |fact| [fact.path, fact.record_id] }
        findings += schedule.fetch("edge_findings").map do |finding|
          preflight_row(finding, ids[finding.fetch("path")])
        end
        findings += unreadable.map do |row|
          preflight_row({ "code" => row.fetch("code"), "blocks_export" => true,
                          "message" => "An assigned Edge's record cannot be read: #{row.fetch('message')}",
                          "locate" => { "edge_paths" => [row.fetch("path")] } }, nil)
        end
        { "findings" => findings, "repairs" => [] }
      rescue CodedError => error
        { "findings" => [{ "code" => error.code, "section" => SECTION, "object_id" => nil,
                           "message" => error.message, "blocks_export" => true }], "repairs" => [] }
      end

      def preflight_row(finding, object_id, prefix = "")
        { "code" => finding.fetch("code"), "section" => SECTION, "object_id" => object_id,
          "message" => prefix + finding.fetch("message"), "blocks_export" => finding.fetch("blocks_export"),
          "locate" => { "name" => ScheduleRegistration::LOCATE, "params" => finding.fetch("locate") } }
      end

      # Every placed Window's world outline, through Windows' published read, in as many pages as it takes, and
      # nil; or none and a non-blocking row saying the window-perimeter check was skipped, when Windows cannot
      # answer. Windows' own preflight reports why, so the thermal-bridge findings stand without it.
      def outlines(request)
        rows = []
        params = { "limit" => Pages::MAXIMUM_LIMIT }
        loop do
          page = request.query(OUTLINES, params)
          rows.concat(page.fetch("units").map { |row| row.fetch("outline_m") })
          break unless page["next_cursor"]

          params = params.merge("cursor" => page["next_cursor"])
        end
        [rows, nil]
      rescue CodedError => error
        [[], { "code" => error.code, "section" => SECTION, "object_id" => nil, "blocks_export" => false,
               "message" => "The window-perimeter check was skipped: #{error.message}" }]
      end

      def records(reader)
        types = reader.records(TYPE_KIND).to_h { |row| [row.fetch("id"), row] }
        facts = facts(reader)
        outlines = reader.section(APERTURES).map { |row| row.fetch("outline_m") }
        schedule = Runs::Schedule.call(facts, :types => types, :outlines => outlines)
        blocking = schedule.fetch("runs").flat_map { |run| run.fetch("findings") }.find { |row| row["blocks_export"] }
        raise Export::Blocked.new(blocking.fetch("code"), blocking.fetch("message")) if blocking

        ids = facts.to_h { |fact| [fact.path, fact.record_id] }
        schedule.fetch("edge_findings").each do |finding|
          reader.note(finding.fetch("code"), ids[finding.fetch("path")], finding.fetch("message"))
        end
        schedule.fetch("runs").map do |run|
          run.fetch("findings").each do |finding|
            reader.note(finding.fetch("code"), run.fetch("identifier"),
                        "#{run.fetch('display_name')}: #{finding.fetch('message')}")
          end
          { "id" => run.fetch("identifier"), "zone_id" => run.dig("zone", "zone_id") }
            .merge(run.slice(*%w[display_name type_id type_name group psi_w_mk quantity closed points_m]))
        end.sort_by { |record| record.fetch("id") }
      end

      # Each assigned Edge occurrence in the snapshot as a Runs::Fact: its Zone from the Zones section, the
      # values of its Zone Faces from the Faces section, and whether a ComponentInstance holds it. The snapshot
      # keeps no Group's definition, so a copied Group whose storage two Groups still share reads as unshared
      # here, where the live schedule says shared. Its record passes the metadata boundary like any entity
      # record; its user_data stays in the Model, since a run joins many Edges and no one Edge's data stands
      # for it.
      def facts(reader)
        snapshot = reader.snapshot
        zones = reader.section(ZONES).to_h { |row| [row.fetch("zone_path"), row] }
        faces = reader.section(FACES).to_h { |row| [row.fetch("path"), row] }
        owners = Zones::ExportProjection::Owners.new(snapshot)
        storage = snapshot.entries.select { |entry| entry.kind == "component_instance" }
                          .to_h { |entry| [entry.path, true] }
        snapshot.records(Assignment::STORE.dictionary, :kind => "edge").map do |entry, record|
          begin
            Assignment.validate!(record)
          rescue CodedError => error
            raise Export::Blocked.new(error.code, error.message)
          end
          reader.entity_record(record, :fields => %w[thermal_bridge_type_id quantity], :target_kind => EDGE_KIND,
                                       :path => entry.path)
          zone_path, reason = owners.owner(entry.path)
          geometry = entry.geometry
          Runs::Fact.new(:path => entry.path, :zone => zone_path && zones.fetch(zone_path), :reason => reason,
                         :record_id => record.fetch("id"), :type_id => record.fetch("thermal_bridge_type_id"),
                         :quantity => record.fetch("quantity"), :points_m => geometry.points_m,
                         :vertex_ids => geometry.vertex_ids,
                         :faces => face_values(faces, entry.path[0...-1], geometry.face_ids),
                         :shared => (1...entry.path.length).any? { |length| storage.key?(entry.path[0, length]) })
        end
      end

      # As ph_composer.zones.faces.host_context reads them live: a Zone Face's recorded values, empty when it is
      # unclassified, and nothing for a Face that is not a Zone Face.
      def face_values(faces, container, face_ids)
        face_ids.filter_map do |id|
          row = faces[container + [id]]
          next unless row

          row["record"] ? row["record"].slice("face_type", "boundary_condition") : {}
        end
      end

      # The runs exported, by type and by group, from the run's result rows: length and psi times length times
      # quantity.
      def report(result, display_units)
        rows = result.fetch("thermal_bridge_runs", [])
        return [] if rows.empty?

        length = PhComposer::Units.label(:quantity => "length", :system => display_units)
        loss = PhComposer::Units.label(:quantity => "heat_loss_rate", :system => display_units)
        by_type = rows.group_by { |row| row.fetch("type_id") }.map do |_id, typed|
          [typed.first.fetch("type_name"), GROUP_WORDS.fetch(typed.first.fetch("group"), typed.first.fetch("group")),
           typed.length, figure(typed.sum { |row| row.fetch("length_m") }, "length", display_units),
           figure(typed.sum { |row| row.fetch("heat_loss_w_k") }, "heat_loss_rate", display_units)]
        end.sort_by(&:first)
        by_group = GROUP_WORDS.map do |group, words|
          [words, figure(rows.select { |row| row.fetch("group") == group }.sum { |row| row.fetch("heat_loss_w_k") },
                         "heat_loss_rate", display_units)]
        end
        html = Export::ReportHtml.table(["Type", "Group", "Runs", "Length (#{length})", "Heat loss (#{loss})"],
                                        by_type) +
               Export::ReportHtml.table(["Group", "Heat loss (#{loss})"], by_group)
        [Export::ReportHtml.section("Thermal bridges", html)]
      end

      def figure(value, quantity, display_units)
        Kernel.format("%.3f", PhComposer::Units.to_display(value, :quantity => quantity, :system => display_units))
      end
    end
  end
end
