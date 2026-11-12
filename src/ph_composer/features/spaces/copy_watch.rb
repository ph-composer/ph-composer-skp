# frozen_string_literal: true

module PhComposer
  module Spaces
    # Makes a fresh native copy of a Space independent automatically, joined to the user's copy so one
    # Undo removes both, as the Zones copy watcher does (context/CONTRACTS.md, "Reconciliation"). A native
    # copy arrives as an added Group after its transaction commits, already carrying its Space record
    # (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts"), so the session's
    # `container_added` event queues a deferred pass. In the pass every Space occurrence whose path holds
    # none of the added Groups is an original; an id held by exactly one original and by added occurrences
    # has copies, which are those added occurrences. Two originals sharing an id are left for the explicit
    # Make independent, as is anything in a file as it opens. A plain Group copied whole is first given its
    # own storage (Zones::CopiedGroups), so a storey Group's Spaces repair like any others (the
    # collection-copy contract, context/CONTRACTS.md, "Space membership"). A Space inside a copied Zone is
    # left to that Zone's repair, and a copy inside a component keeps its finding and gets one notice. The
    # rest run as one gesture through `HostFollowUp` and Make independent: all or nothing, one notice.
    #
    # Undo and Redo drop a pending pass and never repair: an array count (`5x`) undoes the first copy and
    # commits every copy in one transaction, and Redo restores a repaired copy without an addition.
    #
    # The repair joins the latest transaction. A native copy commits once more after its addition, inside
    # the copy's own Undo step, but an unrelated operation committed before the deferred pass looks the
    # same. Undoing that operation then takes the repair back while the copy stays; the watcher says so,
    # and the copy keeps its finding and its explicit repair.
    module CopyWatch
      ACTION = "#{FEATURE_ID}.make_independent"

      module_function

      def state(session)
        session.feature_state(:spaces_copy_watch) { State.new(session) }
      end

      def install(feature)
        feature.on_host_event(:container_added) { |session, entity| state(session).added(entity) }
        feature.on_host_event(:transaction_undone) { |session| state(session).undone }
        feature.on_host_event(:transaction_redone) { |session| state(session).reset }
      end

      class State
        def initialize(session)
          @session = session
          @work = DeferredWork.new { |jobs| run(jobs.fetch(:added)) }
          @repaired = {}
        end

        # Only an added container holding a Space whose id another occurrence already holds can be a copy,
        # so nothing else makes the session wait. The check is a read inside the callback.
        def added(entity)
          ids = if entity.is_a?(Sketchup::Group) then ids_inside([entity])
                elsif entity.is_a?(Sketchup::ComponentInstance) then ids_inside(entity.definition.entities)
                else []
                end
          return if ids.empty?

          held = occurrences.map { |space| space.record.fetch("id") }.tally
          return unless ids.any? { |id| held.fetch(id, 0) > 1 }

          @work.queue(:added, [entity.persistent_id]) { |queued, more| queued | more }
        end

        # Everything in the Model is an original from here on; a pending pass is dropped.
        def reset
          @work.cancel
        end

        # Undo: drop a pending pass, and say so if it took back a repair but left its copy.
        def undone
          reset
          return if @repaired.empty?

          live = occurrences.to_h { |space| [space.path, space.record.fetch("id")] }
          return if live.empty? # An unreadable Model is no evidence that the copies left; keep them.

          # A copy no longer in the Model has nothing left to warn about; every other repair is kept, so a
          # later Undo of an earlier batch, or another Undo after a Redo, still warns.
          @repaired = @repaired.select { |path, _id| live.key?(path) }
          # Reverted: the copy lost the id it was given and shares one again. A copy the row's command
          # made independent since holds an id of its own and is not a copy.
          held = live.values.tally
          reverted = @repaired.select { |path, id| live.fetch(path) != id && held.fetch(live.fetch(path)) > 1 }
          return if reverted.empty?

          count = reverted.length
          @session.notice("Undo also took back making the #{spaces(count)} independent, because it had joined a " \
                          "later change. Use Make independent on #{count == 1 ? 'its row' : 'their rows'}.",
                          :tone => :warning)
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

        def stored_id(entity)
          record = SPACE_STORE.read(entity)
          record.is_a?(Hash) ? record["id"] : nil
        rescue CodedError
          nil # An unreadable record is the Spaces read's to report, not a copy to repair.
        end

        def ids_inside(entities, found = [])
          entities.each do |entity|
            if entity.is_a?(Sketchup::Group)
              id = stored_id(entity)
              id ? found << id : ids_inside(entity.entities, found)
            elsif entity.is_a?(Sketchup::ComponentInstance)
              ids_inside(entity.definition.entities, found)
            end
          end
          found
        end

        def occurrences
          Occurrences.scan(@session.model).spaces
        rescue CodedError => error
          Diagnostics.log("space_copy_watch", "code" => error.code)
          []
        end

        def copies(added)
          occurrences.group_by { |space| space.record.fetch("id") }.flat_map do |_id, group|
            fresh = group.select { |space| (space.path & added).any? }
            group.length - fresh.length == 1 ? fresh : []
          end
        end

        def run(added)
          # The Zones pass first, so a copied Space follows its copied Zone before it takes that Zone's next number.
          Zones::CopyWatch.state(@session).settle
          zones = zone_paths
          Zones::CopiedGroups.isolate(@session, own_copies(added, zones).map(&:path), added)
          shared, repairable = own_copies(added, zones).partition(&:shared_above)
          announce_shared(shared) unless shared.empty?
          return if repairable.empty?

          result = HostFollowUp.run(@session, ACTION, repairable.map { |space| { "reference" => space.reference } })
          @session.changed(:spaces, :copy_watch) if result.fetch("status") != "refused"
          remember(repairable, result)
          announce(repairable.length, result)
        rescue StandardError => error
          Diagnostics.exception("space_copy_watch", error)
          @session.notice("The copied Space could not be made independent. Use Make independent on its row.",
                          :tone => :warning)
        end

        # The copies this watcher repairs. A Space below a Zone the same gesture copied is that Zone's to
        # repair, in its `occurrence_independent` transition; one copied alone inside a Zone is this watcher's.
        def own_copies(added, zones)
          copies(added).reject do |space|
            zones.any? do |path|
              (path & added).any? && path.length < space.path.length && space.path[0, path.length] == path
            end
          end
        end

        def zone_paths
          Zones::Occurrences.zones(@session.model).map(&:path)
        rescue CodedError => error
          Diagnostics.log("space_copy_watch", "code" => error.code)
          []
        end

        # Each repaired copy's path and the id it took, to tell on Undo whether the copy outlived its repair.
        def remember(repairable, result)
          return unless result.fetch("status") == "completed"

          @repaired = @repaired.merge(repairable.zip(result.fetch("values")).to_h do |space, value|
            [space.path, value.fetch("ids").find { |row| row.fetch("kind") == SPACE_KIND }.fetch("after")]
          end)
        end

        def announce_shared(shared)
          @session.notice("#{spaces(shared.length).sub(/\A./, &:upcase)} inside shared storage, such as a component, " \
                          "#{shared.length == 1 ? 'keeps' : 'keep'} the copy's identity. Draw the Space directly.",
                          :tone => :warning)
        end

        # Each notice says what is true in the Model afterwards; a failure is read back rather than assumed.
        def announce(count, result)
          case result.fetch("status")
          when "completed"
            @session.notice("Made the #{spaces(count)} independent.", :tone => :success)
          when "refused"
            @session.notice("The #{spaces(count)} #{count == 1 ? 'keeps' : 'keep'} the copied identity: " \
                            "#{result.fetch('message')}", :tone => :warning)
          else
            message = if result.fetch("restored")
                        "could not be made independent; #{count == 1 ? 'its' : 'their'} records are as copied. " \
                          "Use Make independent on #{count == 1 ? 'its row' : 'their rows'}."
                      else
                        "failed partway, and not everything written could be put back. Check " \
                          "#{count == 1 ? 'its row' : 'their rows'}."
                      end
            @session.notice("The #{spaces(count)} #{message}", :tone => result.fetch("restored") ? :warning : :error)
          end
        end

        def spaces(count)
          count == 1 ? "copied Space" : "#{count} copied Spaces"
        end
      end
    end
  end
end
