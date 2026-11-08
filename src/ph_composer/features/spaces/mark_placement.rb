# frozen_string_literal: true

module PhComposer
  module Spaces
    # What a Mark floor pick means, read from the pick's own path and never a Model walk (context/
    # EXTENSIBILITY.md, "Viewport tools"): the Spaces records on the path's containers, the Zone paths read
    # once per revision and edit context, and Zones' narrow `host_context` row for a Face directly in a Zone,
    # kept per path until the next refresh. A read that fails raises its refusal rather than reading as an
    # answer.
    class MarkPlacement
      ZONES = "ph_composer.zones.all"
      HOST_CONTEXT = "ph_composer.zones.faces.host_context"
      OUTSIDE_ZONE = "That Face is in no Zone. Make it a Zone first, then mark floors in its Spaces."
      OUTSIDE_SPACE = "That Face's Volume is in no Space. Move it into a Space, then mark its floors."
      ZONE_FACE = "That Face is one of its Zone's own Faces, classified in the Geometry view. Mark floor takes " \
                  "Faces inside a Space."
      NESTED = "That Face is inside a Group within its Zone. Create Space takes Faces drawn in the Zone's own " \
               "context; move it out of the Group first."

      def initialize(session, context)
        @session = session
        @context = context
        @rows = {}
      end

      def refresh
        @zone_paths = query(ZONES).fetch("zones").map { |zone| zone.dig("reference", "zone_path") }
        @rows = {}
        @read_at = read_at
      end

      def current
        refresh unless @read_at == read_at
      end

      # `[place, target]`: `:mark`; `:volume` with its Space's reference; `:offer`; or `:refuse` with the
      # reason. Every route needs a Zone above the Face.
      def place(entities)
        ids = entities.map(&:persistent_id)
        parent = entities[-2]
        if parent && Occurrences.read(VOLUME_STORE, VOLUME, parent)
          space_index = entities[0...-2].rindex { |entity| Occurrences.read(SPACE_STORE, SPACE, entity) }
          return [:refuse, OUTSIDE_SPACE] unless space_index
          return [:refuse, OUTSIDE_ZONE] unless in_zone?(ids[0..space_index])

          return [:mark, nil]
        end
        if parent && (space = Occurrences.read(SPACE_STORE, SPACE, parent))
          return [:refuse, OUTSIDE_ZONE] unless in_zone?(ids[0...-1])

          return [:volume, { "space_id" => space.fetch("id"), "entity_path" => ids[0...-1] }]
        end
        zone_face(ids)
      end

      private

      def read_at
        [@session.revision, Array(@session.model.active_path).map(&:persistent_id)]
      end

      # A Face directly in a Zone is offered Create Space unless the Faces feature records it, which makes
      # it one of the Zone's own Faces, or a write to it would refuse from its path, as shared storage does.
      def zone_face(ids)
        row = host_row(ids)
        return [:refuse, OUTSIDE_ZONE] unless row
        return [:refuse, ZONE_FACE] unless row.dig("reference", "entity_id").nil?
        return [:refuse, NESTED] unless row.dig("reference", "entity_path").length == 1
        return [:refuse, row.dig("write_refusal", "message")] if row["write_refusal"]

        [:offer, nil]
      end

      def in_zone?(space_path)
        !Occurrences.zone_path(space_path, @zone_paths).nil?
      end

      def host_row(ids)
        return @rows[ids] if @rows.key?(ids)

        @rows[ids] = query(HOST_CONTEXT, "paths" => [ids]).fetch("faces").first
      end

      def query(name, params = {})
        result = API.query(:context => @context, :name => name, :params => params)
        raise CodedError.new(result.fetch("code"), result.fetch("message")) unless result.fetch("status") == "completed"

        result.fetch("value")
      end
    end
  end
end
