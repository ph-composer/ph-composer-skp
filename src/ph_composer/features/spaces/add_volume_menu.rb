# frozen_string_literal: true

module PhComposer
  module Spaces
    # Add New Volume to Space from SketchUp's context menu: with a Space open, the selected loose Faces at its root
    # become its next Volumes through `volumes.create`, one per set of Faces joined by shared Edges, with weighting
    # factor 1 and the Space's default height. No dialog: one click, one Undo step. It takes the place of Create
    # Space there, which is never offered inside a Space (CreateRoute.available?).
    module AddVolumeMenu
      LABEL = "Add New Volume to Space"
      CREATE_VOLUME = "#{FEATURE_ID}.volumes.create"
      NOT_IN_SPACE = "Open a Space and select loose Faces at its root, then choose Add New Volume to Space. " \
                     "#{Outcome::NOTHING_WRITTEN}".freeze
      NO_FACES = "Select the new Volume's floor surface as loose Faces at the open Space's root, then choose Add New " \
                 "Volume to Space. #{Outcome::NOTHING_WRITTEN}".freeze

      module_function

      def install(feature)
        feature.menu_item("#{FEATURE_ID}.add_volume_menu", :label => LABEL, :menu => EXTENSION_NAME,
                                                           :available => ->(read) { available?(read) }) do |session|
          session.feature_state(:spaces_add_volume_menu) { Client.new(session) }.run
        end
      end

      # Offered when the innermost open context is a Space and a selected Face there could be a floor: not yet a
      # Floor Segment and not vertical. A wall beside a floor stays, for the operation to refuse with its reason.
      def available?(read)
        active = Array(read.model.active_path)
        return false unless open_space(active)

        transform = CreateFaces.open_transform(active)
        read.model.selection.to_a.grep(Sketchup::Face).any? do |face|
          !FLOOR_SEGMENT_STORE.marks?(face) && !Eligibility.wall?(face, transform)
        end
      end

      # The open Space Group when it is the innermost open context, or nil.
      def open_space(active)
        space = active.last
        space if space && SPACE_STORE.marks?(space)
      end

      # What the route says once the Volumes are made.
      def added(volumes)
        segments = volumes.sum { |volume| volume.fetch("floor_segment_ids").length }
        made = volumes.length == 1 ? "a Volume" : "#{volumes.length} Volumes"
        "Added #{made} to the Space with #{segments} #{segments == 1 ? 'Floor Segment' : 'Floor Segments'}."
      end

      # The native menu's client: the same public action a script uses, under its own caller handle.
      class Client
        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
          @sequence = 0
        end

        def run
          active = Array(@session.model.active_path)
          space = AddVolumeMenu.open_space(active)
          return announce(NOT_IN_SPACE) unless space

          path = active.map(&:persistent_id)
          faces = @session.model.selection.to_a.grep(Sketchup::Face).map { |face| path + [face.persistent_id] }
          return announce(NO_FACES) if faces.empty?
          if faces.length > Pages::MAXIMUM_LIMIT
            return announce("Add New Volume to Space takes at most #{Pages::MAXIMUM_LIMIT} Faces at once. " \
                            "#{Outcome::NOTHING_WRITTEN}")
          end

          invoke({ "space_id" => SPACE_STORE.read(space).fetch("id"), "entity_path" => path }, faces)
        rescue CodedError => error
          announce(error.message)
        end

        private

        def invoke(space, faces)
          @sequence += 1
          outcome = API.invoke(:context => @context, :name => CREATE_VOLUME,
                               :params => { "space" => space, "faces" => faces },
                               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
          if outcome.fetch("status") == "completed"
            announce(AddVolumeMenu.added(outcome.dig("value", "volumes")), :success)
          else
            announce(HostNotice.words(outcome), HostNotice.tone(outcome))
          end
          outcome
        end

        def announce(message, tone = :warning)
          HostNotice.show(@session, message, :tone => tone)
          nil
        end
      end
    end
  end
end
