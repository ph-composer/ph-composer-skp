# frozen_string_literal: true

module PhComposer
  module Zones
    module ExportProjection
      SECTION = "ph_composer.zones.export.zones"
      # The Assemblies section whose definitions name the constructions this report counts.
      CONSTRUCTIONS = "ph_composer.assemblies.export.constructions"
      # The option kinds a Zone names, and what the section exports of each choice.
      CHOICE_KINDS = [Options::SEGMENTS, Options::LEVELS].freeze
      CHOICE_FIELDS = %w[name colour export_identifier].freeze

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
        Occurrences.ownership_findings(request.model, :index => index).each do |finding|
          findings << { "code" => finding.fetch("code"), "section" => SECTION,
                        "object_id" => finding.dig("reference", "zone_id"), "message" => finding.fetch("message"),
                        "blocks_export" => false }
        end
        findings.concat(metadata_findings(request, zones))
        repair = { "id" => "#{FEATURE_ID}.solve_all", "label" => "Re-solve adjacencies before export",
                   "checked" => true, "action" => "#{FEATURE_ID}.solve_adjacency",
                   "params" => { "zones" => zones.map(&:reference) } }
        { "findings" => findings, "repairs" => zones.empty? ? [] : [repair] }
      end

      # The metadata extraction refuses, read as `records` reads it: each Zone with its user_data passed
      # through, and alone every valid Building-Segment and Level choice, named by a Zone or not.
      def metadata_findings(request, zones)
        check = Export::MetadataCheck
        check.findings(request, zones.map(&:record), :section => SECTION, :user_data => true,
                                                     :target_kind => REFERENCE_KIND) +
          CHOICE_KINDS.flat_map do |kind|
            check.findings(request, check.definitions(request, kind.id), :section => SECTION)
          end
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

      # Every Zone occurrence in the snapshot as [entry, record], in snapshot order, read once per export and
      # shared by every lookup below. Every caller gets the same pairs: read them, never change them.
      def zone_occurrences(reader)
        reader.projection(:zone_occurrences) { reader.snapshot.records(ZONE_DICTIONARY, :kind => "group") }
      end

      # The Zone occurrences strictly above the snapshot path `path`, outermost first. They are indexed by
      # path once per export, so a lookup reads only the path's own prefixes and never rescans the snapshot.
      def enclosing_zones(reader, path)
        by_path = reader.projection(:zone_occurrences_by_path) do
          zone_occurrences(reader).group_by { |zone_entry, _record| zone_entry.path }
        end
        (1...path.length).flat_map { |length| by_path.fetch(path[0, length], []) }
      end

      # The one Zone occurrence holding the snapshot path `path`, as [entry, record], or nil. Two means a
      # Zone nested in a Zone, which export refuses.
      def zone_owner(reader, path)
        matches = enclosing_zones(reader, path)
        raise Export::Blocked.new("face.wrong_zone", "A Face is contained by more than one Zone.") if matches.length > 1

        matches.first
      end

      # The snapshot Zone a record id names, as [entry, record]; the first in path order for a repeated
      # one, which carries its own finding. Nil when no occurrence holds the id.
      def zone_entry(reader, zone_id)
        by_id = reader.projection(:zone_occurrence_by_id) do
          zone_occurrences(reader).group_by { |_entry, record| record["id"] }
                                  .transform_values { |pairs| pairs.min_by { |entry, _record| entry.path } }
        end
        by_id[zone_id]
      end

      # The snapshot Faces a Zone occurrence owns, at any depth, in snapshot order. One pass files each Face
      # under every Zone above it, so a Face in a Zone nested in a Zone is in both, as each Zone holds it. A Face
      # that has left a Zone's envelope is not that Zone's (`envelope_excluded?`).
      def zone_faces(reader, zone_entry)
        by_zone_path = reader.projection(:zone_faces_by_zone_path) do
          reader.snapshot.entries.each_with_object({}) do |entry, faces|
            next unless entry.kind == "face"

            enclosing_zones(reader, entry.path).map { |zone, _record| zone.path }.uniq.each do |zone_path|
              (faces[zone_path] ||= []) << entry unless envelope_excluded?(reader, entry, zone_path)
            end
          end
        end
        by_zone_path.fetch(zone_entry.path, [])
      end

      # Whether the snapshot Face `entry` has left the envelope of the Zone at `zone_path`: the live rule
      # (Occurrences.envelope_excluded?) over the snapshot entries from inside that Zone down to the Face.
      def envelope_excluded?(reader, entry, zone_path)
        by_path = reader.projection(:zones_entries_by_path) { reader.snapshot.entries.group_by(&:path) }
        inside = ((zone_path.length + 1)..entry.path.length).flat_map do |length|
          by_path.fetch(entry.path[0, length], [])
        end
        return false unless Records::EntityStore.envelope_excluded_entries?(inside)

        !Faces::FACE_STORE.carried_by?(entry.dictionaries) || Records::EntityStore.envelope_excluded_entries?([entry])
      end

      # Whether the snapshot Face `entry` is inside a Zone and has left the envelope of the innermost one, the
      # Zone a live read places it in. A Face outside every Zone is not excluded: it has no envelope to leave.
      def outside_envelope?(reader, entry)
        zone = enclosing_zones(reader, entry.path).last
        !zone.nil? && envelope_excluded?(reader, entry, zone.first.path)
      end

      # The section's registered projection, for a contributor that places its own snapshot entries in a Zone
      # (`reader.section(SECTION)`): one row per Zone occurrence with its id, path, name and Building-Segment
      # name, as zones.containment names them live. It writes no finding; the section
      # contract validates the same records and refuses a choice it cannot export.
      def occurrences(reader)
        zone_occurrences(reader).map do |entry, record|
          record = Names.project(record, entry.native_name)
          segment = if record.fetch("schema_version") == 2
                      option_choices(reader).fetch(Options::SEGMENTS.id)[record["building_segment_id"]]&.fetch("name")
                    else
                      record["building_segment"]
                    end
          { "zone_id" => record.fetch("id"), "zone_path" => entry.path, "name" => record.fetch("name"),
            "building_segment" => segment }
        end
      end

      # The Model's Building-Segment and Level options by kind id, read once per export.
      def option_choices(reader)
        reader.projection(:zone_option_definitions) do
          CHOICE_KINDS.to_h do |kind|
            dictionary = reader.snapshot.model_dictionaries.fetch(kind.store.dictionary, {})
            [kind.id, dictionary.to_h { |id, text| [id, JSON.parse(text)] }]
          end
        end
      end

      # Every valid Building-Segment and Level choice as the section exports it, by kind id and id. Each passes
      # the metadata boundary once, whether a Zone names it or not, so an unused option's map is reported as
      # omitted as a used one's is. An invalid choice is left out, and refuses only when a Zone names it.
      def exported_choices(reader)
        choices = option_choices(reader)
        CHOICE_KINDS.to_h do |kind|
          valid = choices.fetch(kind.id).sort.select { |_id, record| kind.problems(record).empty? }
          [kind.id, valid.to_h { |id, record| [id, reader.entity_record(record, :fields => CHOICE_FIELDS)] }]
        end
      end

      def export_choice(choices, kind, id)
        choices.fetch(kind.id).fetch(id) do
          raise Export::Blocked.new("reference.invalid", "Choose a valid #{kind.label} before export.")
        end
      end

      def records(reader)
        choices = exported_choices(reader)
        zone_occurrences(reader).map do |entry, record|
          record = Names.project(record, entry.native_name)
          Schema.validate!(record)
          owned = zone_faces(reader, entry)
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
            segment = export_choice(choices, Options::SEGMENTS, record.fetch("building_segment_id"))
            level = record["level_id"] && export_choice(choices, Options::LEVELS, record.fetch("level_id"))
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
