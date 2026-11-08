# frozen_string_literal: true

module PhComposer
  # The one result shape every public query and operation answers with (context/CONTRACTS.md,
  # "Outcomes and codes"):
  #
  #   {"status": "completed", "code": "ok", "message": "...", "effect": "committed", "revision": 7,
  #    "value": {...}, "affected": [{"kind": "...", "id": "...", "change": "updated"}],
  #    "findings": [...], "detail": null}
  #
  # `status` says how the request ended, `effect` what happened to the Model, `code` why. Fields are
  # nested and named; a handler's value never merges into the envelope.
  module Outcome
    NOTHING_WRITTEN = "Nothing was written."
    ROLLED_BACK = "The change could not be completed. No changes were retained."
    # The abort ran, but the unchanged-data check failed or could not run, so the message cannot
    # confirm that nothing changed.
    UNVERIFIED = "The change could not be completed, and PH-Composer could not confirm that the Model " \
                 "is unchanged. Check the Model before continuing."

    STATUSES = %w[completed refused failed busy pending cancelled].freeze
    EFFECTS = %w[none committed rolled_back unknown].freeze
    # The envelope as JSON Schema, published by discovery so a client can check what it reads.
    SCHEMA = {
      "type" => "object", "additionalProperties" => false,
      "required" => %w[status code message effect revision value affected findings detail proposal_digest],
      "properties" => {
        "status" => { "type" => "string", "enum" => STATUSES }, "code" => { "type" => "string" },
        "message" => { "type" => "string" }, "effect" => { "type" => "string", "enum" => EFFECTS },
        "revision" => { "type" => %w[integer null] },
        "value" => { "type" => %w[object array string number integer boolean null],
                     "description" => "The operation's result, as its result schema says; null unless completed." },
        "affected" => { "type" => "array", "items" => { "type" => "object" } },
        "findings" => { "type" => "array", "items" => { "type" => %w[object string] },
                        "description" => "Advisory rows; a params refusal lists its schema problems as strings." },
        "detail" => { "type" => %w[object null] }, "proposal_digest" => { "type" => %w[string null] },
        "sequence" => { "type" => "integer",
                        "description" => "The mutation sequence an agent connection assigned; only on its invoke " \
                                         "and outcome results." }
      }
    }.freeze

    module_function

    def completed(revision:, value: nil, effect: "none", affected: [], findings: [], proposal_digest: nil,
                  message: "Done.")
      build("completed", "ok", message, effect, revision, :value => value, :affected => affected,
                                                          :findings => findings, :proposal_digest => proposal_digest)
    end

    # A request turned away before anything was written. `mutation` adds the sentence that tells a
    # user the Model did not change, once: a message that already ends with it keeps one.
    def refused(code, message, revision:, status: "refused", mutation: false, findings: [], detail: nil)
      text = mutation && !message.end_with?(NOTHING_WRITTEN) ? "#{message} #{NOTHING_WRITTEN}" : message
      build(status, code, text, "none", revision, :findings => findings, :detail => detail)
    end

    # What an unexpected failure may say about itself: the log's reference and the kind of error. The
    # error's message stays in the log.
    def failure_detail(incident, error)
      { "incident" => incident, "error_class" => error.class.name }
    end

    # `incident` is the log's reference for an unexpected failure (Diagnostics.incident).
    def failed(effect:, revision:, reason: nil, incident: nil, error: nil)
      message = effect == "rolled_back" ? ROLLED_BACK : UNVERIFIED
      code = effect == "rolled_back" ? "operation.failed" : "operation.rollback_unverified"
      # A declared domain failure remains actionable even when it arose during a native cut.
      # Keep rollback certainty separate; never expose an unexpected exception's message.
      detail = reason && { "cause" => reason.code, "detail" => DeepCopy.call(reason.detail) }
      detail = (detail || {}).merge("incident" => incident) if incident
      detail = detail.merge("error_class" => error.class.name) if incident && error && !reason
      message = "#{reason.message} #{message}" if reason
      build("failed", code, message, effect, revision, :detail => detail)
    end

    def build(status, code, message, effect, revision, value: nil, affected: [], findings: [], detail: nil,
              proposal_digest: nil)
      {
        "status" => status, "code" => code, "message" => message, "effect" => effect, "revision" => revision,
        "value" => value, "affected" => affected, "findings" => findings, "detail" => detail,
        "proposal_digest" => proposal_digest
      }
    end
  end
end
