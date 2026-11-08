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
      STATUS = {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[task_id stage count cancellable outcome],
        "description" => "One task's progress. Never carries the canonical HBJSON bytes.",
        "properties" => {
          "task_id" => { "type" => "string" },
          "stage" => { "type" => "string", "enum" => %w[queued reading translating checking writing finished] },
          "count" => { "type" => "integer", "minimum" => 0, "description" => "Entities read so far." },
          "cancellable" => { "type" => "boolean", "description" => "False once writing starts or the task ended." },
          "outcome" => OUTCOME
        }
      }.freeze
      NO_PARAMS = { "type" => "object", "additionalProperties" => false, "properties" => {} }.freeze
      TASK_PARAMS = { "type" => "object", "additionalProperties" => false, "required" => ["task_id"],
                      "properties" => { "task_id" => TASK_ID } }.freeze
      EXAMPLE_TASK = { "task_id" => "export_0123456789abcdef01234567" }.freeze

      TASKS = {
        "export_preflight" => {
          "capability" => "read", "examples" => [{}, { "location" => "location_AAAAAAAAAAAA" }],
          "params" => {
            "type" => "object", "additionalProperties" => false, "properties" => {
              "location" => { "type" => "string", "minLength" => 1,
                              "description" => "An approved destination's id, to report what it holds now." }
            }
          },
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
          "description" => "Every export contributor's findings and the repairs it offers, before starting."
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
          "capability" => "export", "params" => TASK_PARAMS, "result" => STATUS, "examples" => [EXAMPLE_TASK],
          "description" => "Poll one task this caller started. An expired or other-Model handle refuses " \
                           "task.expired; another caller's refuses task.foreign."
        },
        "cancel_export" => {
          "capability" => "export", "params" => TASK_PARAMS, "result" => STATUS, "examples" => [EXAMPLE_TASK],
          "description" => "Cancel a task this caller started before it starts writing; nothing is " \
                           "written. Another caller's refuses task.foreign."
        },
        "latest_export" => {
          "capability" => "export", "params" => NO_PARAMS, "result" => STATUS.merge("type" => %w[object null]),
          "examples" => [{}], "description" => "The most recent retained task this caller started, or null; another " \
                                               "caller's tasks are not shown."
        }
      }.freeze

      module_function

      def describe(name)
        task = TASKS[name]
        task && DeepCopy.call({ "kind" => "task", "name" => name, "owner" => "ph_composer.export" }.merge(task))
      end
    end
  end
end
