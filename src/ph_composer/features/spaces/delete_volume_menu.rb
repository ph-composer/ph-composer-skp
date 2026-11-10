# frozen_string_literal: true

module PhComposer
  module Spaces
    # Delete Volume from SketchUp's context menu, on one Volume selected in an open Space: `volumes.delete` erases it
    # with its floor Faces in one Undo step. Volumes stay locked, so SketchUp's own Delete passes them by; this item is
    # the native route instead (unlocking a selected Volume spent Redo on every Undo). A Space's only Volume asks
    # first and deletes the Space through `delete`, so no route here leaves a Space empty.
    module DeleteVolumeMenu
      LABEL = "Delete Volume"
      SELECT_ONE = "Select one Volume in an open Space, then choose Delete Volume. #{Outcome::NOTHING_WRITTEN}".freeze

      # The one selected Volume and its open Space, as references an action takes, with both records and whether it is
      # the Space's only Volume.
      Selected = Struct.new(:volume, :space, :volume_record, :space_record, :only, keyword_init: true)

      module_function

      # A provider rather than a `menu_item`, so the item stays off the Extensions menu, where no selection says which
      # Volume it deletes.
      def install(feature)
        feature.menu_entries("#{FEATURE_ID}.delete_volume_menu", :menu => EXTENSION_NAME,
                                                                 :available => ->(read) { available?(read.model) }) do
          [Declarations::MenuEntry.new(:label => LABEL, :handler => ->(session) { client(session).run })]
        end
      end

      # Offered when the selection is one Volume directly in the open Space.
      def available?(model)
        chosen = model.selection.to_a
        return false unless chosen.length == 1 && Protection.volume?(chosen.first)

        !AddVolumeMenu.open_space(Array(model.active_path)).nil?
      end

      # The selected Volume, or nil unless `available?`.
      def selected(model)
        return unless available?(model)

        active = Array(model.active_path)
        space = active.last
        volume = model.selection.to_a.first
        path = active.map(&:persistent_id)
        volume_record = VOLUME_STORE.read(volume)
        space_record = SPACE_STORE.read(space)
        Selected.new(:volume => { "volume_id" => volume_record.fetch("id"),
                                  "entity_path" => path + [volume.persistent_id] },
                     :space => { "space_id" => space_record.fetch("id"), "entity_path" => path },
                     :volume_record => volume_record, :space_record => space_record,
                     :only => space.entities.to_a.count { |entity| Protection.volume?(entity) } == 1)
      end

      # The question asked before a Space's only Volume goes: the Space goes with it.
      def offer(selected)
        space = Names.space(selected.space_record)
        "#{Names.volume(selected.volume_record)} is the only Volume of #{space}. Delete the Space instead?\n\n" \
          "#{space} and everything in it will be erased. One Undo brings it back."
      end

      def client(session)
        session.feature_state(:spaces_delete_volume_menu) { Client.new(session) }
      end

      # The native menu's client: the same public actions a script uses, under its own caller handle.
      class Client
        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
          @sequence = 0
        end

        def run
          target = DeleteVolumeMenu.selected(@session.model)
          return announce(SELECT_ONE) unless target

          revision = @session.revision
          return report(invoke("#{FEATURE_ID}.volumes.delete", { "volume" => target.volume }, revision)) unless
            target.only
          return unless UI.messagebox(DeleteVolumeMenu.offer(target), MB_YESNO) == IDYES

          report(invoke("#{FEATURE_ID}.delete", { "space" => target.space }, revision))
        rescue CodedError => error
          announce(error.message)
        end

        private

        def invoke(name, params, revision)
          @sequence += 1
          API.invoke(:context => @context, :name => name, :params => params,
                     :request => { "sequence" => @sequence, "expected_revision" => revision })
        end

        def report(outcome)
          if outcome.fetch("status") == "completed"
            @session.notice(outcome.fetch("message"), :tone => :success)
            Sketchup.status_text = outcome.fetch("message")
          else
            HostNotice.show(@session, HostNotice.words(outcome), :tone => HostNotice.tone(outcome))
          end
          outcome
        end

        def announce(message)
          HostNotice.show(@session, message, :tone => :warning)
          nil
        end
      end
    end
  end
end
