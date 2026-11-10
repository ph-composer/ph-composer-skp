# frozen_string_literal: true

require "json"

module PhComposer
  module Export
    # Bounded reads of export diagnostics: the current preflight's findings and repairs, and the findings a
    # finished task kept (context/AGENT_INTERFACE.md, "Focused reads"). Rows are keyed by their place in the
    # list they come from, filtered without changing what the list holds, and paged through Pages; one row
    # is read whole through Fragments. Each source binds its own cursors: the preflight the Model revision,
    # a task its own identity, since what a task kept never changes.
    module DiagnosticPages
      # What Pages and Fragments read of a request.
      Request = Struct.new(:session, :params, :revision, keyword_init: true)

      # A row's message past this many characters is cut; the row's whole text is a `row` read.
      MAX_MESSAGE = RecordQueries::MAX_MESSAGE
      # A row's `locate` or repair `params` larger than this, serialized, is given as its size and digest.
      MAX_DETAIL_BYTES = 1024
      DETAIL_FIELDS = %w[locate params].freeze
      FILTERS = %w[owner codes blocks_export object_id].freeze
      PAGE_PARAMS = %w[limit cursor].freeze

      module_function

      # One page of `keyed` (`[[key, row], ...]`, keys sorted Arrays) under `list`: the rows matching the
      # request's filters, each bounded and carrying its `row` key, with `total` (matching) and
      # `unfiltered_total` (every row the list holds).
      def page(request, query, keyed, list:)
        matching = keyed.select { |_key, row| matches?(row, request.params) }
        rows, next_cursor = Pages.bounded(request, query, matching, :key => :first.to_proc,
                                                                    :prepare => lambda { |sliced|
                                                                      sliced.map { |key, row| bounded(row, key) }
                                                                    })
        { list => rows, "total" => matching.length, "unfiltered_total" => keyed.length, "next_cursor" => next_cursor }
      end

      # One whole row, by the `row` key a page gave, as canonical JSON text in fragments.
      def row(request, query, keyed, key)
        found = keyed.find { |candidate, _row| candidate == key }
        raise CodedError.new("target.not_found", "No row #{JSON.generate(key)[0, 80]} is in that list.") unless found

        fragment, next_cursor = Fragments.read(request, query, found.last)
        { "row" => key, "fragment" => fragment, "next_cursor" => next_cursor }
      end

      # A row a page can carry: its message cut, a large `locate` or `params` summarized, each named in
      # `truncated`; identifiers and codes are never cut.
      def bounded(row, key)
        out = row.dup
        truncated = []
        message = row["message"]
        if message.is_a?(String) && message.length > MAX_MESSAGE
          out["message"] = message[0, MAX_MESSAGE]
          truncated << "message"
        end
        DETAIL_FIELDS.each do |field|
          next unless row.key?(field) && JSON.generate(row[field]).bytesize > MAX_DETAIL_BYTES

          out["#{field}_summary"] = Fragments.summary(out.delete(field))
          truncated << field
        end
        out = out.merge("row" => key)
        truncated.empty? ? out : out.merge("truncated" => truncated)
      end

      def matches?(row, params)
        (!params.key?("owner") || row["owner"] == params["owner"]) &&
          (!params.key?("codes") || params["codes"].include?(row["code"])) &&
          (!params.key?("blocks_export") || row["blocks_export"] == params["blocks_export"]) &&
          (!params.key?("object_id") || row["object_id"] == params["object_id"])
      end

      # Counts of `findings` and `repairs` (rows carrying `owner`): the whole preflight's scope, never a
      # filter's.
      def counts(findings, repairs)
        blocking = findings.count { |row| row["blocks_export"] }
        owners = (findings + repairs).map { |row| row.fetch("owner") }.uniq.sort
        {
          "totals" => { "findings" => findings.length, "blocking" => blocking,
                        "warnings" => findings.length - blocking, "repairs" => repairs.length },
          "by_owner" => owners.map do |owner|
            owned = findings.select { |row| row["owner"] == owner }
            { "owner" => owner, "findings" => owned.length, "blocking" => owned.count { |row| row["blocks_export"] },
              "repairs" => repairs.count { |row| row["owner"] == owner } }
          end,
          "by_code" => findings.group_by { |row| row.values_at("owner", "code") }.sort.map do |(owner, code), rows|
            { "code" => code, "owner" => owner, "findings" => rows.length,
              "blocking" => rows.count { |row| row["blocks_export"] } }
          end
        }
      end

      # Refuses a combination of params a read does not take. `parts` maps each part to the filters it takes;
      # filters, a page or a row need a part, a row read takes no filter or limit, and compact is a different
      # read from a part.
      def check!(params, parts)
        part = params["part"]
        given = params.keys & (FILTERS + PAGE_PARAMS + ["row"])
        if part.nil?
          raise CodedError.new("params.invalid", "Name a part to page, filter or read a row.") unless given.empty?

          return
        end
        raise CodedError.new("params.invalid", "part is one of #{parts.keys.join(', ')}.") unless parts.key?(part)
        raise CodedError.new("params.invalid",
                             "compact and part answer different reads; ask for one.") if params["compact"]

        unknown = (params.keys & FILTERS) - parts.fetch(part)
        raise CodedError.new("params.invalid", "The #{part} part takes no #{unknown.join(', ')}.") unless unknown.empty?
        return unless params.key?("row") && !(params.keys & (FILTERS + ["limit"])).empty?

        raise CodedError.new("params.invalid", "A row read takes the row and a cursor only.")
      end
    end
  end
end
