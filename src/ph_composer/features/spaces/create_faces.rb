# frozen_string_literal: true

module PhComposer
  module Spaces
    # Which Faces Create Space takes, by one rule for every edit context: Faces loose in the open context,
    # whether that is the Model root, a plain Group or a Zone's own context. A Space Group never stays inside
    # a Zone: from an open Zone it is placed in the Zone's parent (W6-2). Zones' answers come through its
    # public path reads, never its internals. Reads only.
    module CreateFaces
      CONTAINMENT = "ph_composer.zones.containment"
      HOST_CONTEXT = "ph_composer.zones.faces.host_context"
      ZONES = "ph_composer.zones.all"
      # Why Create Space leaves a selected Face out, by the refusal its path met.
      LEFT_OUT = {
        "target.not_found" => ["not_found", "That Face no longer exists."],
        "target.wrong_kind" => ["not_a_face", "Only Faces become Floor Segments."],
        "target.wrong_hierarchy" => ["in_container", "The Face is inside a Group within its Zone. Create Space takes " \
                                                     "Faces loose in the Zone's own context or outside every Zone."],
        "target.shared_definition" => ["shared_storage", "The Face is in storage another copy shares."],
        "target.locked" => ["locked", "The Face or a Group above it is locked."],
        "target.changed" => ["classified", "The Face is an envelope Face with a classification."]
      }.freeze
      NOT_LOOSE = ["not_loose", "The Face is not loose in the open edit context."].freeze
      FLOOR_SEGMENT = ["floor_segment", "The Face is already a Floor Segment."].freeze
      IN_SPACE = ["in_space", "The Face is inside a Space. To add it to that Space, select it at the Space's root " \
                              "and choose Add New Volume to Space; to make a new Space, draw it outside this " \
                              "one."].freeze
      # A floor surface drawn on the Zone's walls splits them and shares their Edges, so Create Space leaves
      # it out; the way out is to draw it where it touches no other Face.
      SHARES_EDGE = "The Face shares an Edge with an unselected Face; grouping it would split that Face. Undo " \
                    "the floor surface, then draw it just below the floor or inset from the walls, touching no " \
                    "other Face."
      # The Faces of a closed solid, whatever the slope of its sides: taking its top and bottom would count the
      # floor twice, so none is taken. A vertical wall among them is left out as a wall.
      SOLID = "The Face is part of a solid. A Space is a floor surface plus a height: draw the floor surface " \
              "alone, touching no other Face, then set the height, or group the solid and use Height from solid."

      # A Face Create Space would take: its root-to-Face path and its persistent id.
      Eligible = Struct.new(:path, :face_id, keyword_init: true)

      # What `read` found. `open_zone` is the reference of the Zone whose own context is open, or nil;
      # `outside` the path a Space Group is placed in instead of that Zone, or nil when it stays where it is drawn.
      Read = Struct.new(:eligible, :left_out, :open_zone, :outside, :transform, keyword_init: true)

      module_function

      # `context` is the Groups and components from the root to the edit context the Faces are taken from: the
      # open one, or the one a candidate read names. `alone` judges each Face as if it were named by itself, which
      # is what a candidate read reports: a Face it calls eligible is then taken with any other eligible Face.
      def read(request, faces, context: Array(request.model.active_path), alone: false)
        model = request.model
        paths = faces.map { |path| Resolve.integer_path(path) }.uniq
        open_path = context.map(&:persistent_id)
        transform = open_transform(context)
        refusal = context_refusal(context)
        containment = request.query(CONTAINMENT, "paths" => paths).fetch("paths")
        records = request.query(HOST_CONTEXT, "paths" => paths).fetch("faces").to_h { |row| [row.fetch("path"), row] }
        candidates, left_out = sort(model, paths, containment, records,
                                    :open_path => open_path, :context => refusal, :transform => transform)
        eligible = if alone
                     settle_alone(model, candidates, left_out)
                   else
                     settle(Operations::EntityScope.new(open_path).resolve(model), candidates, left_out)
                   end
        zone = own_zone(containment, eligible)
        Read.new(:eligible => eligible, :left_out => left_out, :open_zone => zone,
                 :outside => zone && zone.fetch("zone_path")[0...-1], :transform => transform)
      end

      # What maps a Face loose in the open context to world coordinates.
      def open_transform(active)
        active.reduce(Geom::Transformation.new) { |carried, entity| carried * entity.transformation }
      end

      # The Zone to preselect: the open one, otherwise the one holding the outlines, otherwise none.
      def preselected_zone(request, found)
        return found.open_zone if found.open_zone
        return nil if found.eligible.empty?

        outlines = found.eligible.map do |face|
          FaceCapture.call(Occurrences.entity_at(request.model, face.path), found.transform).loops_m.first
        end
        ZoneInference.pick(outlines, request.query(ZONES).fetch("zones").filter_map { |row| candidate(request, row) })
      end

      # The refusal every Face in this open context meets, or nil: no Space inside a Space, and nothing
      # written through a lock or storage a copy shares.
      def context_refusal(active)
        active.each do |entity|
          return IN_SPACE if marked?(entity, SPACE_STORE) || marked?(entity, VOLUME_STORE)
          return LEFT_OUT.fetch("target.shared_definition") if Occurrences.shared_storage?(entity)
          return LEFT_OUT.fetch("target.locked") if entity.locked?
        end
        nil
      end

      def marked?(entity, store)
        !entity.get_attribute(store.dictionary, store.key).nil?
      end

      # Splits the paths into candidates and left-out rows, one Face at a time.
      def sort(model, paths, containment, records, open_path:, context:, transform:)
        candidates = []
        left_out = []
        paths.zip(containment).each do |path, row|
          reason = context || face_refusal(model, path, row, records[path], open_path, transform)
          if reason
            left_out << left_out_row(path, reason)
          else
            candidates << Eligible.new(:path => path, :face_id => path.last)
          end
        end
        [candidates, left_out]
      end

      def face_refusal(model, path, row, record, open_path, transform)
        return NOT_LOOSE unless path[0...-1] == open_path

        face = Occurrences.entity_at(model, path)
        return LEFT_OUT.fetch("target.not_found") unless face
        return LEFT_OUT.fetch("target.wrong_kind") unless face.is_a?(Sketchup::Face)

        zone_refusal(row, record) || floor_refusal(face, transform)
      end

      def floor_refusal(face, transform)
        return FLOOR_SEGMENT if FLOOR_SEGMENT_STORE.read(face)

        ["vertical", Eligibility::WALL] if Eligibility.wall?(face, transform)
      end

      # What the Zone holding the Face says: nothing for a Face in no Zone.
      def zone_refusal(row, record)
        return nil unless row["zone"]
        return LEFT_OUT.fetch("target.wrong_hierarchy") unless row.fetch("entity_path").length == 1
        return LEFT_OUT.fetch("target.changed") if record&.dig("reference", "entity_id")

        refusal = row["write_refusal"]
        refusal && LEFT_OUT.fetch(refusal.fetch("code")) { [refusal.fetch("code"), refusal.fetch("message")] }
      end

      # Drops the Faces of a closed solid and those sharing an Edge with a Face outside the set, recording why.
      def settle(entities, candidates, left_out)
        walls = left_out.select { |row| row["reason"] == "vertical" }.map { |row| row.fetch("path").last }
        solid = Steps.closed_shells(entities, candidates.map(&:face_id) + walls)
        in_solid, loose = candidates.partition { |face| solid.include?(face.face_id) }
        left_out.concat(in_solid.map { |face| left_out_row(face.path, ["solid", SOLID]) })
        eligible = without_edge_sharing(entities, loose)
        left_out.concat((loose - eligible).map { |face| left_out_row(face.path, ["shares_edge", SHARES_EDGE]) })
        eligible
      end

      # Each candidate named by itself: one Face is never a closed solid, and any Edge it shares is with a Face
      # outside the set, as Eligibility.alone! reads it for a new Volume.
      def settle_alone(model, candidates, left_out)
        eligible, sharing = candidates.partition do |face|
          Steps.sharing([Occurrences.entity_at(model, face.path)], [face.face_id]).empty?
        end
        left_out.concat(sharing.map { |face| left_out_row(face.path, ["shares_edge", SHARES_EDGE]) })
        eligible
      end

      # The candidates that share no Edge with a Face outside the set. Dropping a Face makes it an
      # outside neighbour of the Faces beside it, so the check repeats until nothing more drops.
      def without_edge_sharing(entities, candidates)
        kept = candidates
        loop do
          sharing_ids = Steps.sharing(entities, kept.map(&:face_id))
          return kept if sharing_ids.empty?

          kept = kept.reject { |face| sharing_ids.include?(face.face_id) }
        end
      end

      def left_out_row(path, reason)
        { "path" => path, "reason" => reason.first, "message" => reason.last }
      end

      # The Zone whose own context holds the taken Faces, as a reference. Every taken Face has one parent.
      def own_zone(containment, eligible)
        return nil if eligible.empty?

        row = containment.find { |candidate| candidate.fetch("path") == eligible.first.path }
        row["zone"]&.slice("zone_id", "zone_path")
      end

      # One Zone occurrence's Faces in world metres, or nil for one whose identity does not resolve.
      def candidate(request, row)
        located = request.locate(ZONE_KIND, row.fetch("reference"), :mutable => false)
        ZoneInference::Candidate.new(:reference => row.fetch("reference"),
                                     :faces => zone_faces(located.entity.entities,
                                                          located.transform * located.entity.transformation))
      rescue CodedError
        nil
      end

      # Every Face a Zone can own, through Groups and plain components; a cutting component's geometry is not
      # the Zone's (context/CONTRACTS.md, "Zones geometry rules").
      def zone_faces(entities, transform)
        entities.to_a.flat_map do |entity|
          if entity.is_a?(Sketchup::Face)
            [FaceCapture.call(entity, transform).loops_m]
          elsif entity.is_a?(Sketchup::Group)
            zone_faces(entity.entities, transform * entity.transformation)
          elsif entity.is_a?(Sketchup::ComponentInstance) && !entity.definition.behavior.cuts_opening?
            zone_faces(entity.definition.entities, transform * entity.transformation)
          else
            []
          end
        end
      end
    end
  end
end
