# frozen_string_literal: true

module PhComposer
  module Export
    # Bounded process-local handles. File recovery does not depend on this in-memory task history.
    # A task belongs to the caller that started it: only that caller polls, cancels or finds it as its
    # latest, so through the agent connection a task is its token's (context/AGENT_INTERFACE.md,
    # "Locations only the user can choose").
    class Tasks
      LIMIT = 20
      RETENTION_SECONDS = 30 * 60
      # The caller handle that started a task, and whether that caller's access is still live, which the
      # task asks before it writes. Export code names no token.
      Owner = Struct.new(:handle, :live)
      FOREIGN = "Another caller started that export; only it can poll or cancel it."

      def self.for(session)
        session.feature_state("#{EXTENSION_ID}.export.tasks") { new(session) }
      end

      def initialize(session)
        @session = session
        @tasks = {}
      end

      # The destination is an approved `location` param, or the native Export workflow's own `approval`,
      # a NativeApproval::Granted (Task). A destination the pair would refuse is refused here, before any
      # task exists, whichever route chose it.
      def start(owner:, location: nil, approval: nil, runtime_factory: nil)
        approval ||= ApprovedLocations.grant_param(location, "save_file")
        prune
        if @tasks.values.any? { |task| !task.terminal? }
          raise Blocked.new("export.busy", "An export is already running for this Model.")
        end
        if (problem = ArtifactPair.destination_problem(approval.path))
          raise Blocked.new("export.refused", problem)
        end
        if @session.busy_reason
          raise Blocked.new("session.busy", @session.busy_reason)
        end

        task = Task.new(@session, :approval => approval, :runtime_factory => runtime_factory, :owner => owner)
        task.start
        @tasks[task.id] = task
        task.snapshot(owner)
      end

      # The task's snapshot, compact on request, or with `part` one part of what it kept when it ended
      # (Task#diagnostic), its cursors bound to this task alone, so a later edit of the Model expires none.
      TASK_PARTS = { "findings" => %w[codes blocks_export object_id], "report" => [], "result" => [],
                     "outcome" => [] }.freeze

      def status(id, owner, options = {})
        options = TaskContract.check_options!("export_status", options)
        task = fetch(id, owner)
        DiagnosticPages.check!(options, TASK_PARTS)
        part = options["part"]
        return task.snapshot(owner, :compact => options["compact"]) unless part
        if part != "findings" && !(options.keys & %w[row limit]).empty?
          raise CodedError.new("params.invalid", "The #{part} part is read in fragments; it takes a cursor only.")
        end

        request = DiagnosticPages::Request.new(:session => @session, :params => options.merge("task_id" => id),
                                               :revision => id)
        { "task_id" => id, "source" => task.source, "part" => part }.merge(task.diagnostic(request, part))
      end

      def cancel(id, owner)
        task = fetch(id, owner)
        task.cancel
        task.snapshot(owner)
      end

      def latest(owner, options = {})
        compact = TaskContract.check_options!("latest_export", options)["compact"]
        prune
        @tasks.values.reverse.find { |task| task.owner.handle == owner.handle }&.snapshot(owner, :compact => compact)
      end

      # The tasks `handle` started, for the acknowledgment of a revoked token: those that completed and
      # those its revocation stopped.
      def owned_by(handle)
        prune
        @tasks.values.select { |task| task.owner.handle == handle }
      end

      def detach
        @tasks.each_value(&:cancel)
        @tasks.clear
      end

      private

      def fetch(id, owner)
        prune
        task = @tasks.fetch(id) do
          raise Blocked.new("task.expired", "That export handle expired or belongs to another Model session.")
        end
        raise Blocked.new("task.foreign", FOREIGN) unless task.owner.handle == owner.handle

        task
      end

      def prune
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @tasks.delete_if { |_id, task| task.finished_at && now - task.finished_at > RETENTION_SECONDS }
        finished = @tasks.select { |_id, task| task.terminal? }.keys
        finished[0, [finished.length - LIMIT, 0].max].each { |id| @tasks.delete(id) }
      end
    end
  end
end
