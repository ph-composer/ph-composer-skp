# frozen_string_literal: true

require_relative "handler_request"
require_relative "request_checks"

module PhComposer
  # Runs public queries and operations for every client: the panel, Ruby scripts and, later, external
  # adapters (context/CONTRACTS.md, "Public interface" to "Retries"). It owns the host execution
  # boundary: one mutation at a time per session, validation before any operation opens, one native
  # operation per accepted change, and a verified rollback when that operation fails. Handlers only
  # read and propose.
  class Dispatch
    include RequestChecks

    REQUEST_KEYS = %w[sequence expected_revision proposal_digest].freeze

    def initialize(registry = Registry.current)
      @registry = registry
    end

    def query(context, name, params)
      Refusals.report(@registry.queries[name], answer(context, capability("query"), name, @registry.queries, params))
    end

    # File export has its own grant and never enters a Model mutation. Polling and cancellation
    # use the same explicit session as starting the task, even when another Model is foreground. A
    # start names an approved location; only the native Export workflow passes its own `approval`.
    def export_task(context, operation, arguments)
      session, caller, = resolve(context, "export", nil, nil)
      tasks = Export::Tasks.for(session)
      owner = Export::Tasks::Owner.new(caller.handle, -> { !session.callers.fetch(caller.handle).nil? })
      value = case operation
              when :start then tasks.start(**arguments, :owner => owner)
              when :status then tasks.status(arguments.fetch(:task_id), owner, arguments.fetch(:options, {}))
              when :cancel then tasks.cancel(arguments.fetch(:task_id), owner)
              when :latest then tasks.latest(owner, arguments.fetch(:options, {}))
              else raise InternalError, "Unknown export task operation."
              end
      Outcome.completed(:revision => session.revision, :value => value)
    rescue CodedError => error
      coded_outcome(error, session)
    rescue UserError => error
      Outcome.refused("export.refused", error.message, :revision => session&.revision)
    rescue StandardError => error
      unexpected_outcome(error, session, "export.#{operation}")
    end

    # With `location`, an approved destination's id, the result also says what that destination holds;
    # `options` ask for a bounded form instead of the whole (Export::PreflightView).
    def export_preflight(context, location = nil, options = {})
      session, = resolve(context, "read", nil, nil)
      options = Export::PreflightView.check!(options)
      lists = { "findings" => [], "repairs" => [] }
      @registry.export_contributors.values.sort_by(&:name).each_with_index do |contributor, place|
        next unless contributor.preflight

        outcome = query(context, contributor.preflight, {})
        return outcome unless outcome["status"] == "completed"

        %w[findings repairs].each do |list|
          outcome.dig("value", list).each_with_index do |row, index|
            if list == "repairs" && @registry.actions[row["action"]]&.owner != contributor.owner
              raise InternalError, "Preflight repair needs its owner's public action."
            end

            lists[list] << [[place, index], row.merge("owner" => contributor.owner)]
          end
        end
      end
      value = Export::PreflightView.answer(session, lists, location, options)
      Outcome.completed(:revision => session.revision, :value => DeepCopy.call(value))
    rescue CodedError => error
      coded_outcome(error, session)
    rescue StandardError => error
      unexpected_outcome(error, session, "export.preflight")
    end

    # A change to what the host shows and nothing else (Declarations::ViewCommand). It carries no
    # sequence number and returns no proposal, because there is nothing to retry and nothing to undo.
    # It refuses while the session is busy, as a read does, so it cannot move the camera or the
    # selection out from under an operation that is still running.
    def view(context, name, params)
      declaration = @registry.view_commands[name]
      needed = declaration ? Declarations.capability_of(declaration, "view_command") : capability("view_command")
      Refusals.report(declaration, answer(context, needed, name, @registry.view_commands, params))
    end

    # A change to session or machine state (Declarations::SetupCommand). It runs as a view command
    # does, under its own grant: it carries no sequence number and returns no proposal.
    #
    # `approval` is what a native client obtained from the user for a declaration that needs a
    # location (NativeApproval). The public API never passes one, so a scripted caller of such a
    # declaration is refused before anything runs.
    def setup(context, name, params, approval: nil)
      Refusals.report(@registry.setup_commands[name],
                      answer(context, capability("setup_command"), name, @registry.setup_commands, params,
                             :approval => approval))
    end

    # Registered local-file commands share validation and session targeting with reads. Their
    # separate grant permits file writes, never a Model transaction or an action retry sequence.
    def file_export(context, name, params, approval: nil)
      Refusals.report(@registry.file_exports[name],
                      answer(context, capability("file_export"), name, @registry.file_exports, params,
                             :approval => approval))
    end

    # The refusal `setup` or `file_export` would give before its handler runs (session, grant, params,
    # busy, the declared precondition), or nil when none applies. A native client asks before it opens
    # a dialog, so the user never chooses a location for a call that was going to be refused anyway.
    # Dispatch repeats every check after the dialog, and only that answer is reported for audit.
    def setup_refusal(context, name, params)
      admission_refusal(context, capability("setup_command"), name, @registry.setup_commands, params)
    end

    def file_export_refusal(context, name, params)
      admission_refusal(context, capability("file_export"), name, @registry.file_exports, params)
    end

    # What an operation would change, without changing anything. The result is bound to the revision
    # it reports; applying it later still revalidates everything.
    def preview(context, name, params)
      Refusals.report(@registry.actions[name], proposal_preview(context, name, params))
    end

    # A request whose params are not plain JSON is refused before acceptance. It cannot be digested,
    # so it consumes no sequence and retains no outcome; the caller resends it corrected under the
    # same sequence.
    def invoke(context, name, params, request)
      Refusals.report(@registry.actions[name], mutation(context, name, params, request))
    end

    # The retained outcome of an earlier mutation request, without running it again.
    def outcome(context, request)
      session, caller, = resolve(context, capability("action"), nil, nil)
      sequence = request.is_a?(Hash) ? request["sequence"] : nil
      raise CodedError.new("request.malformed", "The request needs an integer sequence.") unless sequence.is_a?(Integer)

      entry = session.outcomes.lookup(caller.handle, sequence)
      return pending(session) if entry&.pending?
      return session.outcomes.retained(caller.handle, sequence) if entry

      raise CodedError.new("request.outcome_unavailable", "No retained outcome for sequence #{sequence}; " \
                                                          "inspect the Model before issuing new work.")
    rescue CodedError => error
      coded_outcome(error, session)
    end

    private

    def proposal_preview(context, name, params)
      session, _caller, action = resolve(context, Declarations::PREVIEW_CAPABILITY, name, @registry.actions)
      check_params!(action, params, session)
      refuse_if_busy!(session)
      proposal = Operations::Proposal.new
      value = action.handler.call(request_for(session, params, action, proposal), proposal)
      raise proposal.refusal if proposal.refusal

      check_result!(action, value)
      Outcome.completed(:revision => session.revision, :value => value, :affected => proposal.affected,
                        :findings => proposal.findings, :proposal_digest => proposal.digest,
                        :message => "Preview only.")
    rescue UserError => error
      return coded_outcome(error, session) if error.is_a?(CodedError)

      Outcome.refused("validation.failed", error.message, :revision => session&.revision)
    rescue StandardError => error
      unexpected_outcome(error, session, name)
    end

    def mutation(context, name, params, request)
      session, caller, action = resolve(context, capability("action"), name, @registry.actions)
      sequence, expected_revision, proposal_digest = read_request!(request, session)
      check_json!(params, session)
      retained = retained_outcome(session, caller, sequence, name, params, expected_revision, proposal_digest)
      return retained if retained

      # A change also waits while the user is partway through a gesture its commit would cancel, such as a Move;
      # reads do not (ModelSession#gesture_reason).
      refuse_if_busy!(session, session.busy_reason || session.gesture_reason)
      # Digested before the sequence is taken, so anything that cannot be canonicalized still leaves
      # the caller's sequence free.
      digest = request_digest(name, params, expected_revision, proposal_digest)
      caller.highest_sequence = sequence
      session.outcomes.begin(caller.handle, sequence, digest)
      outcome = session.exclusive do
        result = run(session, action, params, expected_revision, proposal_digest)
        session.outcomes.finish(caller.handle, sequence, result)
      end
      # Subscribers may use public queries. Publish only after the request is retained and the
      # mutation lock is released, so those reads see the committed Model rather than session.busy.
      session.changed(:action, action.name) if outcome["effect"] == "committed"
      outcome
    rescue CodedError => error
      coded_outcome(error, session, :mutation => true)
    rescue StandardError => error
      unexpected_outcome(error, session, name)
    end

    # ---------------------------------------------------------------- acceptance

    # A read, a view command and a setup command run the same way: validate, refuse while busy, call the
    # handler, check the result against its declared schema. They differ in the capability they need and in what the
    # handler is allowed to touch, which is the declaration's business rather than this method's.
    def answer(context, capability, name, declarations, params, approval: nil)
      session, _caller, declaration = resolve(context, capability, name, declarations)
      check_params!(declaration, params, session)
      approval, params = NativeApproval.admit(declaration, approval, params)
      refuse_if_busy!(session) unless declaration.respond_to?(:while_busy) && declaration.while_busy
      check_precondition!(session, params, declaration)
      # A call that does not complete, even one whose result fails its schema after writing, keeps the
      # location for a retry.
      request = request_for(session, params, declaration, :approval => approval)
      value = ApprovedLocations.consuming(approval) { check_result!(declaration, declaration.handler.call(request)) }
      Outcome.completed(:revision => session.revision, :value => value)
    rescue CodedError => error
      coded_outcome(error, session)
    rescue UserError => error
      # A handler that refuses what it was asked for says why, as an operation does: "There is no
      # Colour-by mode named ..." is the answer, not a generic failure.
      Outcome.refused("validation.failed", error.message, :revision => session&.revision)
    rescue StandardError => error
      unexpected_outcome(error, session, name)
    end

    def admission_refusal(context, capability, name, declarations, params)
      session, _caller, declaration = resolve(context, capability, name, declarations)
      check_params!(declaration, params, session)
      refuse_if_busy!(session)
      check_precondition!(session, params, declaration)
      nil
    rescue CodedError => error
      coded_outcome(error, session)
    rescue StandardError => error
      unexpected_outcome(error, session, name)
    end

    # The capability dispatch enforces for an operation kind (Declarations::CAPABILITIES).
    def capability(kind)
      Declarations::CAPABILITIES.fetch(kind)
    end

    def resolve(context, capability, name, declarations)
      unless context.is_a?(OperationContext)
        raise CodedError.new("request.malformed", "The context must come from PhComposer::API.connect.")
      end

      unless context.api_major == API::MAJOR
        raise CodedError.new("request.api_version", "This build answers API #{API::MAJOR}, " \
                                                    "not #{context.api_major.inspect}.")
      end

      session = Sessions.find(context.session_id)
      raise CodedError.new("session.unknown", "That Model session is closed or was never opened.") unless session

      caller = session.callers.fetch(context.caller)
      if session.callers.revoked?(context.caller)
        raise CodedError.new("access.revoked", "This caller's access was revoked; nothing ran.")
      end
      raise CodedError.new("session.unknown", "This caller was not connected to that Model session.") unless caller

      declaration = declarations && declarations[name]
      if declarations && !declaration
        raise CodedError.new("request.unknown_operation", "There is no operation named #{name.inspect}.")
      end
      unless caller.capabilities.include?(capability)
        raise CodedError.new("request.capability_denied", "This caller was not granted #{capability} access.")
      end

      [session, caller, declaration]
    end

    def read_request!(request, session)
      unless request.is_a?(Hash) && (request.keys - REQUEST_KEYS).empty?
        raise CodedError.new("request.malformed", "The request may hold only #{REQUEST_KEYS.join(' and ')}.")
      end

      sequence = request["sequence"]
      expected_revision = request["expected_revision"]
      unless sequence.is_a?(Integer) && sequence.positive? && expected_revision.is_a?(Integer)
        raise CodedError.new("request.malformed", "The request needs a positive integer sequence and an " \
                                                  "integer expected_revision.", "revision" => session.revision)
      end

      proposal_digest = request["proposal_digest"]
      unless proposal_digest.nil? || proposal_digest.is_a?(String)
        raise CodedError.new("request.malformed", "proposal_digest must be a string when supplied.")
      end

      [sequence, expected_revision, proposal_digest]
    end

    # A sequence at or below the caller's highest accepted one is a retry, never new work. The payload
    # is compared first, so a different request under a running sequence conflicts rather than reading
    # as the one still running.
    def retained_outcome(session, caller, sequence, name, params, expected_revision, proposal_digest)
      entry = session.outcomes.lookup(caller.handle, sequence)
      if entry
        if entry.digest == request_digest(name, params, expected_revision, proposal_digest)
          return entry.pending? ? pending(session) : session.outcomes.retained(caller.handle, sequence)
        end

        raise CodedError.new("request.sequence_conflict", "Sequence #{sequence} was already used for a different " \
                                                          "request.")
      end
      return nil if sequence > caller.highest_sequence

      raise CodedError.new("request.outcome_unavailable", "Sequence #{sequence} was already used and its outcome " \
                                                          "has expired; inspect the Model before issuing new work.")
    end

    def request_digest(name, params, expected_revision, proposal_digest = nil)
      CanonicalJson.digest("name" => name, "params" => params, "expected_revision" => expected_revision,
                           "proposal_digest" => proposal_digest)
    end

    def pending(session)
      Outcome.refused("request.pending", "That request is still running.", :status => "pending",
                                                                           :revision => session.revision)
    end

    def refuse_if_busy!(session, reason = session.busy_reason)
      raise CodedError.new("session.busy", reason, "reason" => reason) if reason
    end

    # A declared precondition sees the validated params, never the approval, so it can run before a
    # native client opens a dialog as well as before the handler.
    def check_precondition!(session, params, declaration)
      return unless declaration.respond_to?(:precondition) && declaration.precondition

      declaration.precondition.call(request_for(session, params, declaration))
    end

    # `value`, once it is within the declared result schema.
    def check_result!(declaration, value)
      findings = JsonSchema.validate(value, declaration.result)
      return value if findings.empty? && JsonValue.problems(value).empty?

      raise InternalError, "#{declaration.name} returned a result outside its schema: #{findings.first}"
    end

    # ---------------------------------------------------------------- the mutation

    def run(session, action, params, expected_revision, expected_proposal_digest)
      check_params!(action, params, session)
      if expected_revision != session.revision
        raise CodedError.new("revision.stale", "The Model has changed since revision #{expected_revision}; it is " \
                                               "now #{session.revision}.", "revision" => session.revision)
      end

      proposal = Operations::Proposal.new
      request = request_for(session, params, action, proposal)
      value = action.handler.call(request, proposal)
      # A handler that rescued a refusal still proposed an incomplete change; it is refused whole.
      raise proposal.refusal if proposal.refusal

      check_result!(action, value)
      if expected_proposal_digest && expected_proposal_digest != proposal.digest
        raise CodedError.new("proposal.changed", "The proposed change no longer matches the preview.")
      end

      if proposal.empty?
        # Nothing to write is not nothing to say. A handler that only had findings, such as a Solve
        # whose every candidate was a sliver, still has to hand them back.
        return Outcome.completed(:revision => session.revision, :value => value,
                                 :findings => proposal.findings, :message => "Nothing to change.")
      end

      proposal.run_commit_checks!
      commit(session, action, request.engine, proposal, value)
    rescue CodedError => error
      coded_outcome(error, session, :mutation => true)
    rescue UserError => error
      Outcome.refused("validation.failed", error.message, :revision => session.revision, :mutation => true)
    rescue StandardError => error
      incident = Diagnostics.incident("operation_failed", error, "operation" => action.name,
                                                                 "code" => "operation.failed", "effect" => "none")
      Outcome.refused("operation.failed", "The change could not be prepared.",
                      :status => "failed", :mutation => true, :revision => session.revision,
                      :detail => Outcome.failure_detail(incident, error))
      # `failed` with effect `none`: the error came before any operation opened.
    end

    def commit(session, action, engine, proposal, value)
      proposal.capture(session.model)
      session.mutate do
        ModelOperation.perform(session.model, action.undo_name) { proposal.apply(session.model, engine) }
        true
      end
      # The message names what completed, by the same words the Undo menu shows, so a confirmation reads
      # "Done: Make Zone." rather than a bare "Done.".
      Outcome.completed(:revision => session.revision, :value => value, :effect => "committed",
                        :affected => proposal.affected, :findings => proposal.findings,
                        :proposal_digest => proposal.digest, :message => "Done: #{action.undo_name}.")
    rescue StandardError => error
      effect = verified_unchanged?(session.model, engine, proposal) ? "rolled_back" : "unknown"
      reason = error.is_a?(CodedError) ? error : nil
      incident = Diagnostics.incident("operation_failed", error, "operation" => action.name, "effect" => effect,
                                                                 "code" => reason&.code || "operation.failed")
      Outcome.failed(:effect => effect, :revision => session.revision, :reason => reason, :incident => incident,
                     :error => error)
    end

    def verified_unchanged?(model, engine, proposal)
      proposal.unchanged?(model, engine)
    rescue StandardError
      false
    end

    # A read or a view command that failed unexpectedly (a handler bug, a result outside its schema)
    # answers every client with the same failed outcome; the error goes to the log. Neither opens an
    # operation, so `effect` is "none": the Model is unchanged. A view command may still have moved the
    # viewport part-way, which is why a client re-reads what it shows rather than assuming.
    def unexpected_outcome(error, session, name)
      incident = Diagnostics.incident("operation_failed", error, "operation" => name, "code" => "operation.failed",
                                                                 "effect" => "none")
      Outcome.refused("operation.failed", "The request could not be answered.",
                      :status => "failed", :revision => session&.revision,
                      :detail => Outcome.failure_detail(incident, error))
    end

    def coded_outcome(error, session, mutation: false)
      revision = session&.revision || (error.detail.is_a?(Hash) ? error.detail["revision"] : nil)
      status = { "session.busy" => "busy", "request.pending" => "pending" }.fetch(error.code, "refused")
      findings = error.detail.is_a?(Hash) ? Array(error.detail["findings"]) : []
      Outcome.refused(error.code, error.message, :status => status, :revision => revision,
                                                 :mutation => mutation, :findings => findings, :detail => error.detail)
    end
  end
end
