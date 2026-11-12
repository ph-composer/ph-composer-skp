# frozen_string_literal: true

module PhComposer
  # One caller's operation history: the change outcomes its session still retains for it, newest first, a
  # bounded page at a time (context/AGENT_INTERFACE.md, "Writes with observable outcomes"). A row says what
  # was asked and how it ended, never what it carried: no value, params, message or detail. The store's
  # bound is the history's bound, so the answer says it.
  module OutcomeHistory
    QUERY = "outcomes"
    # A row names its first affected references, as many as fit AFFECTED_BYTES, and counts them all, so every
    # row fits a page whatever paths its references carry; `outcome` with the row's sequence reads the whole.
    MAX_AFFECTED = 10
    AFFECTED_BYTES = 2 * 1024
    RETENTION = { "capacity" => OutcomeStore::CAPACITY, "lifetime_seconds" => OutcomeStore::LIFETIME_SECONDS,
                  "shared" => "across every caller of this Model session" }.freeze
    MESSAGE = "What this session still retains: up to #{OutcomeStore::CAPACITY} outcomes across every caller, " \
              "each for #{OutcomeStore::LIFETIME_SECONDS / 60} minutes. An older change is no longer listed; " \
              "read the Model for it."

    module_function

    # `keys` holds the caller's own names for some of its sequences (sequence => key), which a row echoes as
    # its idempotency_key. A cursor binds the caller (inside the filter digest, so the handle never shows)
    # and its highest accepted sequence, so another caller's cursor is params.invalid and a page asked for
    # after a newer change was accepted refuses query.cursor_expired; an eviction only shortens the tail.
    def page(session, caller, params, keys = {})
      unless params["cursor"].nil? || params["cursor"].is_a?(String)
        raise CodedError.new("params.invalid", "cursor must be the next_cursor string of the previous page.")
      end

      rows = session.outcomes.history(caller.handle).map { |entry| row(entry, keys[entry.sequence]) }
      bound = params.slice(*Pages::PAGE_KEYS).merge("caller" => caller.handle)
      request = HandlerRequest.new(:session => session, :params => bound)
      page, next_cursor = Pages.bounded(request, QUERY, rows, :key => ->(row) { [-row.fetch("sequence")] },
                                                              :revision => caller.highest_sequence)
      Outcome.completed(:revision => session.revision, :message => MESSAGE,
                        :value => { "outcomes" => page, "total" => rows.length, "next_cursor" => next_cursor,
                                    "retention" => RETENTION })
    end

    def row(entry, key)
      outcome = entry.outcome
      affected = outcome["affected"].is_a?(Array) ? outcome["affected"] : []
      { "sequence" => entry.sequence, "idempotency_key" => key, "operation" => entry.name,
        "status" => outcome["status"], "effect" => outcome["effect"], "code" => outcome["code"],
        "revision" => outcome["revision"], "recorded_at" => entry.recorded_utc,
        "affected" => first_affected(affected), "affected_total" => affected.length }
    end

    def first_affected(affected)
      bytes = 2
      affected.first(MAX_AFFECTED).take_while do |reference|
        (bytes += JSON.generate(reference).bytesize + 1) <= AFFECTED_BYTES
      end
    end
  end
end
