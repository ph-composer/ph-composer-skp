# frozen_string_literal: true

module PhComposer
  # Reports each Group or ComponentInstance added to any container of one Model as the
  # `container_added` host event, with the entity. A native copy arrives as such an addition after its
  # transaction commits, already carrying its instance dictionaries (context/SKETCHUP_HOST_BEHAVIOR.md,
  # "Observers and edit contexts"), so a feature that reconciles copies needs the addition, not only
  # the commit. A ComponentInstance changed in place, as by native Move, is `instance_modified`. One
  # EntitiesObserver sits on the Model's entities and on every Group's and definition's entities; the set
  # is found again after each commit, Undo, Redo and activation, in one coalesced pass, and a container
  # just added is observed at once. It names no feature and holds no Model work, so it never makes the
  # session busy.
  class ContainerWatch
    # The host events after which the set of containers may have changed.
    REDISCOVER = %i[session_created model_activated transaction_committed transaction_undone
                    transaction_redone].freeze

    class Observer < Sketchup::EntitiesObserver
      def initialize(watch)
        super()
        @watch = watch
      end

      def onElementAdded(_entities, entity)
        @watch.added(entity)
      end

      def onElementModified(_entities, entity)
        @watch.modified(entity)
      end

      # Activating a section plane raises no transaction, and this is the one observer on the Model's entities.
      def onActiveSectionPlaneChanged(_entities)
        @watch.section_changed
      end
    end

    def self.for(session)
      session.feature_state(:container_watch) { new(session) }
    end

    # The host's refusal to read a container it deleted after reporting it added, as when the copy is undone
    # or erased within the same operation. There is then nothing to observe or reconcile, so a callback walking
    # the addition passes it by; any other error is still a defect to log.
    def self.deleted_reference?(error)
      error.is_a?(TypeError) && error.message.start_with?("reference to deleted")
    end

    def initialize(session)
      @session = session
      @observer = Observer.new(self)
      @observed = {}
      @timer = CoalescedTimer.new
    end

    # A new session is observed at once, so the first native copy after it opens is seen.
    def host_event(kind)
      return discover if kind == :session_created

      @timer.schedule { discover } if REDISCOVER.include?(kind)
    end

    def section_changed
      @session.host_event(:section_plane_changed)
    end

    def added(entity)
      return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

      fresh = {}
      walk(contents(entity), key(entity), fresh)
      fresh.each { |found_key, entities| observe(found_key, entities) }
      @session.host_event(:container_added, entity)
    rescue StandardError => error
      # An observer callback must not raise into SketchUp; a subscriber's failure is its own.
      Diagnostics.exception("container_added", error) unless self.class.deleted_reference?(error)
    end

    # Fires for every Edge and Face a gesture touches, so anything else is passed by before it costs a call.
    def modified(entity)
      return unless entity.is_a?(Sketchup::ComponentInstance)

      @session.host_event(:instance_modified, entity)
    rescue StandardError => error
      Diagnostics.exception("instance_modified", error) unless self.class.deleted_reference?(error)
    end

    # Observes every container now in the Model and stops observing those gone. Each collection is keyed
    # by its definition's persistent id, because `Group#entities` answers a new Ruby wrapper on every call
    # (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts"): a definition several placements
    # share is walked and observed once, and an unchanged one is not observed again.
    def discover
      @timer.cancel
      found = {}
      walk(@session.model.entities, :model, found)
      @observed.each { |container_key, entities| unobserve(entities) unless found.key?(container_key) }
      found.each { |container_key, entities| entities.add_observer(@observer) unless @observed.key?(container_key) }
      # The wrapper an observer was added through is kept, so it is the one later removed.
      @observed = found.to_h { |container_key, entities| [container_key, @observed.fetch(container_key, entities)] }
    end

    def detach
      @timer.cancel
      @observed.each_value { |entities| unobserve(entities) }
      @observed = {}
    end

    private

    def walk(entities, container_key, found)
      return if found.key?(container_key)

      found[container_key] = entities
      entities.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        walk(contents(entity), key(entity), found)
      end
    end

    def observe(container_key, entities)
      return if @observed.key?(container_key)

      entities.add_observer(@observer)
      @observed[container_key] = entities
    end

    def key(container)
      container.definition.persistent_id
    end

    def contents(container)
      container.is_a?(Sketchup::ComponentInstance) ? container.definition.entities : container.entities
    end

    def unobserve(entities)
      entities.remove_observer(@observer)
    rescue TypeError => error
      # Entities has no valid? predicate. The host deletes its observers with the collection when a
      # Model closes or a definition is removed; only that native refusal is harmless.
      raise unless error.message == "reference to deleted Entities"
    end
  end
end
