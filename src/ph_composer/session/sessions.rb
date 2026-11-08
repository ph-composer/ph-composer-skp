# frozen_string_literal: true

module PhComposer
  # The one registry of open Model sessions and the only code that keys anything by `model.object_id`.
  #
  # Every open Model keeps its session while it stays open, so switching between documents neither
  # ends a session nor invalidates its callers. A closed Model's session is dropped the next time the
  # registry is read. Reopening a file creates a new Model, and so a new session identity.
  module Sessions
    # What the host observers publish for a session.
    # `container_added` carries the added Group or ComponentInstance (ContainerWatch).
    HOST_EVENTS = %i[
      session_created model_opened model_activated transaction_committed transaction_undone transaction_redone
      active_path_changed selection_changed camera_changed tags_changed pre_save post_save container_added
      rendering_options_changed section_plane_changed
    ].freeze

    class << self
      def install
        # Registered here rather than at load so it runs after every reset registered at load: the
        # session it recreates reads their state.
        PhComposer.on_reset("sessions") { reset }
        return if @installed

        @app_observer = HostObservers::AppObserver.new
        Sketchup.add_observer(@app_observer)
        @installed = true
      end

      # The session of the Model already open, created once every subscriber is registered, so its
      # `session_created` reaches them: the composition root calls this after composing the features.
      def open_active
        self.for(Sketchup.active_model) if Sketchup.active_model
      end

      def for(model)
        return nil unless model

        existing = sessions[model.object_id]
        return existing if existing

        session = ModelSession.new(model)
        model_observer = HostObservers::ModelObserver.new
        selection_observer = HostObservers::SelectionObserver.new
        model.add_observer(model_observer)
        model.selection.add_observer(selection_observer) if model.selection.respond_to?(:add_observer)
        layers_observer = HostObservers::LayersObserver.new
        model.layers.add_observer(layers_observer) if model.layers.respond_to?(:add_observer)
        rendering_options = model.respond_to?(:rendering_options) ? model.rendering_options : nil
        rendering_observer = HostObservers::RenderingOptionsObserver.new(model)
        rendering_options&.add_observer(rendering_observer)
        view = model.respond_to?(:active_view) ? model.active_view : nil
        view_observer = HostObservers::ViewObserver.new
        view.add_observer(view_observer) if view.respond_to?(:add_observer)
        session.add_observers(ModelSession::Observers.new(:model => model_observer, :selection => selection_observer,
                                                          :layers => layers_observer, :view => view_observer,
                                                          :rendering => [rendering_options, rendering_observer]))
        sessions[model.object_id] = session
        session.host_event(:session_created)
        session
      end

      # The open session with this id, or nil when it was never issued or its Model has closed.
      def find(id)
        all.find { |session| session.id == id }
      end

      # Every open session, in the order the Models opened.
      def all
        closed = sessions.values.reject(&:valid?)
        closed.each { |session| detach(session.model) }
        sessions.values
      end

      def current
        Sketchup.active_model ? self.for(Sketchup.active_model) : nil
      end

      def on_change(&block)
        register_subscriber(change_subscribers, block)
      end

      def on_refresh(&block)
        register_subscriber(refresh_subscribers, block)
      end

      def on_notice(&block)
        register_subscriber(notice_subscribers, block)
      end

      # Subscribers run in subscription order, which is `install` order, and an error propagates to
      # the observer that published the event.
      def on_host_event(kind, &block)
        host_event!(kind)
        register_subscriber(host_event_subscribers[kind], block)
      end

      def notify_host_event(session, kind, *arguments)
        host_event!(kind)
        host_event_subscribers[kind].dup.each { |subscriber| subscriber.call(session, *arguments) }
      end

      def notify_change(session, source, detail)
        notify_subscribers(change_subscribers, session, source, detail)
      end

      def notify_refresh(session)
        notify_subscribers(refresh_subscribers, session)
      end

      def notify_notice(session, message, tone)
        notify_subscribers(notice_subscribers, session, message, tone)
      end

      def detach(model)
        return false unless model

        session = sessions.delete(model.object_id)
        return true unless session

        observers = session.observers
        model.remove_observer(observers.model) if observers.model && model.respond_to?(:remove_observer)
        selection = model.selection
        selection.remove_observer(observers.selection) if observers.selection && selection.respond_to?(:remove_observer)
        layers = model.respond_to?(:layers) ? model.layers : nil
        layers.remove_observer(observers.layers) if observers.layers && layers.respond_to?(:remove_observer)
        view = model.respond_to?(:active_view) ? model.active_view : nil
        view.remove_observer(observers.view) if observers.view && view.respond_to?(:remove_observer)
        rendering_options, rendering_observer = observers.rendering
        rendering_options&.remove_observer(rendering_observer)
        session.detach
        true
      end

      def reset
        sessions.values.dup.each { |session| detach(session.model) }
        Sketchup.remove_observer(@app_observer) if @app_observer
        @sessions = {}
        @app_observer = nil
        @installed = false
        install
        open_active
      end

      private

      def register_subscriber(subscribers, block)
        raise ArgumentError, "A session subscriber block is required." unless block

        subscribers << block
        -> { subscribers.delete(block) }
      end

      def notify_subscribers(subscribers, *arguments)
        subscribers.dup.each do |subscriber|
          subscriber.call(*arguments)
        rescue StandardError => error
          Diagnostics.exception("session_subscriber", error)
        end
      end

      def change_subscribers
        @change_subscribers ||= []
      end

      def refresh_subscribers
        @refresh_subscribers ||= []
      end

      def notice_subscribers
        @notice_subscribers ||= []
      end

      def host_event!(kind)
        raise ArgumentError, "Unknown host event: #{kind.inspect}." unless HOST_EVENTS.include?(kind)
      end

      def host_event_subscribers
        @host_event_subscribers ||= Hash.new { |subscribers, kind| subscribers[kind] = [] }
      end

      def sessions
        @sessions ||= {}
      end
    end
  end
end
