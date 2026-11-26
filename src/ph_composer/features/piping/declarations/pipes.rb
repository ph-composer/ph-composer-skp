# frozen_string_literal: true

module PhComposer
  module Piping
    # What the pipe assignment registers: the pipe reference target, assign and clear over explicit Edges, and the
    # selection read with its panel section. Each write is one native Undo step.
    module PipeRegistration
      PREFIX = "#{FEATURE_ID}.pipes".freeze
      ASSIGN = (GroupRegistration::LOCATE + %w[gesture.too_large piping.group_in_zone piping.group_nested
                                               piping.outside_group]).freeze
      CLEAR = (ASSIGN + %w[copy.rule_missing reference.in_use]).freeze
      SELECTION = %w[gesture.too_large record.unreadable validation.failed].freeze
      SELECTION_PAGE = (SELECTION + %w[query.cursor_expired query.limit_invalid]).freeze

      REFERENCE = Assignment::Target::REFERENCE
      VALUES = { "type" => "object" }.freeze
      TARGETS = Shapes.list(Shapes.object({ "reference" => REFERENCE,
                                            "expected_values" => VALUES.merge(
                                              "description" => "The Edge's assignment values as last read; {} or " \
                                                               "absent for an Edge with none. A changed value " \
                                                               "refuses as target.changed."
                                            ) }, :optional => ["expected_values"]))
                      .merge("minItems" => 1,
                             "description" => "Explicit Edges, as pipes.selection returns them; at most " \
                                              "#{Assignment::GESTURE_EDGE_LIMIT}.")
      EXAMPLE = { "group_path" => [1301], "entity_path" => [1301, 1305], "entity_id" => nil }.freeze
      ROLE_KEYS = Assignment::ROLE_SCHEMAS.keys.freeze
      ASSIGN_PARAMS = Shapes.object({
        "targets" => TARGETS,
        "pipe_type_id" => Shapes.id(PipeType::KIND.id_prefix, "The Pipe Type every Edge gets."),
        "role" => { "type" => "string", "enum" => Assignment::ROLES,
                    "description" => "trunk, branch, twig or recirculation. A role's values not given keep the " \
                                     "Edge's own when it already has this role, else take their defaults; values " \
                                     "of another role refuse as params.invalid." }
      }.merge(Assignment::ROLE_SCHEMAS), :optional => ROLE_KEYS).freeze
      REFUSAL = GroupRegistration::REFUSAL
      ROW = Shapes.object({
        "path" => Assignment::Target::PATH,
        "reference" => REFERENCE.merge("type" => %w[object null],
                                       "description" => "The Edge's reference, or null when it is not directly in " \
                                                        "a Piping group."),
        "group" => Shapes.object({ "group_id" => Shapes::TEXT, "group_path" => Assignment::Target::PATH,
                                   "hot_water_system_id" => { "type" => %w[string null] } })
                         .merge("type" => %w[object null],
                                "description" => "The Piping group holding it, or null outside one or when the " \
                                                 "group's record cannot be read."),
        "reason" => { "type" => %w[string null], "enum" => [nil, "outside_group"],
                      "description" => "outside_group when the Edge's parent is no Piping group; null otherwise." },
        "values" => VALUES.merge("description" => "The assignment's values as stored; empty with none."),
        "copied" => { "type" => "boolean",
                      "description" => "Another Edge carries the same assignment id, as a split or copy leaves it." },
        "record_problem" => { "type" => %w[string null], "description" => "Why the stored record is invalid or " \
                                                                          "unreadable, or null." },
        "write_refusal" => REFUSAL.merge("description" => "What a write to the Edge meets, or null.")
      })
      IGNORED = {
        "ignored" => Shapes.list(Shapes.object({ "persistent_id" => { "type" => "integer" }, "type" => Shapes::TEXT }))
                           .merge("description" => "Selected entities that are not Edges, the first " \
                                                   "#{Assignment::Selection::IGNORED_ROWS}; never assigned."),
        "ignored_total" => { "type" => "integer", "minimum" => 0 }
      }.freeze
      MAKE_REFUSAL = {
        "make_refusal" => REFUSAL.merge("description" => "What groups.make over every selected line meets, or null " \
                                                         "when it can run with each row's path.")
      }.freeze
      SELECTION_ALL = Shapes.object({ "edges" => Shapes.list(ROW) }.merge(IGNORED).merge(MAKE_REFUSAL))
      SELECTION_PAGE_RESULT = Shapes.object({ "edges" => Shapes.list(ROW), "next_cursor" => Pages::NEXT_CURSOR,
                                              "total" => Pages::TOTAL }.merge(IGNORED).merge(MAKE_REFUSAL))
      PRECONDITIONS = ["Each Edge sits directly in a Piping group outside every Zone, reached through no locked or " \
                       "shared storage.",
                       "Each target carries the reference and values pipes.selection last read."].freeze

      module_function

      def install(feature)
        feature.reference_target(Assignment::TARGET)
        install_writes(feature)
        feature.query("#{PREFIX}.selection",
                      :description => "One bounded page of the selected Edges under the active path, each with the " \
                                      "Piping group holding it, its assignment and the refusal a write meets; other " \
                                      "entities are reported as ignored, with what making a " \
                                      "Piping group from the selection meets.",
                      :refuses => SELECTION_PAGE,
                      :params => Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                               :optional => %w[limit cursor]),
                      :result => SELECTION_PAGE_RESULT,
                      :examples => [{}, { "limit" => 50 }]) { |request| Assignment::Selection.page(request) }
        feature.query("#{PREFIX}.selection_all",
                      :description => "Every selected Edge in one read, for the panel.",
                      :response => { "bounded" => false, "prefer" => "#{PREFIX}.selection" },
                      :refuses => SELECTION, :params => Shapes::NONE, :result => SELECTION_ALL,
                      :examples => [{}]) { |request| Assignment::Selection.all(request) }
        feature.snapshot_section("#{PREFIX}.selected", :query => "#{PREFIX}.selection_all")
      end

      def install_writes(feature)
        feature.action("#{PREFIX}.assign",
                       :description => "Give explicit Edges in Piping groups one Pipe Type, a role and the role's " \
                                       "values, or reassign them; a stale or unwritable target refuses the whole " \
                                       "command.",
                       :refuses => ASSIGN, :params => ASSIGN_PARAMS,
                       :result => Shapes.object({ "edge_ids" => Shapes.described(Shapes.list(Shapes::TEXT),
                                                                                 "Assignment ids written; empty " \
                                                                                 "when nothing changed.") }),
                       :undo_name => "Assign Pipe", :preconditions => PRECONDITIONS,
                       :side_effects => "Writes one pipe assignment record on each Edge.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE }], "pipe_type_id" => "ppt_Ab12Cd34Ef56",
                                       "role" => "trunk", "multiplier" => 12 }]) do |request, proposal|
          params = request.params
          Assignment::Operations.assign(request, proposal, :targets => params.fetch("targets"),
                                                           :pipe_type_id => params.fetch("pipe_type_id"),
                                                           :role => params.fetch("role"),
                                                           :role_values => params.slice(*ROLE_KEYS))
        end
        feature.action("#{PREFIX}.clear",
                       :description => "Remove the pipe assignment from explicit Edges.",
                       :refuses => CLEAR, :params => Shapes.object({ "targets" => TARGETS }),
                       :result => Shapes.object({ "cleared" => { "type" => "integer", "minimum" => 0 } }),
                       :undo_name => "Clear Pipe", :preconditions => PRECONDITIONS,
                       :side_effects => "Removes the pipe assignment record from each Edge.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE.merge(
                         "entity_id" => "ppe_Ab12Cd34Ef56"
                       ) }] }]) do |request, proposal|
          LineGroups::EdgeOperations.clear(LINE_GROUP, request, proposal, request.params.fetch("targets"),
                                           :limit => Assignment.gesture_edge_limit)
        end
      end
    end
  end
end
