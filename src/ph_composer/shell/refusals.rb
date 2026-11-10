# frozen_string_literal: true

require_relative "../library/refuses"

module PhComposer
  # What an operation can refuse with (context/CONTRACTS.md, "Outcomes and codes"). Each operation
  # declares `refuses`, the codes its handler and the dependencies it calls can answer with an outcome
  # that is not `completed`. COMMON holds the codes dispatch answers for every operation of a kind,
  # whatever its handler does, so no operation repeats them. An operation that declares an `approval`
  # also answers the "approval" set, and the "location" set when an approved location may answer it.
  # `discover` publishes the sets once and `describe` names the sets one operation answers.
  module Refusals
    ANY_OPERATION = %w[request.malformed request.api_version request.capability_denied session.unknown session.busy
                       params.invalid operation.failed].freeze
    COMMON = {
      "query" => ANY_OPERATION,
      "action" => (ANY_OPERATION + %w[request.pending request.sequence_conflict request.outcome_unavailable
                                      revision.stale proposal.changed operation.rollback_unverified]).freeze,
      "view_command" => ANY_OPERATION,
      "setup_command" => ANY_OPERATION,
      "file_export" => ANY_OPERATION,
      # What the foundation's invocation answers for any participant (shell/participant_invocation.rb).
      "participant" => (ANY_OPERATION + %w[operation.proposal_required operation.participant_cycle
                                           proposal.foreign_write proposal.contribution_replaced]).freeze,
      "approval" => %w[access.user_required request.cancelled].freeze,
      "location" => %w[location.unknown location.revoked location.used location.kind_mismatch location.unavailable
                       location.setup_unreadable location.setup_unavailable].freeze
    }.freeze
    # What each COMMON code means, in one line, so a client with only the connection can plan recovery;
    # context/CONTRACTS.md, "Outcomes and codes", is the authority these follow. Discovery publishes them
    # with the sets; `describe`'s `refuses` rows keep a null description for every foundation code.
    MEANINGS = {
      "request.malformed" => "The request envelope or its arguments are not well formed; nothing ran.",
      "request.api_version" => "The request names an API major version this build does not serve.",
      "request.capability_denied" => "The caller's grant does not include the capability the operation needs.",
      "session.unknown" => "The Model session is closed, was reopened or was never opened; discover again.",
      "session.busy" => "Another change is running or deferred work is settling; read context and retry later.",
      "params.invalid" => "The params do not meet the operation's params schema or a rule it states.",
      "operation.failed" => "An unexpected error; the outcome's effect says whether anything was kept.",
      "request.pending" => "A retry of a request that is still running; ask for its outcome later.",
      "request.sequence_conflict" => "This sequence or key was already used for a different change.",
      "request.outcome_unavailable" => "The outcome is too old to know; read the Model before acting again.",
      "revision.stale" => "The Model changed after expected_revision; read again and decide again.",
      "proposal.changed" => "The change is no longer the one the preview's proposal_digest described.",
      "operation.rollback_unverified" => "An abort ran but the unchanged-data check failed or could not run.",
      "operation.proposal_required" => "A participant was called outside an action's proposal.",
      "operation.participant_cycle" => "A participant was asked to call itself, directly or through another.",
      "proposal.foreign_write" => "A participant or library callback staged a write to a kind its owner does not own.",
      "proposal.contribution_replaced" => "A contributor removed or changed what an earlier one proposed.",
      "access.user_required" => "The operation needs a location only the user can choose; ask the user to approve one.",
      "request.cancelled" => "The user dismissed the dialog that would have approved the request.",
      "location.unknown" => "No approved location has that id.",
      "location.revoked" => "The user revoked that approved location.",
      "location.used" => "That single-use location already added its library.",
      "location.kind_mismatch" => "That approved location is for another kind of file or folder.",
      "location.unavailable" => "That approved location is no longer there as approved.",
      "location.setup_unreadable" => "This machine's stored location setup cannot be read.",
      "location.setup_unavailable" => "This machine's location setup could not be read or saved."
    }.freeze
    # Codes no handler raises: an unknown name never reaches one, and only dispatch or a native client
    # answers for an approval. An operation's `refuses` never lists them.
    DISPATCH_ONLY = (%w[request.unknown_operation] + COMMON.fetch("approval")).freeze

    class << self
      # A callable receiving `(declaration, code)` for every outcome of a registered operation that is
      # not `completed`. Nil in production; the offline suite installs one that fails a test whose
      # operation answers a code outside its `refuses` and common sets.
      attr_accessor :audit
    end

    module_function

    # Hands `outcome` to the audit when it is a registered operation's refusal, and returns it.
    def report(declaration, outcome)
      audit&.call(declaration, outcome["code"]) if declaration && outcome && outcome["status"] != "completed"
      outcome
    end

    # Discovery, generated references and the offline audit use this one projection: the operation's
    # own codes, the installed library callback codes it runs, and everything every participant it
    # names can answer (its own codes and the `participant` set), through their own `participants`.
    # The library service contributes its callback codes without naming any receiving feature.
    def declared(declaration, registry = Registry.current)
      effective(declaration, registry, [declaration.name]).uniq - common(declaration)
    end

    def effective(declaration, registry, seen)
      codes = declaration.refuses + Library::Refuses.callback_codes(registry, declaration.name) +
              transition_codes(declaration, registry)
      Array(declaration.respond_to?(:participants) ? declaration.participants : nil).each do |name|
        participant = registry.proposal_participants[name]
        next if participant.nil? || seen.include?(name)

        codes += effective(participant, registry, seen + [name]) + COMMON.fetch("participant")
      end
      codes
    end
    private_class_method :effective

    # What the contributors to the transitions an action declares can answer, and the guard codes
    # contribution itself gives (HandlerRequest#contribute_transition).
    def transition_codes(declaration, registry)
      transitions = Array(declaration.respond_to?(:transitions) ? declaration.transitions : nil)
      return [] if transitions.empty?

      registry.transition_contributors.values.select { |item| transitions.include?(item.transition) }
              .flat_map(&:refuses) + %w[proposal.foreign_write proposal.contribution_replaced]
    end
    private_class_method :transition_codes

    # The names of the COMMON sets one operation answers. A participant answers what any operation
    # does; the action that calls it adds its own set.
    def common_sets(declaration)
      return ["participant"] if declaration.is_a?(Declarations::ProposalParticipant)

      sets = [Declarations::OPERATION_KINDS.fetch(declaration.class)]
      approval = declaration.respond_to?(:approval) && declaration.approval
      sets << "approval" if approval
      sets << "location" if approval && !approval.standing
      sets
    end

    def common(declaration)
      common_sets(declaration).flat_map { |set| COMMON.fetch(set) }
    end
  end
end
