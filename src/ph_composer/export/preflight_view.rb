# frozen_string_literal: true

module PhComposer
  module Export
    # The aggregate export preflight (Dispatch#export_preflight) in each form a caller asks for: whole, as
    # before; compact, counted; or one part, a filtered page or one row (DiagnosticPages). Rows arrive keyed by
    # `[contributor place, index]` and carrying their contributor's `owner`, which the whole form leaves out.
    module PreflightView
      # The parts and the filters each takes.
      PARTS = { "findings" => %w[owner codes blocks_export object_id], "repairs" => %w[owner] }.freeze

      module_function

      # The options as given, nil values dropped, refused before any contributor runs when they are not a
      # read this answers.
      def check!(options)
        checked = TaskContract.check_options!("export_preflight", options)
        DiagnosticPages.check!(checked, PARTS)
        checked
      end

      # `lists` holds the keyed `findings` and `repairs`; `location`, an approved destination's id, adds what
      # that destination holds (Export.destination_report).
      def answer(session, lists, location, options)
        destination = location && Export.destination_report(location)
        return part(session, lists, options) if options["part"]
        return compact(lists.fetch("findings"), lists.fetch("repairs"), destination) if options["compact"]

        strip = ->(keyed) { keyed.map { |_key, row| row.reject { |field, _value| field == "owner" } } }
        value = lists.transform_values(&strip)
        value["destination"] = destination if destination
        value
      end

      # Ready when nothing the preflight checks blocks and a named destination has no problem; the counts
      # always cover the whole preflight.
      def compact(findings, repairs, destination)
        counts = DiagnosticPages.counts(findings.map(&:last), repairs.map(&:last))
        blocked = counts.dig("totals", "blocking").positive? || !destination&.fetch("problem").nil?
        value = { "ready" => !blocked }.merge(counts)
        destination ? value.merge("destination" => destination) : value
      end

      # A page of one part or one row of it, its cursor bound to the Model revision.
      def part(session, lists, options)
        name = options.fetch("part")
        request = DiagnosticPages::Request.new(:session => session, :params => options, :revision => session.revision)
        query = "export_preflight.#{name}"
        read = if options.key?("row")
                 DiagnosticPages.row(request, query, lists.fetch(name), options.fetch("row"))
               else
                 DiagnosticPages.page(request, query, lists.fetch(name), :list => name)
               end
        { "part" => name }.merge(read)
      end
    end
  end
end
