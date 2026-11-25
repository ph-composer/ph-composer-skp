# frozen_string_literal: true

module PhComposer
  module LineGroups
    # A schedule a bounded page at a time, for an agent whose reply has a size limit; with compact, the runs beside the
    # totals, and the detail lists, unreadable records and a run's members each paged. Each read calls `schedule`
    # again, so a cursor holds only a row's place. The feature gives its query names, `parts` (each list's sort key,
    # "unreadable" among them), `counts` (a compact page's count key per other list), `names` (user-text labels in a
    # run row) and `run_label`.
    class SchedulePages
      # Unreadable records a page lists beside a count of every one.
      DETAIL_ROWS = 50
      MAX_MESSAGE = RecordQueries::MAX_MESSAGE

      def initialize(page:, members:, details:, parts:, counts:, names:, run_label:, schedule:)
        @page = page
        @members = members
        @details = details
        @parts = parts
        @counts = counts
        @names = names
        @run_label = run_label
        @schedule = schedule
      end

      # One page of runs beside what is over every run. With `compact`, Edge paths and lists are counted, not listed,
      # and each run gives its `index` for the members read. A bad limit or cursor refuses before the Model is walked.
      def page(request)
        whole = paged(request, @page)
        beside = if request.params["compact"]
                   whole.reject { |key, _value| @parts.key?(key) }
                        .merge("runs" => [])
                        .merge(@counts.to_h { |part, count| [count, whole.fetch(part).length] })
                 else
                   whole.merge("runs" => [])
                        .merge(@counts.keys.to_h { |part| [part, named(whole.fetch(part))] })
                        .merge("unreadable" => whole.fetch("unreadable").first(DETAIL_ROWS))
                 end
        budget = [Pages::MAX_PAGE_BYTES - JSON.generate(beside).bytesize, 0].max
        indexed = whole.fetch("runs").each_with_index.map do |row, index|
          [[index], request.params["compact"] ? compact(bound(row), index) : bound(row)]
        end
        rows, cursor = Pages.bounded(request, @page, indexed, :key => :first.to_proc, :max_bytes => budget)
        beside.merge("runs" => rows.map(&:last), "next_cursor" => cursor, "total" => indexed.length)
      end

      # One page of a run's Edges, or those one finding names; the run by identifier and `index`.
      def members(request)
        runs = paged(request, @members).fetch("runs")
        identifier = request.params.fetch("identifier")
        index = request.params["index"]
        found = (index.nil? ? runs : [runs[index]].compact).select { |row| row.fetch("identifier") == identifier }
        raise CodedError.new("target.not_found", "No #{@run_label} is #{identifier} now.") if found.empty?
        if found.length > 1
          raise CodedError.new("target.ambiguous", "#{found.length} runs are #{identifier}; name one by its index.")
        end

        paths = found.first.fetch("edge_paths")
        named = named_paths(found.first, request.params["finding"])
        rows = paths.each_with_index.filter_map do |path, place|
          { "index" => place, "path" => path } if named.nil? || named.include?(path)
        end
        page, cursor = Pages.bounded(request, @members, rows, :key => ->(row) { [row.fetch("index")] })
        { "identifier" => identifier, "members" => page, "next_cursor" => cursor, "total" => rows.length }
      end

      # One page of one detail list or the unreadable rows, by id or path, each name cut.
      def details(request)
        part = request.params.fetch("part")
        key = @parts.fetch(part)
        rows = named(paged(request, @details).fetch(part)).sort_by { |row| row.fetch(key) }
        page, cursor = Pages.bounded(request, @details, rows, :key => ->(row) { Array(row.fetch(key)) })
        { part => page, "next_cursor" => cursor, "total" => rows.length }
      end

      private

      # Rows with a user-named `name` cut, naming it in `truncated`.
      def named(rows)
        rows.map { |row| row.key?("name") ? row.merge(OccurrencePath.bounded_names(row.slice("name"))) : row }
      end

      def paged(request, query)
        Pages.limit(request.params)
        Pages.position(request, query)
        @schedule.call(request)
      end

      def named_paths(row, finding)
        return nil if finding.nil?

        found = row.fetch("findings")[finding]
        raise CodedError.new("target.not_found", "The run has no finding #{finding}.") unless found

        found.dig("locate", "edge_paths")
      end

      # A run row with its user-named labels and its findings' messages cut, naming what was cut in `truncated`.
      def bound(row)
        labels = OccurrencePath.bounded_names(row.slice(*@names).compact)
        group = OccurrencePath.bounded_names(row.fetch("group").slice("name"))
        truncated = Array(labels.delete("truncated")) + Array(group.delete("truncated")).map { |key| "group.#{key}" }
        findings = row.fetch("findings").each_with_index.map do |finding, place|
          message = finding.fetch("message")
          truncated << "findings.#{place}.message" if message.length > MAX_MESSAGE
          finding.merge("message" => message[0, MAX_MESSAGE])
        end
        bounded = row.merge(labels).merge("group" => row.fetch("group").merge(group), "findings" => findings)
        truncated.empty? ? bounded : bounded.merge("truncated" => truncated)
      end

      # A run row without what grows with its length: its Edge paths and each finding's Edges, counted instead.
      def compact(row, index)
        row.reject { |key, _value| key == "edge_paths" }.merge(
          "index" => index, "edge_count" => row.fetch("edge_paths").length,
          "findings" => row.fetch("findings").map do |finding|
            finding.reject { |key, _value| key == "locate" }
                   .merge("edge_count" => finding.dig("locate", "edge_paths").length)
          end
        )
      end
    end
  end
end
