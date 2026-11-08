# frozen_string_literal: true

require_relative "return_to_host"

module PhComposer
  module Windows
    module Units
      # A Window pasted or moved off its Face goes back to the nearest Face of its Zone, joined to the
      # user's gesture so one Undo takes back both. One that cannot says so in SketchUp and keeps its
      # finding. The reconciler follows "Observers report; deferred work mutates" (context/TECH_STACK.md).
      #
      # A paste reports its addition after the commit, so an addition queues the pass. A Move reports the
      # instance before the commit (measured with a Ruby transform; native Move is not measured), so a change
      # is only remembered and the commit queues it: nothing runs while a gesture is still open.
      #
      # An Undo or Redo reports the same changes before its own event, and drops them: a state Undo brought
      # back is the user's, and a write now would clear Redo. PH-Composer's own operations are ignored.
      # Units already in the Model when it opens are left to their findings, since nothing moved them.
      module HostWatch
        ACTION = "#{FEATURE_ID}.units.return_to_host"

        module_function

        def state(session)
          session.feature_state(:windows_host_watch) { State.new(session) }
        end

        def install(feature)
          feature.on_host_event(:container_added) { |session, entity| state(session).added(entity) }
          feature.on_host_event(:instance_modified) { |session, entity| state(session).modified(entity) }
          feature.on_host_event(:transaction_committed) { |session| state(session).committed }
          feature.on_host_event(:transaction_undone) { |session| state(session).reset }
          feature.on_host_event(:transaction_redone) { |session| state(session).reset }
        end

        class State
          def initialize(session)
            @session = session
            @work = DeferredWork.new { |jobs| run(jobs.fetch(:units)) }
            @moved = []
            @running = false
          end

          def added(entity)
            queue([entity.persistent_id]) if watched?(entity)
          rescue StandardError => error
            log(error)
          end

          def modified(entity)
            @moved |= [entity.persistent_id] if watched?(entity)
          rescue StandardError => error
            log(error)
          end

          def committed
            return if @moved.empty? || @running

            moved = @moved
            @moved = []
            queue(moved)
          end

          def reset
            @moved = []
            @work.cancel unless @running
          end

          def pending?
            @work.pending?
          end

          def settle
            @work.settle
          end

          def detach
            @work.detach
            @moved = []
          end

          private

          def queue(ids)
            @work.queue(:units, ids) { |queued, more| queued | more }
          end

          def watched?(entity)
            return false if @running || @session.mutating?

            entity.is_a?(Sketchup::ComponentInstance) && !Units.read(entity).nil?
          rescue CodedError
            false # An unreadable record is the Unit read's to report.
          end

          # One run per Window, so each lands clear of the one before and one that cannot does not hold
          # back the others.
          def run(ids)
            @running = true
            references = Occurrences.all(@session.model).select { |item| ids.include?(item.path.last) }.map(&:reference)
            outcomes = references.map { |unit| return_unit(unit) }
            @session.changed(:windows, :host_watch) if outcomes.any? { |outcome| outcome.fetch("status") != "refused" }
            announce(outcomes)
          rescue CodedError => error
            Diagnostics.log("window_host_watch", "code" => error.code)
          rescue StandardError => error
            Diagnostics.exception("window_host_watch", error)
            HostNotice.show(@session, "PH-Composer could not check a moved Window. See its row in the Schedule.")
          ensure
            @running = false
          end

          # HostFollowUp answers a refusal; anything else is this Window's own and must not hold back the others.
          def return_unit(unit)
            HostFollowUp.run(@session, ACTION, [{ "unit" => unit }])
          rescue StandardError => error
            Diagnostics.exception("window_host_watch", error)
            { "status" => "failed", "message" => "PH-Composer could not return it." }
          end

          def announce(outcomes)
            returned = outcomes.count { |outcome| outcome.dig("values", 0, "returned") }
            HostNotice.show(@session, returned_words(returned), :tone => :info) if returned.positive?
            outcomes.reject { |outcome| outcome.fetch("status") == "completed" }.each do |outcome|
              HostNotice.show(@session, "A Window is off its Face and stays there: #{outcome.fetch('message')} " \
                                        "Undo, or use its row in the Schedule.")
            end
          end

          def returned_words(count)
            windows = count == 1 ? "Window" : "#{count} Windows"
            "#{windows} left #{count == 1 ? 'its Face and went' : 'their Faces and went'} back to the nearest Face " \
              "of the Zone. Undo takes this back with the move."
          end

          def log(error)
            Diagnostics.exception("window_host_watch_event", error) unless ContainerWatch.deleted_reference?(error)
          end
        end
      end
    end
  end
end
