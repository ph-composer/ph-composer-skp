# frozen_string_literal: true

module PhComposer
  module Spaces
    # What a Mark floor pick means, read from the pick's own path and never a Model walk (context/
    # EXTENSIBILITY.md, "Viewport tools"): the Spaces records on the path's containers and Zones' narrow
    # `host_context` row for a Face directly in a Zone, kept per path until the next refresh. A read that fails
    # raises its refusal rather than reading as an answer.
    class MarkPlacement
      HOST_CONTEXT = "ph_composer.zones.faces.host_context"
      OUTSIDE_SPACE = "That Face's Volume is in no Space. Move it into a Space, then mark its floors."
      ZONE_FACE = "That Face is one of its Zone's own Faces, classified in the Geometry view. Mark floor takes " \
                  "Faces inside a Space."
      NESTED = "That Face is inside a Group within its Zone. Create Space takes Faces drawn in the Zone's own " \
               "context; move it out of the Group first."
      NOT_LOOSE = "That Face is inside a closed Group or Zone. Create Space takes Faces loose in the open context; " \
                  "open it first."

      def initialize(session, context)
        @session = session
        @context = context
        @rows = {}
      end

      def refresh
        @rows = {}
        @read_at = read_at
      end

      def current
        refresh unless @read_at == read_at
      end

      # `[place, target]`: `:mark`; `:volume` with its Space's reference; `:offer`; or `:refuse` with the
      # reason. A Space in no Zone is an ordinary Space: the finding asks for a Zone, the tool does not.
      def place(entities)
        ids = entities.map(&:persistent_id)
        parent = entities[-2]
        if parent && Occurrences.read(VOLUME_STORE, VOLUME, parent)
          space_index = entities[0...-2].rindex { |entity| Occurrences.read(SPACE_STORE, SPACE, entity) }
          return [:refuse, OUTSIDE_SPACE] unless space_index

          return [:mark, nil]
        end
        if parent && (space = Occurrences.read(SPACE_STORE, SPACE, parent))
          return [:volume, { "space_id" => space.fetch("id"), "entity_path" => ids[0...-1] }]
        end

        loose_face(ids)
      end

      private

      def read_at
        [@session.revision, Array(@session.model.active_path).map(&:persistent_id)]
      end

      # A Face loose in the open context is offered Create Space. In a Zone, the Faces feature's record makes
      # it one of the Zone's own Faces, and a write to it may refuse from its path, as shared storage does.
      def loose_face(ids)
        row = host_row(ids)
        if row
          return [:refuse, ZONE_FACE] unless row.dig("reference", "entity_id").nil?
          return [:refuse, NESTED] unless row.dig("reference", "entity_path").length == 1
          return [:refuse, row.dig("write_refusal", "message")] if row["write_refusal"]
        end
        ids[0...-1] == read_at.last ? [:offer, nil] : [:refuse, NOT_LOOSE]
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
