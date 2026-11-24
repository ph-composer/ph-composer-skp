# frozen_string_literal: true

module PhComposer
  module Piping
    # The schedule a bounded page at a time, for an agent whose reply has a size limit: one page of runs beside the
    # totals, Systems, Pipe Types and the first unreadable records; with compact, the runs beside the totals alone,
    # and the Systems, Pipe Types, unreadable records and one run's pipes each a page at a time. Each read walks the
    # Model again, so a cursor holds only a row's place.
    module SchedulePages
      PAGE = "#{FEATURE_ID}.schedule".freeze
      MEMBERS = "#{FEATURE_ID}.runs.members".freeze
      DETAILS = "#{FEATURE_ID}.schedule.details".freeze
      # Each list the details read pages, by the key its rows sort by.
      PARTS = { "systems" => "hot_water_system_id", "types" => "pipe_type_id", "unreadable" => "path" }.freeze
      # Unreadable records a page lists beside a count of every one.
      DETAIL_ROWS = 50
      MAX_MESSAGE = Scan::MAX_MESSAGE
      # The labels in a run row that come from a user's text, cut as every name in a bounded row is.
      NAMES = %w[display_name hot_water_system_name parent_name pipe_type_name].freeze

      module_function

      # One page of runs in schedule order, beside what is over every run. With `compact`, each run leaves out its
      # Edge paths and each finding its pipes, counting them, and gives its `index` for `runs.members`, and the System,
      # Pipe Type and unreadable rows are left to DETAILS, counted. A bad limit or cursor refuses before the Model is
      # walked.
      def page(request)
        whole = paged(request, PAGE)
        compact = request.params["compact"]
        beside = if compact
                   whole.reject { |key, _value| PARTS.key?(key) }
                        .merge("runs" => [], "system_count" => whole.fetch("systems").length,
                               "type_count" => whole.fetch("types").length)
                 else
                   whole.merge("runs" => [], "systems" => named(whole.fetch("systems")),
                               "types" => named(whole.fetch("types")),
                               "unreadable" => whole.fetch("unreadable").first(DETAIL_ROWS))
                 end
        budget = [Pages::MAX_PAGE_BYTES - JSON.generate(beside).bytesize, 0].max
        indexed = whole.fetch("runs").each_with_index.map do |row, index|
          [[index], compact ? compact(bound(row), index) : bound(row)]
        end
        rows, cursor = Pages.bounded(request, PAGE, indexed, :key => :first.to_proc, :max_bytes => budget)
        beside.merge("runs" => rows.map(&:last), "next_cursor" => cursor, "total" => indexed.length)
      end

      # One page of one run's pipes in run order, or of only those one of its findings names. The run is named by
      # its derived identifier and, from a compact row, its `index`; one that changed refuses target.not_found.
      def members(request)
        runs = paged(request, MEMBERS).fetch("runs")
        identifier = request.params.fetch("identifier")
        index = request.params["index"]
        found = (index.nil? ? runs : [runs[index]].compact).select { |row| row.fetch("identifier") == identifier }
        raise CodedError.new("target.not_found", "No piping run is #{identifier} now.") if found.empty?
        if found.length > 1
          raise CodedError.new("target.ambiguous", "#{found.length} runs are #{identifier}; name one by its index.")
        end

        paths = found.first.fetch("edge_paths")
        named = named_paths(found.first, request.params["finding"])
        rows = paths.each_with_index.filter_map do |path, place|
          { "index" => place, "path" => path } if named.nil? || named.include?(path)
        end
        page, cursor = Pages.bounded(request, MEMBERS, rows, :key => ->(row) { [row.fetch("index")] })
        { "identifier" => identifier, "members" => page, "next_cursor" => cursor, "total" => rows.length }
      end

      # One page of the schedule's System, Pipe Type or unreadable rows, by id or path, each name cut.
      def details(request)
        part = request.params.fetch("part")
        key = PARTS.fetch(part)
        rows = named(paged(request, DETAILS).fetch(part)).sort_by { |row| row.fetch(key) }
        page, cursor = Pages.bounded(request, DETAILS, rows, :key => ->(row) { Array(row.fetch(key)) })
        { part => page, "next_cursor" => cursor, "total" => rows.length }
      end

      # Rows with a user-named `name` cut, naming it in `truncated`.
      def named(rows)
        rows.map { |row| row.key?("name") ? row.merge(OccurrencePath.bounded_names(row.slice("name"))) : row }
      end

      def paged(request, query)
        Pages.limit(request.params)
        Pages.position(request, query)
        Scan.schedule(request)
      end

      def named_paths(row, finding)
        return nil if finding.nil?

        found = row.fetch("findings")[finding]
        raise CodedError.new("target.not_found", "The run has no finding #{finding}.") unless found

        found.dig("locate", "edge_paths")
      end

      # A run row with its user-named labels and its findings' messages cut, naming what was cut in `truncated`.
      def bound(row)
        labels = OccurrencePath.bounded_names(row.slice(*NAMES).compact)
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

      # A run row without what grows with its length: its Edge paths and each finding's pipes, counted instead.
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
