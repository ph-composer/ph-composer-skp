# frozen_string_literal: true

module PhComposer
  module Export
    # What every contributor's preflight query answers (Dispatch#export_preflight): findings that
    # describe what blocks or weakens export, and repairs the user may choose to run first. A
    # contributor publishes this as its preflight result schema so a client reads one shape.
    PREFLIGHT_RESULT = {
      "type" => "object", "additionalProperties" => false, "required" => %w[findings repairs],
      "properties" => {
        "findings" => {
          "type" => "array",
          "items" => {
            "type" => "object", "additionalProperties" => false,
            "required" => %w[code section object_id message blocks_export],
            "properties" => {
              "code" => { "type" => "string" }, "section" => { "type" => "string" },
              "object_id" => { "type" => %w[string null], "description" => "The record the finding is about." },
              "message" => { "type" => "string" }, "blocks_export" => { "type" => "boolean" },
              "locate" => {
                "type" => "object", "additionalProperties" => false, "required" => %w[name params],
                "description" => "A view command that shows what the finding is about.",
                "properties" => { "name" => { "type" => "string" }, "params" => { "type" => "object" } }
              }
            }
          }
        },
        "repairs" => {
          "type" => "array",
          "items" => {
            "type" => "object", "additionalProperties" => false,
            "required" => %w[id label checked action params],
            "description" => "An action the export workflow offers to run before exporting.",
            "properties" => {
              "id" => { "type" => "string" }, "label" => { "type" => "string" }, "checked" => { "type" => "boolean" },
              "action" => { "type" => "string" }, "params" => { "type" => "object" }
            }
          }
        }
      }
    }.freeze

    # The warnings, the non-blocking findings, every export contributor's preflight gives for `session` as
    # it is now. A started export (Task) reads them so its report carries what the preflight showed.
    # Starting it was granted, so the read asks for no grant of its own, as a menu item's availability
    # read does (Commands); a result outside PREFLIGHT_RESULT is an internal error.
    def self.preflight_warnings(session, registry = Registry.current)
      registry.export_contributors.values.sort_by(&:name).filter_map(&:preflight).flat_map do |name|
        declaration = registry.queries.fetch(name)
        value = declaration.handler.call(HandlerRequest.for(session, :owner => declaration.owner,
                                                                     :name => name, :registry => registry))
        unless JsonSchema.validate(value, PREFLIGHT_RESULT).empty?
          raise InternalError, "#{name} returned a preflight outside its schema."
        end

        value.fetch("findings").reject { |finding| finding.fetch("blocks_export") }
      end
    end

    # What an approved destination holds now and, as `problem`, why start_export would refuse it (the
    # same check Tasks#start makes), or nil, so a caller learns before starting what the start refuses.
    def self.destination_report(location)
      problem = nil
      held = ApprovedLocations.observe(location) do |path|
        problem = ArtifactPair.destination_problem(path)
        ArtifactPair.state(path)
      end
      held.merge("problem" => problem)
    end
  end
end
