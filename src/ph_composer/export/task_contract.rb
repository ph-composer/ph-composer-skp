# frozen_string_literal: true

module PhComposer
  module Export
    # The export task methods' public descriptions (PhComposer::API start_export and its siblings). A
    # file export is not a Model mutation, so these are not registered actions: they are shell-owned
    # task methods with their own grant. `API.describe(name:)` answers each from here, so a client can
    # call them from their declarations alone. Each params key is the method's keyword argument.
    module TaskContract
      TASK_ID = { "type" => "string", "description" => "task_id from start_export." }.freeze
      FILE = { "type" => "object", "required" => %w[path sha256 bytes],
               "properties" => { "path" => { "type" => "string" }, "sha256" => { "type" => "string" },
                                 "bytes" => { "type" => "integer" } } }.freeze
      ARTIFACTS = {
        "type" => "object", "required" => %w[run_id source_revision export_generation hbjson report],
        "description" => "Where the written pair is and what its bytes hash to, for the caller that started the " \
                         "task only. Read the files with your own tools and compare the SHA-256 before parsing: a " \
                         "later export to the same destination replaces them.",
        "properties" => { "run_id" => { "type" => "string" }, "source_revision" => { "type" => "integer" },
                          "export_generation" => { "type" => "integer" },
                          "location" => { "type" => %w[object null] }, "hbjson" => FILE, "report" => FILE }
      }.freeze
      OUTCOME = {
        "type" => %w[object null],
        "description" => "Null until the task ends; then the outcome shape every call answers with.",
        "required" => %w[status code message effect],
        "properties" => {
          "status" => { "type" => "string", "enum" => %w[completed refused failed cancelled] },
          "code" => { "type" => "string", "description" => "export.complete, export.blocked, export.cancelled " \
                                                           "and so on." },
          "message" => { "type" => "string" }, "effect" => { "type" => "string" },
          "revision" => { "type" => %w[integer null] },
          "value" => { "type" => %w[object null],
                       "description" => "When completed: the compact result and, for a start from an approved " \
                                        "location, that location's id and label. Only the caller that started " \
                                        "the task, once the pair is written, also gets artifacts.",
                       "properties" => { "artifacts" => ARTIFACTS } },
          "affected" => { "type" => "array" }, "findings" => { "type" => "array" },
          "detail" => { "type" => %w[object null] }, "proposal_digest" => { "type" => %w[string null] }
        }
      }.freeze
      SUMMARY = { "type" => %w[object null], "description" => "Its canonical JSON text's size and SHA-256.",
                  "properties" => { "bytes" => { "type" => "integer" }, "sha256" => { "type" => "string" } } }.freeze
      SOURCE = {
        "type" => "object", "required" => %w[revision export_generation],
        "description" => "The Model revision and content generation the run read, captured when it started; null " \
                         "only for a task that failed before it read anything.",
        "properties" => { "revision" => { "type" => %w[integer null] },
                          "export_generation" => { "type" => %w[integer null] } }
      }.freeze
      DIAGNOSTICS = {
        "type" => %w[object null],
        "description" => "Null until the task ends; then what it kept, which export_status with part reads: the " \
                         "finding counts, and the generated report and compact result as size and digest, or null.",
        "properties" => {
          "findings" => { "type" => "integer" }, "blocking" => { "type" => "integer" },
          "report" => SUMMARY, "result" => SUMMARY,
          "report_absent" => { "type" => %w[string null], "enum" => ["no_translation", "not_rendered", nil],
                               "description" => "Why no report was kept: no_translation when the run ended before " \
                                                "translation answered, not_rendered when it stopped after." }
        }
      }.freeze
      STATUS = {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[task_id stage count cancellable source diagnostics outcome],
        "description" => "One task's progress. Never carries the canonical HBJSON bytes.",
        "properties" => {
          "task_id" => { "type" => "string" },
          "stage" => { "type" => "string", "enum" => %w[queued reading translating checking writing finished] },
          "count" => { "type" => "integer", "minimum" => 0, "description" => "Entities read so far." },
          "cancellable" => { "type" => "boolean", "description" => "False once writing starts or the task ended." },
          "source" => SOURCE, "diagnostics" => DIAGNOSTICS, "outcome" => OUTCOME
        }
      }.freeze
      NO_PARAMS = { "type" => "object", "additionalProperties" => false, "properties" => {} }.freeze
      TASK_PARAMS = { "type" => "object", "additionalProperties" => false, "required" => ["task_id"],
                      "properties" => { "task_id" => TASK_ID } }.freeze
      COMPACT = { "type" => "boolean",
                  "description" => "Leave the findings, the result and the report out of the outcome; diagnostics " \
                                   "counts them and export_status with part reads them." }.freeze
      # The filters and page of a part read (Export::DiagnosticPages); totals beside a page count the whole list.
      FILTERS = {
        "codes" => { "type" => "array", "minItems" => 1, "items" => { "type" => "string" },
                     "description" => "Only findings with one of these codes." },
        "blocks_export" => { "type" => "boolean", "description" => "Only blocking findings, or only warnings." },
        "object_id" => { "type" => "string", "description" => "Only findings about this record." },
        "row" => { "type" => "array", "minItems" => 1, "maxItems" => 2, "items" => { "type" => "integer" },
                   "description" => "One row whole, by the row key a page gave, as fragments." },
        "limit" => Pages::LIMIT,
        "cursor" => { "type" => "string", "description" => "next_cursor from the previous page or fragment of the " \
                                                           "same read." }
      }.freeze
      PREFLIGHT_OPTIONS = {
        "compact" => { "type" => "boolean",
                       "description" => "Counts by owner and code, blocking and warnings, and the destination, in " \
                                        "place of the lists." },
        "part" => { "type" => "string", "enum" => %w[findings repairs],
                    "description" => "One filtered page of findings or repairs, bound to this revision." },
        "owner" => { "type" => "string", "description" => "Only one feature's rows, by its id." }
      }.merge(FILTERS).freeze
      STATUS_OPTIONS = {
        "compact" => COMPACT,
        "part" => { "type" => "string", "enum" => %w[findings report result outcome],
                    "description" => "What the ended task kept: a filtered page of findings, or the generated " \
                                     "report, the compact result or the whole outcome (a long failure message " \
                                     "included) as fragments. Never reads the Model or exports again." }
      }.merge(FILTERS).freeze
      ROW = {
        "type" => "object", "description" => "A row as its whole list holds it, with owner (a preflight row) and " \
                                             "row, its key; message cut at 512 characters and a locate or params " \
                                             "over 1 KiB given as locate_summary or params_summary, each named in " \
                                             "truncated."
      }.freeze
      PART_PAGE = {
        "type" => "object",
        "description" => "With part and no row: findings or repairs, one page; total, the rows matching the " \
                         "filters; unfiltered_total, every row of the part. With row, or a report or result part: " \
                         "fragment and next_cursor, the canonical JSON text to join and check against its sha256.",
        "properties" => {
          "part" => { "type" => "string" }, "findings" => { "type" => "array", "items" => ROW },
          "repairs" => { "type" => "array", "items" => ROW }, "total" => { "type" => "integer" },
          "unfiltered_total" => { "type" => "integer" }, "row" => { "type" => "array" },
          "fragment" => Fragments::FRAGMENT, "next_cursor" => Pages::NEXT_CURSOR,
          "task_id" => { "type" => "string" }, "source" => SOURCE
        }
      }.freeze
      COUNTS = {
        "type" => "object",
        "description" => "With compact: ready (nothing the preflight checks blocks, and the destination, when " \
                         "named, has no problem; translation still checks the HBJSON), totals, by_owner and by_code " \
                         "over the whole preflight, and destination.",
        "properties" => { "ready" => { "type" => "boolean" }, "totals" => { "type" => "object" },
                          "by_owner" => { "type" => "array" }, "by_code" => { "type" => "array" },
                          "destination" => { "type" => "object" } }
      }.freeze
      EXAMPLE_TASK = { "task_id" => "export_0123456789abcdef01234567" }.freeze

      TASKS = {
        "export_preflight" => {
          "capability" => "read", "examples" => [{}, { "location" => "location_AAAAAAAAAAAA" }],
          "params" => {
            "type" => "object", "additionalProperties" => false, "properties" => {
              "location" => { "type" => "string", "minLength" => 1,
                              "description" => "An approved destination's id, to report what it holds now." }
            }.merge(PREFLIGHT_OPTIONS)
          },
          "compact_result" => COUNTS, "part_result" => PART_PAGE,
          "result" => PREFLIGHT_RESULT.merge("properties" => PREFLIGHT_RESULT.fetch("properties").merge(
            "destination" => {
              "type" => "object", "additionalProperties" => false, "required" => %w[exists state problem],
              "description" => "With location: whether the pair exists and its state, and problem, why " \
                               "start_export refuses the destination itself (a name without .hbjson, or half " \
                               "of a prior pair), null when it does not. An existing pair is still replaced " \
                               "only with replace and this state as the location's expected_destination.",
              "properties" => { "exists" => { "type" => "boolean" }, "state" => { "type" => %w[string null] },
                                "problem" => { "type" => %w[string null] } }
            }
          )),
          "description" => "Every export contributor's findings and the repairs it offers, before starting. compact " \
                           "counts them; part pages one list, filtered by owner, codes, blocks_export or object_id, " \
                           "and row reads one row whole. A page's cursor expires when the Model changes."
        },
        "start_export" => {
          "capability" => "export",
          "description" => "Start one export of the canonical HBJSON and its report to a destination the user " \
                           "approved (ph_composer.locations.approve_destination). An existing pair is replaced only " \
                           "with replace and the expected_destination export_preflight reported; one task runs " \
                           "per Model at a time.",
          "params" => {
            "type" => "object", "additionalProperties" => false, "required" => ["location"],
            "properties" => { "location" => ApprovedLocations.param("save_file") }
          },
          "result" => STATUS, "examples" => [{ "location" => { "id" => "location_AAAAAAAAAAAA" } }]
        },
        "export_status" => {
          "capability" => "export",
          "params" => TASK_PARAMS.merge("properties" => TASK_PARAMS.fetch("properties").merge(STATUS_OPTIONS)),
          "result" => STATUS, "part_result" => PART_PAGE,
          "examples" => [EXAMPLE_TASK, EXAMPLE_TASK.merge("compact" => true),
                         EXAMPLE_TASK.merge("part" => "findings", "blocks_export" => true)],
          "description" => "Poll one task this caller started; compact while polling. Once it ended, part reads " \
                           "what it kept, bound to this task and not the Model: findings a page at a time, the " \
                           "report or the result in fragments; before that part refuses task.running. An expired " \
                           "or other-Model handle refuses task.expired; another caller's refuses task.foreign."
        },
        "cancel_export" => {
          "capability" => "export", "params" => TASK_PARAMS, "result" => STATUS, "examples" => [EXAMPLE_TASK],
          "description" => "Cancel a task this caller started before it starts writing; nothing is " \
                           "written. Another caller's refuses task.foreign."
        },
        "latest_export" => {
          "capability" => "export",
          "params" => NO_PARAMS.merge("properties" => { "compact" => COMPACT }),
          "result" => STATUS.merge("type" => %w[object null]),
          "examples" => [{}, { "compact" => true }],
          "description" => "The most recent retained task this caller started, or null; another caller's tasks are " \
                           "not shown."
        }
      }.freeze

      module_function

      # The bounded-read options of task method `name` as given, nil values dropped, checked against its params
      # schema; the method's own keys (location, task_id) are checked where they are used.
      def check_options!(name, options)
        given = options.transform_keys(&:to_s).compact
        properties = TASKS.fetch(name).dig("params", "properties").reject { |key, _schema|
          %w[location task_id].include?(key)
        }
        schema = { "type" => "object", "additionalProperties" => false, "properties" => properties }
        problem = JsonSchema.validate(given, schema).first
        raise CodedError.new("params.invalid", "The request is not valid: #{problem}.") if problem

        given
      end

      def describe(name)
        task = TASKS[name]
        task && DeepCopy.call({ "kind" => "task", "name" => name, "owner" => "ph_composer.export" }.merge(task))
      end
    end
  end
end
