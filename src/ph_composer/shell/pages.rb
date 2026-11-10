# frozen_string_literal: true

module PhComposer
  # Bounded pages for every paged read (context/AGENT_INTERFACE.md, focused reads). A read sorts its
  # rows by a stable key, and a cursor carries the last key it returned together with what it was
  # read against: the Model session, the query, a digest of the filter and the revision. A cursor
  # reused after any of those changed is refused rather than mixing two states or two questions.
  # A read whose rows do not come from the Model binds what they do come from instead of the
  # revision, such as a library catalog's generation, by passing `revision:`.
  module Pages
    DEFAULT_LIMIT = 100
    MAXIMUM_LIMIT = 500
    LIMIT = { "type" => "number",
              "description" => "Page size, 1 to #{MAXIMUM_LIMIT}; #{DEFAULT_LIMIT} when absent." }.freeze
    CURSOR = { "type" => "string",
               "description" => "next_cursor from the previous page of the same query and filter." }.freeze
    NEXT_CURSOR = { "type" => %w[string null],
                    "description" => "Pass back as cursor for the next page; null on the last page." }.freeze
    TOTAL = { "type" => "integer", "minimum" => 0,
              "description" => "Rows matching the filter, on every page." }.freeze
    PAGE_KEYS = %w[limit cursor].freeze
    # The one reply budget: an agent connection refuses a serialized result larger than this, envelope and
    # all (context/AGENT_INTERFACE.md, "User-controlled local access").
    REPLY_BYTES = 24 * 1024
    # The serialized rows of one bounded page stay under this, so the page and its envelope fit REPLY_BYTES.
    MAX_PAGE_BYTES = 16 * 1024

    module_function

    # [page, next_cursor] of `rows`, which are sorted by `key`.
    def slice(request, query, rows, key:, revision: request.revision)
      limit = limit(request.params)
      after = position(request, query, revision)
      remaining = after.nil? ? rows : rows.select { |row| after_position?(key.call(row), after) }
      page = remaining.first(limit)
      [page, remaining.length > limit ? token(request, query, key.call(page.last), revision) : nil]
    end

    # As `slice`, then cut at the last whole row that keeps the page's serialized rows under `max_bytes`,
    # with a cursor that resumes after it. A row is never split; one row larger than the budget comes
    # alone, and a caller with a reply budget asks for fewer `fields`.
    # `size` weighs a row when what the page carries beside its rows grows with them. `prepare`, when given,
    # turns the sliced rows into the rows the page answers, one for one, so a read that is costly per row
    # computes only the rows of this page; `key` still reads the rows `rows` holds.
    def bounded(request, query, rows, key:, revision: request.revision, max_bytes: MAX_PAGE_BYTES,
                size: ->(row) { JSON.generate(row).bytesize + 1 }, prepare: nil)
      sliced, next_cursor = slice(request, query, rows, :key => key, :revision => revision)
      page = prepare ? prepare.call(sliced) : sliced
      total = 2
      fitted = page.take_while.with_index do |row, index|
        total += size.call(row)
        index.zero? || total <= max_bytes
      end
      return [page, next_cursor] if fitted.length == page.length

      [fitted, token(request, query, key.call(sliced[fitted.length - 1]), revision)]
    end

    def limit(params)
      limit = params.fetch("limit", DEFAULT_LIMIT)
      return limit if limit.is_a?(Integer) && limit.between?(1, MAXIMUM_LIMIT)

      raise CodedError.new("query.limit_invalid", "The page limit must be a whole number from 1 to #{MAXIMUM_LIMIT}.")
    end

    def token(request, query, after, revision = request.revision)
      [JSON.generate(binding_of(request, query, revision).merge("after" => after))].pack("m0")
    end

    def position(request, query, revision = request.revision)
      cursor = request.params["cursor"]
      return nil if cursor.nil?

      decoded = JSON.parse(cursor.unpack1("m0"))
      raise ArgumentError, "not a cursor" unless decoded.is_a?(Hash) && decoded.key?("after") &&
                                                 [String, Array].include?(decoded["after"].class)

      expected = binding_of(request, query, revision)
      asked = decoded.reject { |key, _value| %w[after revision].include?(key) }
      if asked != expected.reject { |key, _value| key == "revision" }
        raise CodedError.new("params.invalid", "That cursor belongs to another query, filter or Model.")
      end

      unless decoded["revision"] == expected["revision"]
        raise CodedError.new("query.cursor_expired", "What this page was read from has changed; start again " \
                                                     "from the first page.")
      end

      decoded.fetch("after")
    rescue JSON::ParserError, ArgumentError
      raise CodedError.new("params.invalid", "That cursor is not one this query issued.")
    end

    # A position of another kind than this query's keys (a path where ids are, say) did not come
    # from this query, however well its binding was copied.
    def after_position?(row_key, after)
      order = row_key <=> after
      raise CodedError.new("params.invalid", "That cursor is not one this query issued.") if order.nil?

      order.positive?
    end

    def binding_of(request, query, revision)
      { "session" => request.session.id, "query" => query, "revision" => revision,
        "filter" => CanonicalJson.digest(request.params.reject { |key, _value| PAGE_KEYS.include?(key) }) }
    end
    private_class_method :after_position?, :binding_of
  end
end
