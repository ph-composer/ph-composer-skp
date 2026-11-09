# frozen_string_literal: true

module PhComposer
  module Spaces
    # The native route to a Space's floor surface: on one selected Volume, or a Space with one Volume, it does what the
    # panel's Enter does, `volumes.unprotect` when the Volume is protected and then `context.open`. Leaving the
    # Volume protects it again, as on every other route.
    module EditFloorSurfaceMenu
      LABEL = "Edit Floor Surface"
      UNPROTECT = "#{FEATURE_ID}.volumes.unprotect"
      OPEN = "#{FEATURE_ID}.context.open"
      SELECT_ONE = "Select one Space or Volume, then choose Edit Floor Surface."
      SEVERAL_VOLUMES = "This Space has several Volumes. Open the Space, select the Volume whose floor surface you " \
                        "want, then choose Edit Floor Surface."
      NO_VOLUME = "This Space has no Volume to edit."
      UNPROTECTED = "The Volume was left unprotected; Undo protects it again."

      module_function

      def install(feature)
        feature.menu_item("#{FEATURE_ID}.edit_floor_surface_menu",
                          :label => LABEL, :menu => EXTENSION_NAME,
                          :available => ->(read) { !selected(read.session).nil? }) do |session|
          session.feature_state(:spaces_edit_floor_surface_menu) { Client.new(session) }.run
        end
      end

      # The one selected Space or Volume Group, or nil.
      def selected(session)
        chosen = session.model.selection.to_a
        return unless chosen.length == 1 && (Protection.volume?(chosen.first) || Navigation.space?(chosen.first))

        chosen.first
      end

      # The Volume a Space selection means, from what the Space directly holds, or the sentence saying why
      # there is none.
      def volume_in(space)
        volumes = space.entities.to_a.select { |entity| Protection.volume?(entity) }
        return NO_VOLUME if volumes.empty?

        volumes.length == 1 ? volumes.first : SEVERAL_VOLUMES
      end

      class Client
        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
          @sequence = 0
        end

        def run
          entity = EditFloorSurfaceMenu.selected(@session)
          return say(SELECT_ONE) unless entity

          path = Array(@session.model.active_path).map(&:persistent_id) + [entity.persistent_id]
          volume = Protection.volume?(entity) ? entity : EditFloorSurfaceMenu.volume_in(entity)
          return say(volume) if volume.is_a?(String)

          path += [volume.persistent_id] unless volume.equal?(entity)
          open_volume(volume, { "volume_id" => VOLUME_STORE.read(volume).fetch("id"), "entity_path" => path })
        rescue CodedError => error
          say(error.message)
        end

        private

        def open_volume(volume, reference)
          if volume.locked?
            @sequence += 1
            unlocked = API.invoke(:context => @context, :name => UNPROTECT, :params => { "volume" => reference },
                                  :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
            return report(unlocked) unless unlocked.fetch("status") == "completed"

            return report(open(reference), UNPROTECTED)
          end
          report(open(reference))
        end

        def open(reference)
          API.view(:context => @context, :name => OPEN, :params => { "reference" => reference })
        end

        def report(outcome, note = nil)
          return outcome if outcome.fetch("status") == "completed"

          UI.messagebox([outcome.fetch("message"), note].compact.join(" "))
          outcome
        end

        def say(message)
          UI.messagebox(message)
          nil
        end
      end
    end
  end
end
