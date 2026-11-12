# frozen_string_literal: true

module PhComposer
  # What every dispatch path checks before a handler runs, and how it builds the handler's request.
  # Shared by Dispatch and HostFollowUp; the includer provides `@registry`.
  module RequestChecks
    REQUEST_KEYS = %w[sequence expected_revision proposal_digest].freeze

    private

    def check_params!(declaration, params, session)
      check_json!(params, session)
      findings = JsonSchema.validate(params, declaration.params)
      return if findings.empty?

      raise CodedError.new("params.invalid", "The request is not valid: #{findings.first}.", "findings" => findings)
    end

    def check_json!(params, session)
      return if params.is_a?(Hash) && JsonValue.problems(params).empty?

      raise CodedError.new("request.malformed", "Params must be a plain JSON object.", "revision" => session.revision)
    end

    # The mutation `request` envelope (context/CONTRACTS.md, "Public interface"): its sequence, expected
    # revision and optional proposal digest.
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

    def request_for(session, params, declaration, proposal = nil, approval: nil)
      HandlerRequest.for(session, :owner => declaration.owner, :name => declaration.name, :registry => @registry,
                                  :params => params, :proposal => proposal, :approval => approval)
    end
  end
end
