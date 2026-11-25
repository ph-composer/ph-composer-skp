# frozen_string_literal: true

module PhComposer
  module Ducting
    # What the duct assignment registers: the duct reference target, assign and clear over explicit Edges, and the
    # selection read with its panel section. Each write is one native Undo step.
    module DuctRegistration
      PREFIX = "#{FEATURE_ID}.ducts".freeze
      Shapes = Mechanical::Shapes
      ASSIGN = (GroupRegistration::LOCATE + %W[gesture.too_large #{Codes::GROUP_IN_ZONE} #{Codes::GROUP_NESTED}
                                               #{Codes::OUTSIDE_GROUP}]).freeze
      CLEAR = (ASSIGN + %w[copy.rule_missing reference.in_use]).freeze
      SELECTION = %w[gesture.too_large record.unreadable validation.failed].freeze
      SELECTION_PAGE = (SELECTION + %w[query.cursor_expired query.limit_invalid]).freeze
      VALUE_KEYS = Assignment::VALUE_SCHEMAS.keys.freeze

      REFERENCE = Assignment::REFERENCE
      VALUES = { "type" => "object" }.freeze
      TARGETS = Shapes.list(Shapes.object({ "reference" => REFERENCE,
                                            "expected_values" => VALUES.merge(
                                              "description" => "The Edge's assignment values as last read; {} or " \
                                                               "absent for an Edge with none. A changed value " \
                                                               "refuses as target.changed."
                                            ) }, :optional => ["expected_values"]))
                      .merge("minItems" => 1,
                             "description" => "Explicit Edges, as ducts.selection returns them; at most " \
                                              "#{Assignment::GESTURE_EDGE_LIMIT}.")
      EXAMPLE = { "group_path" => [1301], "entity_path" => [1301, 1305], "entity_id" => nil }.freeze
      KEPT = " An Edge already assigned keeps it when not given; an Edge with none needs it."
      ASSIGN_PARAMS = Shapes.object({
        "targets" => TARGETS,
        "duct_type_id" => Shapes.id(DuctType::KIND.id_prefix, "The Duct Type every Edge gets.#{KEPT}"),
        "direction" => Assignment::VALUE_SCHEMAS.fetch("direction")
                                                .merge("description" => "outdoor_air (shown Outdoor air) or " \
                                                                        "exhaust_air (shown Exhaust air).#{KEPT}"),
        "quantity" => Assignment::VALUE_SCHEMAS.fetch("quantity")
                                               .merge("description" => "How many identical ducts each line stands " \
                                                                       "for. An Edge already assigned keeps its " \
                                                                       "own when not given; an Edge with none " \
                                                                       "takes 1.")
      }, :optional => VALUE_KEYS).freeze
      ROW = Shapes.object({
        "path" => LineGroups::PATH,
        "reference" => REFERENCE.merge("type" => %w[object null],
                                       "description" => "The Edge's reference, or null when it is not directly in " \
                                                        "a Ducting group."),
        "group" => Shapes.object({ "group_id" => Shapes::TEXT, "group_path" => LineGroups::PATH,
                                   "ventilator_id" => { "type" => %w[string null] } })
                         .merge("type" => %w[object null],
                                "description" => "The Ducting group holding it, or null outside one or when the " \
                                                 "group's record cannot be read."),
        "reason" => { "type" => %w[string null], "enum" => [nil, "outside_group"],
                      "description" => "outside_group when the Edge's parent is no Ducting group; null otherwise." },
        "values" => VALUES.merge("description" => "The assignment's values as stored; empty with none."),
        "copied" => { "type" => "boolean",
                      "description" => "Another Edge carries the same assignment id, as a split or copy leaves it." },
        "record_problem" => { "type" => %w[string null], "description" => "Why the stored record is invalid or " \
                                                                          "unreadable, or null." },
        "write_refusal" => GroupRegistration::REFUSAL.merge("description" => "What a write to the Edge meets, or null.")
      })
      IGNORED = {
        "ignored" => Shapes.list(Shapes.object({ "persistent_id" => { "type" => "integer" }, "type" => Shapes::TEXT }))
                           .merge("description" => "Selected entities that are not Edges, the first " \
                                                   "#{LineGroups::Selection::IGNORED_ROWS}; never assigned."),
        "ignored_total" => { "type" => "integer", "minimum" => 0 }
      }.freeze
      PRECONDITIONS = ["Each Edge sits directly in a Ducting group outside every Zone, reached through no locked or " \
                       "shared storage.",
                       "Each target carries the reference and values ducts.selection last read."].freeze

      module_function

      def install(feature)
        feature.reference_target(Assignment::TARGET)
        install_writes(feature)
        feature.query("#{PREFIX}.selection",
                      :description => "One bounded page of the selected Edges under the active path, each with the " \
                                      "Ducting group holding it, its assignment and the refusal a write meets; other " \
                                      "entities are reported as ignored.",
                      :refuses => SELECTION_PAGE,
                      :params => Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                               :optional => %w[limit cursor]),
                      :result => Shapes.object({ "edges" => Shapes.list(ROW), "next_cursor" => Pages::NEXT_CURSOR,
                                                 "total" => Pages::TOTAL }.merge(IGNORED)),
                      :examples => [{}, { "limit" => 50 }]) { |request| Assignment::Selection.page(request) }
        feature.query("#{PREFIX}.selection_all",
                      :description => "Every selected Edge in one read, for the panel.",
                      :response => { "bounded" => false, "prefer" => "#{PREFIX}.selection" },
                      :refuses => SELECTION, :params => Shapes::NONE,
                      :result => Shapes.object({ "edges" => Shapes.list(ROW) }.merge(IGNORED)),
                      :examples => [{}]) { |request| Assignment::Selection.all(request) }
        feature.snapshot_section("#{PREFIX}.selected", :query => "#{PREFIX}.selection_all")
      end

      def install_writes(feature)
        feature.action("#{PREFIX}.assign",
                       :description => "Give explicit Edges in Ducting groups a Duct Type, a direction and a " \
                                       "quantity, or change any of them; a stale or unwritable target refuses the " \
                                       "whole command.",
                       :refuses => ASSIGN, :params => ASSIGN_PARAMS,
                       :result => Shapes.object({ "edge_ids" => Shapes.described(Shapes.list(Shapes::TEXT),
                                                                                 "Assignment ids written; empty " \
                                                                                 "when nothing changed.") }),
                       :undo_name => "Assign Duct", :preconditions => PRECONDITIONS,
                       :side_effects => "Writes one duct assignment record on each Edge.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE }], "duct_type_id" => "dct_Ab12Cd34Ef56",
                                       "direction" => "outdoor_air" },
                                     { "targets" => [{ "reference" => EXAMPLE.merge("entity_id" => "dce_Ab12Cd34Ef56"),
                                                       "expected_values" => { "quantity" => 1 } }],
                                       "quantity" => 2 }]) do |request, proposal|
          Assignment::Operations.assign(request, proposal, :targets => request.params.fetch("targets"),
                                                           :values => request.params.slice(*VALUE_KEYS))
        end
        feature.action("#{PREFIX}.clear",
                       :description => "Remove the duct assignment from explicit Edges.",
                       :refuses => CLEAR, :params => Shapes.object({ "targets" => TARGETS }),
                       :result => Shapes.object({ "cleared" => { "type" => "integer", "minimum" => 0 } }),
                       :undo_name => "Clear Duct", :preconditions => PRECONDITIONS,
                       :side_effects => "Removes the duct assignment record from each Edge.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE.merge(
                         "entity_id" => "dce_Ab12Cd34Ef56"
                       ) }] }]) do |request, proposal|
          LineGroups::EdgeOperations.clear(LINE_GROUP, request, proposal, request.params.fetch("targets"),
                                           :limit => Assignment.gesture_edge_limit)
        end
      end
    end
  end
end
