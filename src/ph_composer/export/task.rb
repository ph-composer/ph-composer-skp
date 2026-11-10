# frozen_string_literal: true

require "securerandom"
require_relative "privacy"

module PhComposer
  module Export
    # One read-only export, owned by its Model session rather than by a panel or caller connection.
    # Timer boundaries admit cancellation and recheck content generation; Python returns asynchronously.
    class Task
      PAIR_FAILED = "The HBJSON and Export report could not be written. The destination was left as it was."
      # Ruby's own bound on a silent runtime, so a page that never answers still ends the run (REVIEW F05).
      # Startup waits out the page's own boot deadline plus this grace; once the page is ready, a translation
      # waits TRANSLATION_SILENCE_SECONDS. Starting defaults, to be measured on the proving host.
      STARTUP_GRACE_SECONDS = 15
      TRANSLATION_SILENCE_SECONDS = 300
      NOT_STARTED = "The export runtime did not start in time, so the export was stopped. No files were written."
      # A runtime failure keeps its own code when it is one the runtime declares; its message stays fixed.
      RUNTIME_FAILURES = {
        "runtime.asset_refused" => "The export runtime could not start. No files were written.",
        "runtime.boot_failed" => "The export runtime could not start. No files were written.",
        "runtime.boot_timeout" => "The export runtime could not start. No files were written.",
        "runtime.conformance_failed" => "The export runtime could not check this Model's HBJSON. No files were written."
      }.freeze
      TRANSLATION_FAILED = "The export runtime could not translate this Model."
      UNRESPONSIVE = "The export runtime stopped responding, so the export was stopped. No files were written."
      FINDING_FIELDS = Privacy::SHELL.fetch("findings").first.keys.freeze

      attr_reader :id, :finished_at, :owner

      # `approval` is the NativeApproval::Granted for the destination: from the native Save sheet, or
      # resolved from an approved location, whose id and label the completed outcome names instead of
      # a path.
      def initialize(session, approval:, owner:, runtime_factory: nil)
        @session = session
        @owner = owner
        @id = "export_#{SecureRandom.hex(12)}"
        @destination = File.expand_path(approval.path)
        @location = approval.location_id && { "id" => approval.location_id, "label" => approval.label }
        @pair = ArtifactPair::Transaction.new(@destination, :run_id => id)
        pair_step { @pair.recover }
        @prior = ArtifactPair.state(@destination)
        consent!(approval) if @prior
        @runtime_factory = runtime_factory || ->(&callback) {
          RuntimeHost.new(:session_id => session.id,
                          :on_message => callback)
        }
        @timer = CoalescedTimer.new
        @retained = RunDiagnostics.new
        @stage = "queued"
        @count = 0
        @units = Preferences.snapshot.fetch("unit_system")
        # The request that started the run, carried into every later timer and runtime callback's log lines.
        @trace = Diagnostics.current_context.merge("run_id" => @id)
      end

      def start
        @session.settle
        @generation = @session.export_generation
        @source_revision = @session.revision
        @builder = Collection::Builder.new(@session.model, :run_id => id)
        @watchdog = UI.start_timer(0.2, true) { traced { watch } }
        schedule
        self
      rescue StandardError => error
        failed(error)
        self
      end

      def terminal?
        !@outcome.nil?
      end

      # `asker`, the Tasks::Owner polling, sees where the committed pair is and what it hashes to only when
      # it started the task (context/AGENT_INTERFACE.md, "Locations only the user can choose"). Every snapshot
      # names the source the run read (`source`) and, once it ended, what it kept (`diagnostics`); `compact`
      # leaves the findings, the result and the report out of the outcome for `diagnostic` to read.
      def snapshot(asker = nil, compact: false)
        outcome = @outcome
        if @artifacts && asker && asker.handle == @owner.handle
          outcome = outcome.merge("value" => outcome.fetch("value").merge("artifacts" => @artifacts))
        end
        outcome = compact_outcome(outcome) if compact && outcome
        DeepCopy.call("task_id" => id, "stage" => @stage, "count" => @count,
                      "cancellable" => !terminal? && @stage != "writing",
                      "source" => source, "diagnostics" => @diagnostics, "outcome" => outcome)
      end

      # The whole outcome as its owner polls it, in fragments: a failure message of any length is read here.
      def outcome_part(request)
        fragment, next_cursor = Fragments.read(request, "export_status.outcome", snapshot(@owner).fetch("outcome"))
        { "fragment" => fragment, "next_cursor" => next_cursor }
      end

      # The Model revision and content generation the run read, captured when it started.
      def source
        { "revision" => @source_revision, "export_generation" => @generation }
      end

      # One part of what the run kept when it ended, read for `request` (Export::DiagnosticPages::Request),
      # never from the Model and never by translating again: a page of its findings, one finding whole
      # (`row`), or the generated report or compact result as fragments.
      def diagnostic(request, part)
        raise Blocked.new("task.running", "That export has not finished; poll export_status.") unless terminal?
        return outcome_part(request) if part == "outcome"

        @retained.read(request, part)
      end

      def cancel
        return false if terminal? || @stage == "writing"

        finish(Outcome.build("cancelled", "export.cancelled", Workflow::CANCELLED, "none", @session.revision))
        true
      end

      private

      def schedule
        @timer.schedule { traced { tick } }
      end

      def tick
        return if terminal?

        coherent!
        @stage = "reading"
        # Read at the revision the run exports, so the report carries the warnings the preflight showed.
        @warnings ||= Export.preflight_warnings(@session)
        if @builder.advance
          @extraction = @builder.extraction
          @builder = nil
          @stage = "translating"
          @waiting_since = now
          @runtime = @runtime_factory.call { |type, payload| traced { received(type, payload) } }
          @runtime.start
          @runtime.translate(id, @extraction.document)
        else
          @count = @builder.count
          schedule
        end
      rescue StandardError => error
        failed(error)
      end

      def received(type, payload)
        return if terminal?
        if type == "runtime.closed"
          return failed(Blocked.new("runtime.closed", "The export runtime closed before the run finished."))
        end
        return ready if type == "runtime.ready"
        return unless type == "runtime.translation" && payload["request_id"] == id

        coherent!
        runtime_failed!(payload["error"]) if payload["error"]

        @stage = "checking"
        result = payload.fetch("result")
        raise InternalError, "The runtime returned another run." unless result["run_id"] == id

        result.fetch("findings").concat(@extraction.findings.map { |note| note.merge("blocks_export" => false) })
        passed = passed_user_data(result.dig("canonical_model", "hbjson"))
        result.fetch("findings") << passed if passed
        result.fetch("findings").concat(unreported(@warnings, result.fetch("findings")))
        result.fetch("summary")["findings"] = result.fetch("findings").length
        result["state"] = "complete_with_findings" if result["state"] == "complete" && !result["findings"].empty?
        Privacy.validate!(result)
        @retained.translated(result.fetch("findings"), compact_result(result))
        unless result.dig("summary", "publishable") && result.dig("canonical_model", "hbjson")
          value = { "result" => compact_result(result) }.merge(blocked_report(result))
          @retained.report = value["report_html"]
          return finish(Outcome.build("refused", "export.blocked", "Export not created. Resolve the blocking findings.",
                                      "none", @session.revision, :findings => result.fetch("findings"),
                                                                 :value => value))
        end
        @result = result
        # Writing is a separate tick, so cancellation and queued host mutations are admitted after Python.
        @timer.schedule { traced { commit } }
      rescue StandardError => error
        failed(error)
      end

      def commit
        return if terminal?

        coherent!
        if ArtifactPair.state(@destination) != @prior
          raise Blocked.new("export.destination_changed",
                            "The destination pair changed during export. Choose it again.")
        end
        html = Report.render(@result, :display_units => @units)
        @retained.report = html
        coherent!
        return revoked unless still_permitted?

        @stage = "writing"
        written = pair_step { @pair.commit(@result.fetch("canonical_model").fetch("hbjson"), html) }
        @artifacts = artifacts(written)
        ApprovedLocations.mark_used(@location.fetch("id")) if @location
        value = { "result" => compact_result(@result) }
        value["location"] = @location if @location
        finish(Outcome.build("completed", "export.complete", "HBJSON and Export report created.", "none",
                             @session.revision, :value => value))
      rescue StandardError => error
        failed(error)
      end

      # Status carries counts and diagnostics. Canonical bytes are retrieved explicitly from files,
      # never serialized into every status response or retained once the pair has committed.
      # A blocked run writes no pair, so its report, labelled as from a run that wrote no model, travels in the
      # refused outcome for the panel to show, rendered without the canonical model so no HBJSON travels
      # with it (context/CONTRACTS.md, "Translation sections and artifacts"). A report that cannot render
      # leaves the refusal as it was rather than turning it into a failure.
      def blocked_report(result)
        shown = compact_result(result).tap { |document| document.delete("canonical_model") }
        { "report_html" => Report.render(shown, :display_units => @units, :published => false) }
      rescue StandardError => error
        Diagnostics.exception("export_blocked_report", error)
        {}
      end

      def compact_result(document)
        result = DeepCopy.call(document)
        result["canonical_model"]&.delete("hbjson")
        result
      end

      def coherent!
        raise Blocked.new("session.closed", "The Model closed before export finished.") unless @session.valid?
        if @session.export_generation != @generation
          raise Blocked.new("export.model_changed", "The Model content changed during export. Start again.")
        end
      end

      def watch
        # Reading the sessions detaches a closed Model's session, and detaching cancels this task.
        Sessions.find(@session.id)
        return if terminal?

        coherent!
        responsive! if @stage == "translating"
      rescue StandardError => error
        failed(error) unless terminal?
      end

      # The log keeps where the runtime stopped, its own code and its frames; the user reads a fixed sentence.
      def traced(&block)
        Diagnostics.with_context(@trace, &block)
      end

      def runtime_failed!(error)
        error = error.is_a?(Hash) ? error : {}
        Diagnostics.log("export_runtime_failed", {
          "severity" => "error", "run_id" => id
        }.merge(Diagnostics.accepted(error.slice("stage", "code", "error_class", "frames"))))
        code = RUNTIME_FAILURES.key?(error["code"]) ? error["code"] : "runtime.translation_failed"
        raise Blocked.new(code, RUNTIME_FAILURES.fetch(code, TRANSLATION_FAILED))
      end

      # The translation clock starts when the page is ready, not when it was asked to load.
      def ready
        @ready = true
        @waiting_since = now
      end

      # A silent runtime cannot report itself, so the deadline that ends the run is logged here.
      def responsive!
        if @ready
          return if now - @waiting_since <= TRANSLATION_SILENCE_SECONDS

          silent!("translation", "runtime.unresponsive", UNRESPONSIVE)
        end
        return if now - @waiting_since <= (RuntimeGate.fetch("boot_deadline_ms") / 1000.0) + STARTUP_GRACE_SECONDS

        silent!("boot", "runtime.boot_timeout", NOT_STARTED)
      end

      def silent!(stage, code, message)
        Diagnostics.log("export_runtime_failed", "severity" => "error", "status" => "failed", "stage" => stage,
                                                 "code" => code)
        raise Blocked.new(code, message)
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # A pair error can carry the filesystem's own message, which names the destination; the outcome
      # says what failed in fixed words and the log keeps the error class. Half a prior pair keeps its
      # own fixed message, since the user must act on it.
      def pair_step
        yield
      rescue ArtifactPair::IncompletePriorPairError
        raise
      rescue ArtifactPair::PairError => error
        Diagnostics.exception("export_pair", error)
        raise Blocked.new("export.failed", PAIR_FAILED), :cause => nil
      end

      # Replacing a pair needs consent. The native Save sheet gives it against the pair as it is now; an
      # approved location gives it against the state export_preflight reported.
      def consent!(approval)
        unless approval.replace
          raise Blocked.new("export.replace_required", "Confirm replacement of the existing HBJSON/report pair.")
        end
        return unless approval.location_id

        unless approval.state
          raise Blocked.new("export.replace_required", "Replacing the pair at an approved location needs the " \
                                                       "expected_destination export_preflight reported.")
        end
        return if approval.state == @prior

        raise Blocked.new("export.destination_changed", "The destination pair changed after review. Preflight again.")
      end

      # Where the committed pair is and what its bytes hash to, kept for the caller that started the task.
      def artifacts(written)
        { "run_id" => id, "source_revision" => @source_revision, "export_generation" => @generation,
          "location" => @location,
          "hbjson" => { "path" => written.hbjson_path }.merge(written.files.fetch("hbjson")),
          "report" => { "path" => written.report_path }.merge(written.files.fetch("report")) }
      end

      # Immediately before the pair is written, the access that started the task and the approved location
      # it named are checked again: a revocation acknowledged before this point writes nothing.
      def still_permitted?
        return false unless @owner.live.call
        return true unless @location

        File.expand_path(ApprovedLocations.resolve(@location.fetch("id"), :kind => "save_file")) == @destination
      rescue CodedError => error
        @revocation = error
        false
      end

      def revoked
        error = @revocation
        code, message = if error
                          [error.code, error.message]
                        else
                          ["export.revoked", "The access that started this export was revoked before it wrote " \
                                             "anything. No files were written."]
                        end
        finish(Outcome.build("refused", code, message, "none", @session.revision))
      end

      def failed(error)
        Diagnostics.exception("export_task", error) unless error.is_a?(UserError)
        code = error.is_a?(CodedError) ? error.code : "export.failed"
        message = error.is_a?(UserError) ? error.message : "Export could not finish. No new pair was created."
        finish(Outcome.build("failed", code, message, "none", @session.revision))
      end

      def finish(outcome)
        @outcome = outcome
        @diagnostics = @retained.summary
        @finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @stage = "finished"
        @timer.cancel
        CoalescedTimer.stop(@watchdog)
        @watchdog = nil
        @runtime&.stop
        @runtime = @builder = @extraction = @result = @warnings = nil
        @session.request_refresh if @session.valid?
      end

      # The outcome without what `diagnostic` reads a part at a time, its message cut as a page row's is; the
      # `outcome` part reads it whole.
      def compact_outcome(outcome)
        value = outcome["value"]
        value = value.reject { |key, _value| %w[result report_html].include?(key) } if value.is_a?(Hash)
        compact = outcome.reject { |key, _value| key == "findings" }.merge("value" => value)
        message = outcome["message"].to_s
        return compact if message.length <= DiagnosticPages::MAX_MESSAGE

        compact.merge("message" => message[0, DiagnosticPages::MAX_MESSAGE], "truncated" => ["message"])
      end

      # The preflight warnings no finding in `findings` already reports by code and object, once each, in
      # the result's finding fields. A contributor's note and its preflight row for one condition share
      # both, as do a preflight's repeated rows for one object, so each condition is listed once.
      def unreported(warnings, findings)
        key = ->(finding) { finding.values_at("code", "object_id") }
        reported = findings.map(&key)
        warnings.reject { |warning| reported.include?(key.call(warning)) }.uniq(&key)
                .map { |warning| warning.slice(*FINDING_FIELDS) }
      end

      # One finding counting the HBJSON objects that carry a user's passed-through user_data, or nil.
      def passed_user_data(hbjson)
        return nil unless hbjson.is_a?(String)

        counts = HbjsonMetadata.passed(hbjson, Privacy.user_data_keys)
        return nil if counts.empty?

        listed = counts.sort.map { |type, count| "#{count} #{type}#{count == 1 ? '' : 's'}" }.join(", ")
        { "code" => "export.user_data_passed", "section" => "canonical_model", "object_id" => nil,
          "message" => "User data passed through to the HBJSON on #{listed}.", "blocks_export" => false }
      end
    end
  end
end
