# frozen_string_literal: true

module PhComposer
  module Export
    # What one export run generated for its caller to read back after it ends (context/AGENT_INTERFACE.md,
    # "Implemented export task contract"): the translation's findings and compact result, and the report as
    # rendered, a blocked run's included. It is kept with the Task, read only through the task's owner, and
    # never recomputed from the Model or by translating again; a run that kept no report says why.
    class RunDiagnostics
      ABSENT = {
        "no_translation" => "it has no checked translation result: the run ended before translation answered, or " \
                            "the result failed its privacy check, so no report was generated.",
        "not_rendered" => "its report was not rendered: the run stopped after translation, or the report failed."
      }.freeze

      attr_writer :report

      def initialize
        @findings = []
        @result = nil
        @report = nil
      end

      # The translation answered: its findings (the preflight's warnings joined) and its result without the
      # canonical bytes.
      def translated(findings, result)
        @findings = DeepCopy.call(findings)
        @result = result
      end

      # Counts, and each kept text's size and SHA-256, which the joined fragments of a `read` must match.
      def summary
        { "findings" => @findings.length, "blocking" => @findings.count { |row| row["blocks_export"] },
          "report" => @report && Fragments.summary(@report), "report_absent" => @report ? nil : absent,
          "result" => @result && Fragments.summary(@result) }
      end

      # One part for `request` (DiagnosticPages::Request): a page of findings, one finding whole (`row`), or the
      # report or result as fragments.
      def read(request, part)
        query = "export_status.#{part}"
        if part == "findings"
          keyed = @findings.each_with_index.map { |row, index| [[index], row] }
          return DiagnosticPages.row(request, query, keyed, request.params["row"]) if request.params.key?("row")

          return DiagnosticPages.page(request, query, keyed, :list => "findings")
        end
        value = { "report" => @report, "result" => @result }.fetch(part)
        raise CodedError.new("target.not_found", "This run kept no #{part}: #{ABSENT.fetch(absent)}") unless value

        fragment, next_cursor = Fragments.read(request, query, value)
        { "fragment" => fragment, "next_cursor" => next_cursor }
      end

      private

      def absent
        @result ? "not_rendered" : "no_translation"
      end
    end
  end
end
