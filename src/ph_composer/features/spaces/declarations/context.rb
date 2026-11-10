# frozen_string_literal: true

module PhComposer
  module Spaces
    # The edit-context commands, Unprotect, Restore position and the reconciler's subscriptions.
    module ContextRegistration
      # The protection boundary these commands may trigger (context/AGENT_INTERFACE.md, view commands).
      LEAVING = "Moves the edit path, which advances the Model revision; leaving a Volume that was open and " \
                "unprotected protects it again. No authored value changes; SketchUp itself records leaving a " \
                "Group as an Undo entry, and undoing it reopens the Group."
      PATH_RESULT = Shapes.object({ "path" => Shapes::ZONE_PATH.merge("description" => "The edit path afterwards.") })
      TARGET = %w[record.unreadable target.ambiguous target.changed target.locked target.not_found
                  target.shared_definition validation.failed].freeze
      OPEN_PARAM = Shapes.object({ "space_id" => Shapes::TEXT, "volume_id" => Shapes::TEXT, "entity_path" => PATH },
                                 :optional => %w[space_id volume_id],
                                 :description => "A Space, or an unprotected Volume, as list returns it.")
      VOLUME_PARAM = VOLUME_REFERENCE.merge("description" => "The Volume, as list returns it.").freeze
      ANY_PARAM = Shapes.object({ "space_id" => Shapes::TEXT, "volume_id" => Shapes::TEXT,
                                  "floor_segment_id" => Shapes::TEXT, "entity_path" => PATH },
                                :optional => %w[space_id volume_id floor_segment_id],
                                :description => "A Space, Volume or Floor Segment, as list returns it.")
      EXAMPLE_SPACE = { "space_id" => "spc_Ab12Cd34Ef56", "entity_path" => [1201, 1300] }.freeze
      EXAMPLE_VOLUME = { "volume_id" => "vol_Ab12Cd34Ef56", "entity_path" => [1201, 1300, 1310] }.freeze

      module_function

      def install(feature)
        declare_views(feature)
        feature.action("#{FEATURE_ID}.volumes.unprotect",
                       :description => "Unlock a protected Volume so context.open can open it. The edit context " \
                                       "does not move; leaving the Volume later protects it again.",
                       :refuses => TARGET, :params => Shapes.object({ "volume" => VOLUME_PARAM }),
                       :result => Shapes.object({ "volume_id" => Shapes::TEXT,
                                                  "unprotected" => { "type" => "boolean",
                                                                     "description" => "Whether it was protected." } }),
                       :undo_name => "Unprotect Volume", :side_effects => "Unlocks the Volume Group.",
                       :examples => [{ "volume" => EXAMPLE_VOLUME }]) do |request, proposal|
          Navigation.unprotect(request, proposal, :volume => request.params.fetch("volume"))
        end
        feature.action("#{FEATURE_ID}.volumes.restore_position",
                       :description => "Put a moved Volume back where it was last left, and protect it.",
                       :refuses => TARGET + %w[space.position_unknown space.volume_open],
                       :params => Shapes.object({ "volume" => VOLUME_PARAM }),
                       :result => Shapes.object({ "volume_id" => Shapes::TEXT,
                                                  "moved" => { "type" => "boolean",
                                                               "description" => "Whether it had moved." } }),
                       :undo_name => "Restore Volume Position", :side_effects => "Moves and locks the Volume Group.",
                       :examples => [{ "volume" => EXAMPLE_VOLUME }]) do |request, proposal|
          Authoring.restore_position(request, proposal, :volume => request.params.fetch("volume"))
        end
        subscribe(feature)
      end

      def declare_views(feature)
        feature.view_command("#{FEATURE_ID}.context.open",
                             :description => "Open a Space, or a Volume volumes.unprotect unlocked, as the edit " \
                                             "context; a Volume being left is protected first.",
                             :refuses => TARGET + %w[space.volume_protected session.inactive], :side_effects => LEAVING,
                             :params => Shapes.object({ "reference" => OPEN_PARAM }), :result => PATH_RESULT,
                             :examples => [{ "reference" => EXAMPLE_SPACE }]) do |request|
          Navigation.open(request, :reference => request.params.fetch("reference"))
        end
        feature.view_command("#{FEATURE_ID}.context.close",
                             :description => "Leave the innermost open Space or Volume for its parent, protecting a " \
                                             "Volume being left.",
                             :refuses => %w[session.inactive], :params => Shapes::NONE, :result => PATH_RESULT,
                             :side_effects => LEAVING,
                             :examples => [{}]) { |request| Navigation.close(request) }
        feature.view_command("#{FEATURE_ID}.locate",
                             :description => "Select and frame one Space, Volume or Floor Segment. Nothing is " \
                                             "unlocked: the path opens up to the first locked Group, such as a " \
                                             "protected Volume, and that Group is selected instead.",
                             :refuses => TARGET + %w[session.inactive],
                             :params => Shapes.object({ "reference" => ANY_PARAM }),
                             :side_effects => "Selects and frames. #{LEAVING}",
                             :result => PATH_RESULT, :examples => [{ "reference" => EXAMPLE_SPACE }]) do |request|
          Navigation.locate(request, :reference => request.params.fetch("reference"))
        end
      end

      # The reconciler hears every event that can move the path or the Volume on it.
      def subscribe(feature)
        %i[session_created model_opened].each do |kind|
          feature.on_host_event(kind) { |session| Reconciler.for(session).opened }
        end
        %i[transaction_committed active_path_changed].each do |kind|
          feature.on_host_event(kind) { |session| Reconciler.for(session).observed }
        end
        %i[transaction_undone transaction_redone].each do |kind|
          feature.on_host_event(kind) { |session| Reconciler.for(session).reverted }
        end
        feature.on_host_event(:pre_save) { |session| Reconciler.for(session).pre_save }
        EditContext.boundary(:spaces) do |model, from, to|
          volume = Protection.leaving(model, from, to)
          Reconciler.for(Sessions.for(model)).protected(volume) if volume
        end
      end
    end
  end
end
