# frozen_string_literal: true

module PhComposer
  module Spaces
    # Create Space from SketchUp's context menu. The menu item is offered on a Face selection, or on the
    # Faces the Mark floor tool last offered; it works only inside an open Zone's edit context and says so
    # outside one. It reads the Faces' Zone references from Zones' `host_context`, so a selection mixing
    # eligible and ineligible Faces reaches the review whole, and hands the panel a review of what
    # `create_preview` accepts and leaves out. The panel confirms by calling `create` at the review's
    # revision. The operations take explicit references, so this availability rule lives in the route only.
    module CreateRoute
      ZONES = "ph_composer.zones.all"
      HOST_CONTEXT = "ph_composer.zones.faces.host_context"
      LABEL = "Create Space…"
      NO_ZONE = "Create Space works inside a Zone: open the Zone's edit context, select the floor outlines, then " \
                "choose Create Space. #{Outcome::NOTHING_WRITTEN}".freeze
      NO_FACES = "Select the floor outlines as Faces in the open Zone. #{Outcome::NOTHING_WRITTEN}".freeze

      module_function

      # A cheap structural test for the menu: a Face is selected, or the running Mark floor tool offered one.
      def available?(session)
        return true if session.model.selection.to_a.any? { |entity| entity.is_a?(Sketchup::Face) }

        tool = Spaces.mark_tool(session)
        tool.active? && !tool.offered.empty?
      end

      def review(session)
        session.feature_state(:spaces_create_review) { Review.new }
      end

      def client(session)
        session.feature_state(:spaces_create_menu) { Client.new(session) }
      end

      # `revision` is the one the caller read `faces` at; a later Model refuses. A new review replaces one
      # still open, so a review the panel never closed cannot hold Create Space shut.
      def open(request, zone:, faces:, revision:)
        if revision != request.revision
          raise CodedError.new("revision.stale", "The Model changed after the Faces were read. Nothing was written.")
        end

        row = request.query(ZONES).fetch("zones").find { |candidate| candidate.fetch("reference") == zone }
        raise CodedError.new("target.not_found", "That Zone occurrence no longer exists.") unless row

        preview = request.query("#{FEATURE_ID}.create_preview", "zone" => zone, "faces" => faces)
        review(request.session).open(zone, row.dig("values", "name").to_s, preview, request.revision)
        request.session.changed(:spaces, :create_review)
        review(request.session).snapshot
      end

      # The review the panel shows: a token per opening, the revision `create` must be applied at, the Zone,
      # and what `create_preview` accepted and left out.
      class Review
        def initialize
          clear
        end

        def open(zone, zone_name, preview, revision)
          @value = { "token" => SecureRandom.uuid, "revision" => revision, "zone" => DeepCopy.call(zone),
                     "zone_name" => zone_name, "accepted" => DeepCopy.call(preview.fetch("accepted")),
                     "left_out" => DeepCopy.call(preview.fetch("left_out")) }
        end

        def snapshot
          DeepCopy.call(@value)
        end

        def close(token)
          clear if @value.fetch("token") == token
          snapshot
        end

        def clear
          @value = { "token" => nil, "revision" => nil, "zone" => nil, "zone_name" => "", "accepted" => [],
                     "left_out" => [] }
        end

        def detach
          clear
        end
      end

      # The native menu's client: the same public reads and view command a script uses.
      class Client
        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
        end

        def run
          zone = open_zone
          return announce(NO_ZONE) unless zone

          paths = face_paths
          return announce(NO_FACES) if paths.empty?
          if paths.length > Pages::MAXIMUM_LIMIT
            return announce("Create Space takes at most #{Pages::MAXIMUM_LIMIT} Faces at once. " \
                            "#{Outcome::NOTHING_WRITTEN}")
          end

          rows = API.query(:context => @context, :name => HOST_CONTEXT, :params => { "paths" => paths })
          return refuse(rows) unless rows.fetch("status") == "completed"

          faces = rows.dig("value", "faces").map { |row| row.fetch("reference") }
          return announce(NO_FACES) if faces.empty?

          result = API.view(:context => @context, :name => "#{FEATURE_ID}.create_review.open",
                            :params => { "zone" => zone, "faces" => faces, "revision" => rows.fetch("revision") })
          return refuse(result) unless result.fetch("status") == "completed"

          Commands.open_panel.proc.call
          result
        end

        private

        # The Zone whose edit context is open: the innermost open container, matched to a Zone occurrence.
        def open_zone
          active = Array(@session.model.active_path).map(&:persistent_id)
          return nil if active.empty?

          read = API.query(:context => @context, :name => ZONES)
          return nil unless read.fetch("status") == "completed"

          row = read.dig("value", "zones").find { |candidate| candidate.dig("reference", "zone_path") == active }
          row&.fetch("reference")
        end

        # Root-to-Face paths: the selected Faces in the open context, or else what Mark floor last offered.
        def face_paths
          active = Array(@session.model.active_path).map(&:persistent_id)
          selected = @session.model.selection.to_a.select { |entity| entity.is_a?(Sketchup::Face) }
          return selected.map { |face| active + [face.persistent_id] } unless selected.empty?

          tool = Spaces.mark_tool(@session)
          tool.active? ? tool.offered : []
        end

        def announce(message, tone = :warning)
          HostNotice.show(@session, message, :tone => tone)
          nil
        end

        def refuse(outcome)
          announce(HostNotice.words(outcome), HostNotice.tone(outcome))
        end
      end
    end
  end
end
