# frozen_string_literal: true

module PhComposer
  module Zones
    # Makes a fresh native copy of a Zone independent automatically, joined to the user's copy so one
    # Undo removes both. The Zones reconciler for copies, following "Observers report; deferred
    # work mutates" (context/TECH_STACK.md); the host facts it relies on are in
    # context/SKETCHUP_HOST_BEHAVIOR.md and the rule it applies in context/CONTRACTS.md, "Reconciliation".
    #
    # A native copy arrives as an added Group after its transaction commits, with its Zone record
    # attached, so the session's `container_added` event queues a deferred pass, which remembers which
    # containers the gesture added. In the pass, every occurrence whose path
    # holds none of them is an original; an id held by exactly one original and by added occurrences
    # has copies, which are those added occurrences. A duplicate that was already there has two
    # originals and is left for the explicit command, as is anything in a file as it opens. Paths
    # through a ComponentInstance are dropped silently, because a component's placements share it by
    # design. The rest run as one gesture through `HostFollowUp` and Make Zone
    # independent: all or nothing, one notice.
    #
    # Undo and Redo drop a pending pass and never repair: an array count (`5x`) undoes the first copy
    # and commits every copy in one transaction, and Redo restores a repaired copy without an addition.
    #
    # The repair joins the latest transaction. A native Move/Copy commits once more after its addition,
    # inside the copy's own Undo step (measured: one Undo removes copy and repair), and callbacks cannot
    # tell that commit from an unrelated operation committed before the deferred pass. If one was
    # unrelated, undoing it also undoes the repair while the copied Group stays. That state is
    # consistent (the copy is read only and offers Make Zone independent), and the watcher says so.
    module CopyWatch
      ACTION = "#{FEATURE_ID}.make_independent"

      module_function

      def state(session)
        session.feature_state(:zones_copy_watch) { State.new(session) }
      end

      def install(feature)
        feature.on_host_event(:container_added) { |session, entity| state(session).container_added(entity) }
        feature.on_host_event(:transaction_undone) { |session| state(session).undone }
        feature.on_host_event(:transaction_redone) { |session| state(session).reset }
      end

      class State
        def initialize(session)
          @session = session
          @work = DeferredWork.new { |jobs| run(jobs.fetch(:added)) }
          @running = false
          @repaired = {}
        end

        # Everything in the Model is an original from here on; a pending pass is dropped.
        def reset
          @work.cancel unless @running
        end

        # Undo and Redo: drop a pending pass, and say so if an Undo took back a repair but left its copy.
        def undone
          reset
          return if @running || @repaired.empty?

          live = occurrences.to_h
          return if live.empty? # An unreadable Model is no evidence that the copies left; keep them.

          # A copy no longer in the Model has nothing left to warn about; every other repair is kept, so a
          # later Undo of an earlier batch, or another Undo after a Redo, still warns.
          @repaired = @repaired.select { |path, _id| live.key?(path) }
          reverted = @repaired.select { |path, id| live.fetch(path) != id }
          return if reverted.empty?

          count = reverted.length
          @session.notice("Undo also took back making the #{count == 1 ? 'copied Zone' : "#{count} copied Zones"} " \
                          "independent, because it had joined a later change. #{count == 1 ? 'It is' : 'They are'} " \
                          "read only again; use Make Zone independent on #{count == 1 ? 'its row' : 'their rows'}.",
                          :tone => :warning)
        end

        # Only an addition that brings in a Zone id another occurrence already holds can be a copy.
        # Anything else leaves the session free, because a pending watcher makes every read and write
        # wait. The check is a read, inside the callback, and walks the Zones only for an addition that
        # carries a Zone record.
        def container_added(entity)
          return if @running
          # A pass is already due and recomputes the copies itself: the rest of the gesture only adds ids.
          return queue(entity) if @work.pending?

          ids = zone_ids(entity)
          return if ids.empty?
          return unless occurrences.map(&:last).tally.any? { |id, count| count > 1 && ids.include?(id) }

          queue(entity)
        rescue StandardError => error
          # A failure here is the watcher's own; the other subscribers to the addition still hear it.
          Diagnostics.exception("zone_copy_watch_added", error) unless ContainerWatch.deleted_reference?(error)
        end

        def pending?
          @work.pending?
        end

        def settle
          @work.settle
        end

        def detach
          @work.detach
          @repaired = {}
        end

        private

        def queue(entity)
          @work.queue(:added, [entity.persistent_id]) { |queued, more| queued + more }
        end

        def zone_ids(entity, found = [])
          record = stored_record(entity) if entity.is_a?(Sketchup::Group)
          found << record["id"] if record.is_a?(Hash) && record["id"]
          children = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.entities : entity.entities
          children.each do |child|
            zone_ids(child, found) if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
          end
          found
        end

        def occurrences
          Occurrences.zones(@session.model).map { |zone| [zone.path, zone.record.fetch("id")] }
        rescue CodedError => error
          # An unreadable Zone record is the Zones read's to report; the watcher waits for the next change.
          Diagnostics.log("zone_copy_watch", "code" => error.code)
          []
        end

        def stored_record(entity)
          ZONE_STORE.read(entity)
        rescue CodedError
          nil # An unreadable record is the Zones read's to report, not a copy to repair.
        end

        def copies(added)
          occurrences.group_by(&:last).flat_map do |_id, group|
            fresh = group.select { |path, _| (path & added).any? }
            group.length - fresh.length == 1 ? fresh : []
          end.map(&:first).reject { |path| through_component?(path) }
        end

        def through_component?(path)
          entities = @session.model.entities
          path[0...-1].each do |persistent_id|
            entity = entities.find { |candidate| candidate.persistent_id == persistent_id }
            return false unless entity
            return true if entity.is_a?(Sketchup::ComponentInstance)

            entities = entity.entities
          end
          false
        end

        def run(added)
          paths = copies(added)
          return if paths.empty?

          @running = true
          paths = copies(added) if CopiedGroups.isolate(@session, paths, added)
          return if paths.empty?

          params = paths.map { |path| { "zone_path" => path, "copy_added" => added } }
          result = HostFollowUp.run(@session, ACTION, params)
          @session.changed(:zones, :copy_watch) if result.fetch("status") != "refused"
          remember(paths, result)
          announce(paths, result)
        rescue StandardError => error
          Diagnostics.exception("zone_copy_watch", error)
          @session.notice("The copied Zone could not be made independent. Use Make Zone independent on " \
                          "its row.", :tone => :warning)
        ensure
          @running = false
        end

        # Each notice says what is true in the Model afterwards; a failure is read back rather than assumed.
        def remember(paths, result)
          return unless result.fetch("status") == "completed"

          repaired = paths.zip(result.fetch("values")).to_h { |path, value| [path, value.fetch("zone_id")] }
          @repaired = @repaired.merge(repaired)
        end

        def announce(paths, result)
          count = paths.length
          zones = count == 1 ? "copied Zone" : "#{count} copied Zones"
          case result.fetch("status")
          when "completed"
            retired = result.fetch("values").sum { |value| value.fetch("retired_pairs") }
            message = "Made the #{zones} independent."
            message += " #{retired} copied Surface #{retired == 1 ? 'pair was' : 'pairs were'} retired; run " \
                       "Solve adjacencies again." if retired.positive?
            @session.notice(message, :tone => retired.positive? ? :info : :success)
          when "refused"
            @session.notice("The #{zones} #{count == 1 ? 'stays' : 'stay'} shared: #{result.fetch('message')}",
                            :tone => :warning)
          else
            failed(paths, zones, result)
          end
        end

        def failed(paths, zones, result)
          unless result.fetch("restored")
            return @session.notice("Making the #{zones} independent failed partway, and not everything it " \
                                   "wrote could be put back. Check their rows before editing them.", :tone => :error)
          end

          isolated = paths.count { |path| own_storage?(path) }
          message = "The #{zones} could not be made independent; #{paths.length == 1 ? 'its' : 'their'} records " \
                    "are as copied."
          message += " #{owned(isolated, paths.length)}" if isolated.positive?
          @session.notice("#{message} Use Make Zone independent on #{paths.length == 1 ? 'its row' : 'their rows'}.",
                          :tone => :warning)
        end

        def owned(isolated, count)
          return "It now has Faces of its own." if count == 1

          who = isolated == count ? "All" : isolated.to_s
          "#{who} of them now #{isolated == 1 ? 'has' : 'have'} Faces of their own."
        end

        def own_storage?(path)
          zone = Occurrences.zones(@session.model).find { |occurrence| occurrence.path == path }
          zone && !zone.shared_definition
        rescue CodedError
          false
        end
      end
    end
  end
end
