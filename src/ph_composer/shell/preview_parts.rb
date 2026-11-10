# frozen_string_literal: true

require_relative "fragments"

module PhComposer
  # A preview larger than one reply, kept reviewable (context/AGENT_INTERFACE.md, "Writes with observable
  # outcomes"). `compact` keeps the outcome's status, revision and proposal_digest and gives each part's
  # size and digest in place of the part; `read` answers one part exactly, in fragments (shell/fragments.rb),
  # from a preview Dispatch has just run again. The cursor binds the action, its params, the part, the
  # revision and the proposal digest, so a fragment of another proposal refuses `query.cursor_expired`.
  # Nothing is kept or held open between fragments, and apply revalidates the proposal as always.
  module PreviewParts
    PARTS = %w[value affected findings].freeze
    # What Pages and Fragments bind a part's cursor to; no handler sees it.
    Request = Struct.new(:session, :params, :revision)

    module_function

    # `outcome` with value, affected and findings left out and each part's size and digest (and count, for a
    # list) in `detail`, when it serializes larger than `within` bytes; unchanged otherwise. `rerun` runs the
    # same preview again: a part that comes out different (an action that names new ids each run) is marked
    # `stable: false`, since what a later read answers for it will not match this digest.
    def compact(outcome, within, rerun)
      return outcome unless outcome["status"] == "completed" && JSON.generate(outcome).bytesize > within

      again = rerun.call
      parts = PARTS.to_h do |part|
        value = outcome[part]
        summary = Fragments.summary(value).merge("stable" => again["status"] == "completed" &&
                                                             CanonicalJson.generate(again[part]) ==
                                                             CanonicalJson.generate(value))
        [part, value.is_a?(Array) ? summary.merge("count" => value.length) : summary]
      end
      outcome.merge("message" => "#{outcome['message']} It is larger than one reply: read its value, affected " \
                                 "and findings by part.",
                    "value" => nil, "affected" => [], "findings" => [],
                    "detail" => (outcome["detail"] || {}).merge("omitted" => PARTS, "parts" => parts))
    end

    # The Outcome answering one fragment of `part` of `outcome`, a completed preview of `name` with `params`.
    def read(session, outcome, name, params, part, cursor)
      raise CodedError.new("params.invalid", "A preview's parts are #{PARTS.join(', ')}.") unless PARTS.include?(part)

      digest = outcome.fetch("proposal_digest")
      revision = outcome.fetch("revision")
      request = Request.new(session, { "name" => name, "params" => params, "part" => part, "cursor" => cursor }.compact,
                            revision)
      fragment, next_cursor = Fragments.read(request, "preview", outcome.fetch(part), :revision => [revision, digest])
      Outcome.completed(:revision => revision, :proposal_digest => digest, :message => "Preview only.",
                        :value => { "name" => name, "part" => part, "proposal_digest" => digest,
                                    "fragment" => fragment, "next_cursor" => next_cursor })
    rescue CodedError => error
      Outcome.refused(error.code, error.message, :revision => session.revision, :detail => error.detail)
    end
  end
end
