# frozen_string_literal: true

module PhComposer
  module Shading
    # `shading.export_preflight`: what the Shades section will leave out and what the mark leaves as it is, read
    # live, one walk of the Model as `shading.list` reads it. Rows about the section's records are the notes it
    # writes, with the same code and object id (ExportSection.identifier of the path), so the export lists each
    # once:
    #
    # - a Shading Face that cannot become a Shade (`shading.geometry_invalid`), or two that share a path
    #   (`target.ambiguous`);
    # - a mark whose text cannot be read (`record.unreadable`), which still marks its entity;
    # - a mark's extension_data the left-out rules refuse, blocking as for every entity record.
    #
    # A marked Group or component that is a Zone or holds one, holds another feature's object, or holds a cutting
    # component such as a Window Unit, arises after assign refused it (Make Zone inside a marked Group, a paste):
    # the mark does not reach through it (context/CONTRACTS.md, "The shading mark"), so its Faces stay what they
    # are and `shading.zone_inside` names the container. Each row names its path in its message. Reads only.
    module Preflight
      SECTION = "#{FEATURE_ID}.export.shades"

      module_function

      def call(request)
        zones = Targets.zone_names(request.model)
        findings = []
        faces = Hash.new { |hash, path| hash[path] = [] }
        marks = []
        Inventory.walk(request.model.entities, [], [], Geom::Transformation.new,
                       zones) do |entity, path, containers, transform, cut|
          # The snapshot keeps a Group or component inside a cutting component, and its mark, but no Face there.
          marks << [entity, path] if Mark.marked?(entity) && !(cut && entity.is_a?(Sketchup::Face))
          next if cut

          if entity.is_a?(Sketchup::Face)
            faces[path] << [entity, transform] if Inventory.shading_face?(entity, containers, cut)
            next
          end
          next unless Mark.marked?(entity)

          findings.concat(container_findings(entity, path, zones))
        end
        findings.concat(face_findings(faces))
        findings.concat(mark_findings(request, marks))
        { "findings" => findings, "repairs" => [] }
      end

      # A container can take both notes: a cutting component or a Zone below it does not hide the classified
      # Faces beside them, which the mark would otherwise reach.
      def container_findings(entity, path, zones)
        what = held(entity, path, zones)
        rows = what ? [zone_inside(entity, path, what)] : []
        reaches = Targets.in_zone?(path, zones) && !Targets.cutting?(entity) && !Targets.owned?(entity) &&
                  !Zones::Occurrences.zone_record?(entity)
        count = reaches ? Targets.classified_within(Targets.contents(entity).to_a) : 0
        count.positive? ? rows << classified_inside(entity, path, count) : rows
      end

      # The section's left-out notes, read live: two Shading Faces at one path, or one whose geometry cannot
      # become a Shade. A Face whose transform is singular fails the whole export's snapshot, so it blocks.
      def face_findings(faces)
        faces.flat_map do |path, occurrences|
          next [row("target.ambiguous", path, ExportSection.ambiguous(path))] if occurrences.length > 1

          face, transform = occurrences.first
          problem = ExportSection.geometry_problem(path, FaceCapture.call(face, transform))
          problem ? [row(problem.first, path, problem.last)] : []
        rescue CodedError => error
          raise unless error.code == "geometry.invalid"

          [row(error.code, path, "The Shading Face at path #{path.inspect}: #{error.message}", :blocks => true)]
        end
      end

      # Each mark the export reads, by occurrence: unreadable text as a note, and the metadata rules on a readable
      # one's record, as the section's entity record reads it.
      def mark_findings(request, marks)
        records = []
        rows = marks.filter_map do |entity, path|
          record, whole = ExportSection.parse(entity.get_attribute(Mark::STORE.dictionary, Mark::STORE.key))
          records << record.merge("id" => ExportSection.identifier(path)) if record
          row("record.unreadable", path, ExportSection.unreadable(path)) unless whole
        end
        rows + Export::MetadataCheck.findings(request, records, :section => SECTION)
      end

      def row(code, path, message, blocks: false)
        { "code" => code, "section" => SECTION, "object_id" => ExportSection.identifier(path), "message" => message,
          "blocks_export" => blocks }
      end

      # What the mark does not reach in a marked container, in words, or nil when it reaches everything.
      def held(entity, path, zones)
        contents = Targets.contents(entity).to_a
        return "a Zone" if zones.keys.any? { |zone_path| zone_path[0, path.length] == path }
        return "an object another feature owns, such as a Space" if Records::EntityStore.claimed_within?(contents)

        "a cutting component, such as a Window" if cutting_within?(contents)
      end

      def cutting_within?(entities)
        entities.any? do |entity|
          next false unless Targets.container?(entity)

          Targets.cutting?(entity) || cutting_within?(Targets.contents(entity).to_a)
        end
      end

      # A Face classified after the Group above it was marked stays envelope: classification wins.
      def classified_inside(entity, path, count)
        row("shading.classified_inside", path,
            "#{label(entity)} at path #{path.inspect} carries the shading mark and holds #{count} classified Zone " \
            "Face(s). They stay part of the Zone's envelope and are not shading; clear their classification to " \
            "make them shading.")
      end

      # The container's name in quotes, or words for none. A name that reads as a local file path is left out, as
      # the component name leaves it out, since these notes join every export's result.
      def label(entity)
        name = Targets.native_name(entity)
        return "\"#{name}\"" if Reads.named?(name) && !Diagnostics.absolute_path?(name.strip)

        "An unnamed Group or component"
      end

      def zone_inside(entity, path, what)
        row("shading.zone_inside", path,
            "#{label(entity)} at path #{path.inspect} carries the shading mark and is or holds #{what}. The mark " \
            "does not reach it, so its Faces stay as they are and are not shading.")
      end
    end
  end
end
