# frozen_string_literal: true

module PhComposer
  # Adapters from SketchUp's observer callbacks to session host events. They record the event and
  # return; deferred work mutates (context/TECH_STACK.md "Observers report; deferred work mutates").
  # Features subscribe to the events in their `install`; nothing here names a feature.
  module HostObservers
    class AppObserver < Sketchup::AppObserver
      def onNewModel(model)
        Sessions.for(model)
      end

      # The host can create a Model's session before its file has loaded, so an opened file is reported
      # to the session whether it is new or not.
      def onOpenModel(model)
        Sessions.for(model).host_event(:model_opened)
      end

      def onActivateModel(model)
        session = Sessions.for(model)
        session.host_event(:model_activated)
        Sessions.notify_refresh(session)
      end
    end

    class ModelObserver < Sketchup::ModelObserver
      def onTransactionCommit(model)
        Sessions.for(model).host_event(:transaction_committed)
      end

      def onTransactionUndo(model)
        Sessions.for(model).host_event(:transaction_undone)
      end

      def onTransactionRedo(model)
        Sessions.for(model).host_event(:transaction_redone)
      end

      def onActivePathChanged(model)
        Sessions.for(model).host_event(:active_path_changed)
      end

      def onPreSaveModel(model)
        Sessions.for(model).host_event(:pre_save)
      end

      def onSaveModel(model)
        Sessions.for(model).host_event(:post_save)
      end
    end

    # Tag visibility decides what a viewport drawing may paint. Whether the host also commits a
    # transaction for it, and so advances the session revision, is not measured: a subscriber that
    # has to repaint should not wait to find out, so the event is published on its own.
    class LayersObserver < Sketchup::LayersObserver
      def onLayerChanged(layers, _layer)
        tags_changed(layers)
      end

      def onLayerRemoved(layers, _layer)
        tags_changed(layers)
      end

      def onRemoveAllLayers(layers)
        tags_changed(layers)
      end

      # A tag in a hidden tag folder is hidden however its own flag reads, so a folder change is a tag change.
      def onLayerFolderAdded(layers, _folder)
        tags_changed(layers)
      end

      def onLayerFolderChanged(layers, _folder)
        tags_changed(layers)
      end

      def onLayerFolderRemoved(layers, _folder)
        tags_changed(layers)
      end

      private

      def tags_changed(layers)
        model = layers.respond_to?(:model) ? layers.model : Sketchup.active_model
        session = model && Sessions.for(model)
        session&.host_event(:tags_changed)
      end
    end

    # The camera moved: the view generation advances, so a selection page or a capture read before it is
    # known to be of another view. No refresh: nothing the panel shows depends on the camera.
    class ViewObserver < Sketchup::ViewObserver
      def onViewChanged(view)
        model = view.respond_to?(:model) ? view.model : Sketchup.active_model
        Sessions.for(model)&.host_event(:camera_changed)
      end
    end

    class SelectionObserver < Sketchup::SelectionObserver
      def onSelectionBulkChange(selection)
        selection_changed(selection)
      end

      def onSelectionCleared(selection)
        selection_changed(selection)
      end

      def onSelectionAdded(selection, _entity)
        selection_changed(selection)
      end

      def onSelectionRemoved(selection, _entity)
        selection_changed(selection)
      end

      private

      def selection_changed(selection)
        model = selection.respond_to?(:model) ? selection.model : Sketchup.active_model
        session = model && Sessions.for(model)
        return unless session

        session.host_event(:selection_changed)
        session.request_refresh
      end
    end
  end
end
