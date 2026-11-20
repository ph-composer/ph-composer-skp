# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      module ExportProjection
        SECTION = "ph_composer.zones.faces.export.faces"
        # The preflight code for each state a Face's reference can be in other than resolved or current.
        ADJACENCY_CODES = { "stale" => "adjacency.stale", "unresolved" => "adjacency.unresolved",
                            "invalid" => "adjacency.invalid" }.freeze
        CONSTRUCTION_CODES = { "dangling" => "construction.dangling", "invalid" => "construction.invalid" }.freeze
        UNRESOLVED_ASSEMBLY = { "dangling" => "This Face's Assembly is no longer in the Model.",
                                "invalid" => "This Face's Assembly cannot be read." }.freeze
        ATTACHED_ZONE_CODES = { "absent" => "attached_zone.absent", "dangling" => "attached_zone.dangling",
                                "invalid" => "attached_zone.invalid", "unavailable" => "attached_zone.unavailable" }
                              .freeze
        # One preflight finding before it is placed on its Face: `blocking` says whether it blocks export.
        Issue = Struct.new(:code, :message, :blocking, keyword_init: true)
        # The Face record fields the export section carries.
        EXPORTED_FIELDS = %w[face_type boundary_condition assembly_id assembly_reversed adjacency].freeze

        module_function

        # The Faces section's registered projection: detached native occurrences for contributors
        # needing host context, including unclassified Faces. Classification validity remains the
        # consuming feature's export policy. `left_out` is true for a Face of a Zone in no Building Segment,
        # which the section leaves out, so a contributor leaves out what it hangs on that Face. A contributor
        # reads it as `reader.section(SECTION)`.
        def contexts(reader)
          zone_faces(reader).map do |entry|
            stored = entry.record(FACE_DICTIONARY)
            owner = Zones::ExportProjection.zone_owner(reader, entry.path)
            left_out = !owner.nil? && !Zones::Schema.exported?(owner[1])
            { "path" => entry.path, "record" => context_record(reader, stored, left_out),
              "zone_id" => owner && owner[1]["id"], "left_out" => left_out, "geometry" => entry.geometry }
          end
        end

        # A valid Face record as the projection carries it, or nil. A left-out Face's metadata never leaves, so
        # it is not read through the metadata boundary, and nothing about it can block the export.
        def context_record(reader, stored, left_out)
          return nil unless stored && Schema.problems(stored).empty?
          return { "id" => stored.fetch("id") }.merge(stored.slice(*EXPORTED_FIELDS)) if left_out

          reader.entity_record(stored, :fields => EXPORTED_FIELDS, :target_kind => REFERENCE_KIND, :user_data => true)
        end

        def install(feature)
          feature.query("#{PREFIX}.export_preflight", :description => "Face classification and Assembly checks.",
                                                      :refuses => Refuses::READ,
                                                      :params => Shapes::NONE, :result => Export::PREFLIGHT_RESULT,
                                                      :examples => [{}]) { |request| preflight(request) }
          feature.export_contributor(SECTION,
                                     :section_version => 2,
                                     :preflight => "#{PREFIX}.export_preflight", :projection => method(:contexts),
                                     :result => { "surface_omissions" => [
                                       Export::Privacy.fields(%w[face_id zone_id code reason area_m2])
                                     ] }, :report => method(:omission_report)) { |reader| records(reader) }
        end

        def omission_report(result, display_units)
          omissions = result.fetch("surface_omissions", [])
          return [] if omissions.empty?

          rows = omissions.map do |row|
            area = Units.to_display(row.fetch("area_m2"), :quantity => "area", :system => display_units)
            [row.fetch("face_id"), row.fetch("zone_id"), format("%.2f", area), row.fetch("reason")]
          end
          heading = "Area (#{Units.label(:quantity => 'area', :system => display_units)})"
          table = Export::ReportHtml.table(["Face", "Zone", heading, "Reason"], rows)
          [Export::ReportHtml.section("Faces omitted", table)]
        end

        def preflight(request)
          index = Zones::Index.new(request.model)
          # A Zone in no Building Segment is left out with its Faces, so none of them is checked.
          exported = Zones::Occurrences.zones(request.model, :index => index).select do |zone|
            Zones::Schema.exported?(zone.record)
          end
          findings = exported.flat_map do |zone|
            Zones::Occurrences.faces(zone, :index => index).flat_map do |occurrence|
              face_findings(request, zone, occurrence, index)
            end
          end
          { "findings" => findings, "repairs" => [] }
        end

        def face_findings(request, zone, occurrence, index)
          record = Zones::Occurrences.face_record(occurrence.entity)
          issues = if record.nil?
                     [issue("face.unclassified", "Zone #{zone.record.fetch('name')} has an unclassified Face.", true)]
                   elsif !Schema.problems(record).empty?
                     [issue("face.invalid", "Face assignment is invalid: #{Schema.problems(record).first}.", true)]
                   else
                     assignment_issues(request, occurrence, record, index) + metadata_issues(request, record)
                   end
          issues.map do |found|
            { "code" => found.code, "section" => SECTION, "object_id" => record && record["id"],
              "message" => found.message, "blocks_export" => found.blocking, "locate" => {
                "name" => "#{PREFIX}.locate", "params" => {
                  "faces" => [occurrence.reference.merge("entity_id" => record && record["id"])]
                }
              } }
          end
        end

        # The metadata extraction refuses on this Face's assignment, read as the section reads it.
        def metadata_issues(request, record)
          Export::MetadataCheck.findings(request, [record], :section => SECTION, :user_data => true,
                                                            :target_kind => REFERENCE_KIND).map do |row|
            issue(row.fetch("code"), row.fetch("message"), true)
          end
        end

        def issue(code, message, blocking)
          Issue.new(:code => code, :message => message, :blocking => blocking)
        end

        def assignment_issues(request, occurrence, record, index)
          issues = []
          issues << issue("face.type_missing", "Choose a Face type before exporting.", true) unless record["face_type"]
          unless record["boundary_condition"]
            issues << issue("face.boundary_unassigned", "Face has no boundary condition and will be omitted.", false)
          end
          state = Zones::Adjacency.state(request.model, occurrence, record, :index => index)
          if state && state != "current"
            issues << issue(ADJACENCY_CODES.fetch(state), "Surface adjacency is #{state}; this Face will be omitted.",
                            false)
          end
          issues.concat(attached_zone_issues(request, record)) if record["boundary_condition"] == "AttachedZone"
          issues.concat(partner_issues(request, record, index)) if state == "current"
          return issues unless record["boundary_condition"] && (!state || state == "current")

          issues.concat(construction_issues(request, occurrence, record, index))
          issues.concat(AssemblyAssignment.findings(request, occurrence, record, index).map do |finding|
            # honeybee rejects a Surface pair whose sides do not mirror one construction, so it blocks.
            issue(finding.fetch("code"), finding.fetch("message"), BLOCKING_FINDINGS.include?(finding.fetch("code")))
          end)
          issues
        end

        BLOCKING_FINDINGS = %w[face.assembly_pair_mismatch].freeze

        def construction_issues(request, occurrence, record, index)
          id = record["assembly_id"]
          # The finding's object_id carries the Face; its sentence is for a reader and names no record id, so
          # every Face with one cause reads the same.
          unless id
            return [] if interior_within_segment?(request, occurrence, record, index)

            return [issue("construction.missing", missing_message(record), true)]
          end

          state = AssemblyAssignment.state(request, record)
          if state != "resolved"
            message = UNRESOLVED_ASSEMBLY.fetch(state, "This Face's Assembly is #{state}.")
            return [issue(CONSTRUCTION_CODES.fetch(state), message, true)]
          end
          assembly = AssemblyAssignment.catalog(request).fetch(:records).fetch(id)
          return [] if assembly.fetch("export_ready")

          reason = assembly.fetch("export_blockers").first.fetch("message")
          name = assembly.fetch("values")["name"]
          [issue("construction.incomplete", "This Face's Assembly #{name} is not finished: #{reason}", true)]
        end

        # An interior Face within one Building-Segment exports with no construction; PHX drops it from
        # the PH model and honeybee applies its default interior construction. Across Building-Segments the
        # Face is part of a segment's envelope, so it needs an Assembly.
        def interior_within_segment?(request, occurrence, record, index)
          return false unless record["boundary_condition"] == "Surface"

          other = Zones::Occurrences.resolve_face(request.model, record.fetch("adjacency").fetch("counterpart"),
                                                  :index => index)
          mine = segment(occurrence.zone.record)
          !mine.nil? && mine == segment(other.zone.record)
        rescue CodedError
          false
        end

        # A Zone's Building-Segment as the export groups it: the managed choice, or nil for a managed Zone in
        # no Building Segment, which shares a Segment with no other Zone; else its name.
        def segment(zone_record)
          return ["legacy", zone_record["building_segment"]] unless Zones::Schema.managed?(zone_record)

          id = zone_record["building_segment_id"]
          id && ["managed", id]
        end

        def missing_message(record)
          return "This Face has no Assembly." unless record["boundary_condition"] == "Surface"

          "This interior Face joins two Building-Segments, so it needs an Assembly."
        end

        # A current Surface pair whose other side is in a Zone in no Building Segment: export leaves that Zone out,
        # so the pair has no other side and refuses.
        def partner_issues(request, record, index)
          other = Zones::Occurrences.resolve_face(request.model, record.fetch("adjacency").fetch("counterpart"),
                                                  :index => index)
          return [] if Zones::Schema.exported?(other.zone.record)

          [issue("face.partner_left_out", partner_message(record, other.zone.record), true)]
        rescue CodedError
          []
        end

        def attached_zone_issues(request, record)
          id = record["attached_zone_id"]
          state = id.to_s.empty? ? "absent" : attached_record_state(request, id)
          return [] if state == "resolved"

          [issue(ATTACHED_ZONE_CODES.fetch(state), "The Face's Attached zone reference is #{state}.", true)]
        end

        def attached_record_state(request, id)
          kind = request.engine.kind(AttachedZone::KIND_ID)
          stored = kind.store.read(request.model, id)
          return "dangling" unless stored
          return "invalid" unless stored.is_a?(Hash)
          return "unavailable" unless stored["schema_version"] == kind.schema_version
          return "invalid" unless kind.problems(stored).empty?

          required = stored.fetch("extension_data", {}).select do |_namespace, envelope|
            envelope.is_a?(Hash) && envelope["export_relevance"] != "local_only"
          end
          return "unavailable" unless required.all? do |namespace, envelope|
            Records::Extension.status(envelope, request.registry.catalog.extension(namespace)) == "understood"
          end

          "resolved"
        rescue JSON::ParserError, CodedError
          "invalid"
        end

        # One record per classified Face of an exported Zone. A Face of a Zone in no Building Segment leaves with
        # its Zone, and so is not written; an AttachedZone Face carries its Attached zone's values.
        def records(reader)
          attached = attached_zones(reader)
          zone_faces(reader).filter_map do |entry|
            record = entry.record(FACE_DICTIONARY)
            next unless record

            owner = Zones::ExportProjection.zone_owner(reader, entry.path)
            next if owner && !Zones::Schema.exported?(owner.fetch(1))

            Schema.validate!(record)
            geometry = entry.geometry
            stamp = entry.record(Zones::STAMP_DICTIONARY)
            unless stamp && stamp["zone_id"].is_a?(String) && owner && owner.fetch(1)["id"] == stamp["zone_id"]
              raise Export::Blocked.new("face.wrong_zone", "Face #{record.fetch('id')} has no owning Zone stamp.")
            end

            exported = reader.entity_record(
              record, :fields => EXPORTED_FIELDS,
                      :target_kind => REFERENCE_KIND, :path => entry.path, :user_data => true
            ).merge(
              "zone_id" => stamp.fetch("zone_id"), "geometry" => geometry.to_h
            )
            exported["attached_zone"] =
              attached_zone(attached, record) if record["boundary_condition"] == "AttachedZone"
            omission = omission_reason(reader, entry, record)
            if omission
              exported["omission"] = { "code" => omission.fetch(0), "reason" => omission.fetch(1),
                                       "area_m2" => geometry.area_m2, "zone_id" => stamp.fetch("zone_id") }
            end
            exported
          end.sort_by { |record| record.fetch("id") }
        end

        # Every snapshot Face but those that have left their Zone's envelope: a Face outside every Zone stays, so
        # a contributor reading the projection still finds it.
        def zone_faces(reader)
          reader.projection(:zone_envelope_faces) do
            reader.snapshot.entries.select do |entry|
              entry.kind == "face" && !Zones::ExportProjection.outside_envelope?(reader, entry)
            end
          end
        end

        # Every readable Attached zone in the snapshot, by id. An Attached zone leaves no object of its own: each
        # AttachedZone Face carries its values (`attached_zone`), so each one with a map gets a finding that the
        # map stayed in the Model. Whether its envelopes let export go ahead is the preflight's
        # (`attached_record_state`), and a record that cannot be read is that preflight's finding when a Face
        # names it.
        def attached_zones(reader)
          kind = AttachedZone::RECORD_KIND
          reader.snapshot.model_dictionaries.fetch(kind.store.dictionary,
                                                   {}).sort.each_with_object({}) do |(id, text), found|
            record = text.is_a?(String) ? JSON.parse(text) : nil
            next unless record.is_a?(Hash) && kind.problems(record).empty?

            reader.entity_record(record.slice("id", "user_data"), :fields => [])
            found[id] = record
          rescue JSON::ParserError
            next
          end
        end

        # The values an AttachedZone Face exports for its Attached zone: the record's id, name and factor. Its
        # kind stays in the Model: honeybee-ph's Grasshopper component writes every attached zone as an unheated
        # space, and PHX reads it as one.
        def attached_zone(attached, record)
          found = attached[record["attached_zone_id"]]
          unless found
            raise Export::Blocked.new("attached_zone.dangling",
                                      "Face #{record.fetch('id')} names an Attached zone that cannot be exported.")
          end

          found.slice("id", "name", "temperature_reduction_factor")
        end

        def omission_reason(reader, entry, record)
          unless record["boundary_condition"]
            return ["face.boundary_unassigned", "Face has no assigned boundary condition."]
          end
          return nil unless record["boundary_condition"] == "Surface"

          endpoint = record.dig("adjacency", "counterpart")
          path = Array(endpoint&.fetch("zone_path", nil)) + Array(endpoint&.fetch("entity_path", nil))
          counterpart = reader.snapshot.entry_at(path, :kind => "face")
          other = counterpart&.record(FACE_DICTIONARY)
          # A counterpart that has left its Zone's envelope is not exported, so the pair has no other side.
          unless counterpart && other && !Zones::ExportProjection.outside_envelope?(reader, counterpart)
            return ["adjacency.unresolved", "Face has no reciprocal Surface endpoint."]
          end
          unless Zones::Adjacency.snapshot_pair_current?(entry, record, counterpart, other)
            return ["adjacency.stale", "Face has no current reciprocal Surface endpoint."]
          end

          # A current pair whose other side leaves with its Zone has no other side, as the preflight says.
          partner = Zones::ExportProjection.zone_owner(reader, counterpart.path)
          if partner && !Zones::Schema.exported?(partner.fetch(1))
            raise Export::Blocked.new("face.partner_left_out", partner_message(record, partner.fetch(1)))
          end

          nil
        end

        # The refusal for a Surface Face whose other side is in a Zone export leaves out, and its repair.
        def partner_message(record, partner)
          "Face #{record.fetch('id')} is one side of a Surface pair with Zone #{partner.fetch('name')}, which is in " \
            "no Building Segment and left out of export. Make #{partner.fetch('name')} the Attached zone for the " \
            "Faces it shares, or put it in a Building Segment."
        end
        private_class_method :face_findings, :issue, :assignment_issues, :attached_zone_issues, :attached_record_state,
                             :omission_reason, :construction_issues, :zone_faces, :attached_zones, :attached_zone,
                             :partner_message, :context_record, :partner_issues
      end
    end
  end
end
