# frozen_string_literal: true

module PhComposer
  module Zones
    module ExportProjection
      SECTION = "ph_composer.zones.export.zones"
      # The Assemblies section whose definitions name the constructions this report counts.
      CONSTRUCTIONS = "ph_composer.assemblies.export.constructions"

      module_function

      def install(feature)
        feature.export_contributor(
          SECTION, :section_version => 2,
                   :preflight => "#{FEATURE_ID}.export_preflight",
                   # What the Zone translation writes on each Room (python/ph_composer_translation/model_sections.py).
                   :user_data_keys => %w[ph_composer.level ph_composer.building_segment],
                   :result => {
                     "construction_usage" => [Export::Privacy.fields(%w[assembly_id face_count gross_area_m2])]
                   },
                   :requires => [CONSTRUCTIONS], :report => method(:report), :projection => method(:occurrences)
        ) { |reader| records(reader) }
        feature.query("#{FEATURE_ID}.export_preflight", :description => "All-Zone export checks and adjacency repair.",
                                                        :refuses => Options::Registration::REFUSALS,
                                                        :params => Shapes::NONE, :result => Export::PREFLIGHT_RESULT,
                                                        :examples => [{}]) { |request| preflight(request) }
      end

      def preflight(request)
        index = Index.new(request.model)
        zones = Occurrences.zones(request.model, :index => index)
        managed = !Options.settings(request.engine).nil?
        findings = []
        if zones.empty?
          findings << { "code" => "zone.none", "section" => SECTION, "object_id" => nil,
                        "message" => "Make at least one Zone before exporting.", "blocks_export" => true }
        end
        zones.each do |zone|
          begin
            Schema.validate!(zone.record)
            if (managed || zone.record.fetch("schema_version") == 2) &&
               Options::Adoption.needs_adoption?(request.engine, zone.record)
              Options.refuse("zone.options_adoption_required", "Adopt legacy or copied choices before export")
            end
            Options.resolve(request.engine, zone.record) if zone.record.fetch("schema_version") == 2
            Occurrences.resolve_zone(request.model, zone.reference, :mutable => true, :index => index)
          rescue CodedError => error
            findings << { "code" => error.code, "section" => SECTION, "object_id" => zone.record["id"],
                          "message" => error.message, "blocks_export" => true }
          end
        end
        Occurrences.component_findings(request.model).each do |finding|
          findings << { "code" => finding.fetch("code"), "section" => SECTION,
                        "object_id" => finding.dig("reference", "zone_id"), "message" => finding.fetch("message"),
                        "blocks_export" => true }
        end
        repair = { "id" => "#{FEATURE_ID}.solve_all", "label" => "Solve stale adjacencies before export",
                   "checked" => true, "action" => "#{FEATURE_ID}.solve_adjacency",
                   "params" => { "zones" => zones.map(&:reference) } }
        { "findings" => findings, "repairs" => zones.empty? ? [] : [repair] }
      end

      # Gross area per Assembly over the emitted Faces. Window net areas are the Windows report's.
      def report(result, display_units)
        usage = result.fetch("construction_usage", [])
        return [] if usage.empty?

        names = result.section(CONSTRUCTIONS).fetch("construction_definitions", []).to_h do |row|
          [row.fetch("assembly_id"), row.fetch("name")]
        end
        rows = usage.map do |row|
          area = Units.to_display(row.fetch("gross_area_m2"), :quantity => "area", :system => display_units)
          [names.fetch(row.fetch("assembly_id"), row.fetch("assembly_id")), row.fetch("face_count"),
           format("%.2f", area)]
        end
        heading = "Gross area (#{Units.label(:quantity => 'area', :system => display_units)})"
        table = Export::ReportHtml.table(["Assembly", "Faces", heading], rows)
        [Export::ReportHtml.section("Construction usage", table)]
      end

      # The one Zone occurrence containing a snapshot entry, as [entry, record], or nil. Two means a
      # Zone nested in a Zone, which export refuses. An entry inside a nested container has no owner.
      def zone_owner(snapshot, entry)
        owner = enclosing_zone(snapshot, entry)
        owner unless owner && in_container?(snapshot, owner.first, entry)
      end

      # Whether a snapshot entry lies in a nested container of the Zone holding it: not a Zone Face,
      # so no Zones section exports it.
      def contained?(snapshot, entry)
        owner = enclosing_zone(snapshot, entry)
        !owner.nil? && in_container?(snapshot, owner.first, entry)
      end

      def enclosing_zone(snapshot, entry)
        matches = snapshot.records(ZONE_DICTIONARY, :kind => "group").select do |zone_entry, _record|
          snapshot.contains?(zone_entry, entry)
        end
        raise Export::Blocked.new("face.wrong_zone", "A Face is contained by more than one Zone.") if matches.length > 1

        matches.first
      end

      def in_container?(snapshot, zone_entry, entry)
        containers(snapshot, zone_entry).any? { |group| snapshot.contains?(group, entry) }
      end

      # The snapshot Faces a Zone occurrence owns: every Face inside it except those in a nested
      # container, the rule `Occurrences` applies to the live Model. The snapshot keeps those Faces
      # for the feature that stamped the container.
      def zone_faces(snapshot, zone_entry)
        nested = containers(snapshot, zone_entry)
        snapshot.descendants(zone_entry, :kind => "face").reject do |face|
          nested.any? { |group| snapshot.contains?(group, face) }
        end
      end

      # The Groups inside a Zone occurrence that carry a Zone stamp (context/CONTRACTS.md, "Zones geometry rules").
      def containers(snapshot, zone_entry)
        snapshot.descendants(zone_entry, :kind => "group").select do |group|
          !group.dictionaries.fetch(STAMP_DICTIONARY, {})[STAMP_STORE.key].nil?
        end
      end

      # The section's registered projection, for a contributor that places its own snapshot entries in a Zone
      # (`reader.section(SECTION)`): one row per Zone occurrence with its id, path, name and Building-Segment
      # name, as zones.containment names them live, and the paths of the containers it holds, whose contents
      # are not the Zone's (context/CONTRACTS.md, "Zones geometry rules"). It writes no finding; the section
      # contract validates the same records and refuses a choice it cannot export.
      def occurrences(reader)
        reader.snapshot.records(ZONE_DICTIONARY, :kind => "group").map do |entry, record|
          record = Names.project(record, entry.native_name)
          segment = if record.fetch("schema_version") == 2
                      option_choices(reader).fetch(Options::SEGMENTS.id)[record["building_segment_id"]]&.fetch("name")
                    else
                      record["building_segment"]
                    end
          { "zone_id" => record.fetch("id"), "zone_path" => entry.path, "name" => record.fetch("name"),
            "building_segment" => segment,
            "container_paths" => containers(reader.snapshot, entry).map(&:path) }
        end
      end

      # The Model's Building-Segment and Level options by kind id, read once per export.
      def option_choices(reader)
        reader.projection(:zone_option_definitions) do
          [Options::SEGMENTS, Options::LEVELS].to_h do |kind|
            dictionary = reader.snapshot.model_dictionaries.fetch(kind.store.dictionary, {})
            [kind.id, dictionary.to_h { |id, text| [id, JSON.parse(text)] }]
          end
        end
      end

      def export_choice(reader, choices, kind, id)
        record = choices.fetch(kind.id)[id]
        unless record && kind.problems(record).empty?
          raise Export::Blocked.new("reference.invalid", "Choose a valid #{kind.label} before export.")
        end

        reader.entity_record(record, :fields => %w[name colour export_identifier])
      end

      def records(reader)
        zones = reader.snapshot.records(ZONE_DICTIONARY, :kind => "group")
        zones.map do |entry, record|
          record = Names.project(record, entry.native_name)
          Schema.validate!(record)
          owned = zone_faces(reader.snapshot, entry)
          assigned = owned.map { |face| [face, face.record(Faces::FACE_DICTIONARY)] }
          missing = assigned.select { |_face, assignment| assignment.nil? }
          unless missing.empty?
            raise Export::Blocked.new("face.unclassified",
                                      "Zone #{record.fetch('id')} has #{missing.length} unclassified Faces.")
          end
          ids = assigned.map { |_face, assignment| assignment.fetch("id") }.sort
          exported = reader.entity_record(record, :fields => %w[name building_segment level],
                                                  :target_kind => REFERENCE_KIND, :path => entry.path,
                                                  :user_data => true)
          if record.fetch("schema_version") == 2
            choices = option_choices(reader)
            segment = export_choice(reader, choices, Options::SEGMENTS, record.fetch("building_segment_id"))
            level = record["level_id"] && export_choice(reader, choices, Options::LEVELS, record.fetch("level_id"))
            exported.merge!("building_segment_id" => segment.fetch("id"),
                            "building_segment_export_identifier" => segment.fetch("export_identifier"),
                            "building_segment" => segment.fetch("name"), "level" => level&.fetch("name"))
          end
          exported.merge("face_ids" => ids)
        end.sort_by { |record| record.fetch("id") }
      end
    end
  end
end
