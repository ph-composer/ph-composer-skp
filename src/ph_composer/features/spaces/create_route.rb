# frozen_string_literal: true

module PhComposer
  module Spaces
    # Create Space from SketchUp's context menu. The menu item is offered on a Face selection, or on the
    # Faces the Mark floor tool last offered, in any edit context. It hands the panel a review of what
    # `create_preview` accepts and leaves out, the Zone it preselects and the Zones to choose from; the panel
    # confirms by calling `create` at the review's revision. The operations take explicit paths, so this route
    # holds no rule of its own about where a Space may be made.
    module CreateRoute
      ZONES = "ph_composer.zones.all"
      LABEL = "Create Space from Floor Surface…"
      NO_FACES = "A Space is a floor surface plus a height: select the floor surface as Faces in the open context, " \
                 "then choose Create Space. #{Outcome::NOTHING_WRITTEN}".freeze

      module_function

      # Offered when a selected Face could become a floor, or the running Mark floor tool offered one. A wall or a
      # classified Face never could, so a selection of only those leaves the item out; one beside a floor stays
      # for the review's "Left out" list.
      def available?(read)
        return true if floor_selected?(read)

        tool = Spaces.mark_tool(read.session)
        tool.active? && !tool.offered.empty?
      end

      # Whether a selected Face is both non-vertical and unclassified: the review's own rule for those two, with
      # the geometry read first so only possible floors ask Zones. A selection too large for that read, or one
      # Zones cannot read, stays offered: the route says why when it runs.
      def floor_selected?(read)
        active = Array(read.model.active_path)
        transform = CreateFaces.open_transform(active)
        floors = read.model.selection.to_a.grep(Sketchup::Face).reject { |face| Eligibility.wall?(face, transform) }
        return false if floors.empty?
        return true if floors.length > Pages::MAXIMUM_LIMIT

        open_path = active.map(&:persistent_id)
        rows = read.query(CreateFaces::HOST_CONTEXT, "paths" => floors.map { |face| open_path + [face.persistent_id] })
        rows.fetch("faces").count { |row| row.dig("reference", "entity_id") } < floors.length
      rescue UserError
        true
      end

      def review(session)
        session.feature_state(:spaces_create_review) { Review.new }
      end

      def client(session)
        session.feature_state(:spaces_create_menu) { Client.new(session) }
      end

      # `revision` is the one the caller read `faces` at; a later Model refuses. A new review replaces one
      # still open, so a review the panel never closed cannot hold Create Space shut.
      def open(request, faces:, revision:)
        if revision != request.revision
          raise CodedError.new("revision.stale", "The Model changed after the Faces were read. Nothing was written.")
        end

        preview = request.query("#{FEATURE_ID}.create_preview", "faces" => faces)
        zones = request.query(ZONES).fetch("zones").map do |row|
          row.fetch("reference").merge("name" => row.dig("values", "name").to_s)
        end
        review(request.session).open(preview, zones, request.revision)
        request.session.changed(:spaces, :create_review)
        review(request.session).snapshot
      end

      # The review the panel shows: a token per opening, the revision `create` must be applied at, what
      # `create_preview` accepted and left out, the Zone it preselects, the Zones to choose from and the height.
      class Review
        def initialize
          clear
        end

        def open(preview, zones, revision)
          @value = { "token" => SecureRandom.uuid, "revision" => revision,
                     "zone" => DeepCopy.call(preview.fetch("zone")), "zones" => DeepCopy.call(zones),
                     "accepted" => DeepCopy.call(preview.fetch("accepted")),
                     "left_out" => DeepCopy.call(preview.fetch("left_out")), "height_m" => preview.fetch("height_m"),
                     "height_source" => preview.fetch("height_source") }
        end

        def snapshot
          DeepCopy.call(@value)
        end

        def close(token)
          clear if @value.fetch("token") == token
          snapshot
        end

        def clear
          @value = { "token" => nil, "revision" => nil, "zone" => nil, "zones" => [], "accepted" => [],
                     "left_out" => [], "height_m" => nil, "height_source" => nil }
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
          paths = face_paths
          return announce(NO_FACES) if paths.empty?
          if paths.length > Pages::MAXIMUM_LIMIT
            return announce("Create Space takes at most #{Pages::MAXIMUM_LIMIT} Faces at once. " \
                            "#{Outcome::NOTHING_WRITTEN}")
          end

          result = API.view(:context => @context, :name => "#{FEATURE_ID}.create_review.open",
                            :params => { "faces" => paths, "revision" => @session.revision })
          return refuse(result) unless result.fetch("status") == "completed"

          Commands.open_panel.proc.call
          result
        end

        private

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
