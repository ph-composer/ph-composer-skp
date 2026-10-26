# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # What Edge assignment registers: the Edge reference target, assign and clear, and the selection read
    # with its panel section. Each write is one native Undo step over explicit Edge references.
    module AssignmentRegistration
      PREFIX = "#{FEATURE_ID}.edges".freeze
      # Resolving an explicit Edge inside a Zone for a write: Zones' target codes, which pass through.
      TARGET_CODES = %w[record.unreadable target.ambiguous target.changed target.locked target.not_found
                        target.shared_definition target.wrong_hierarchy target.wrong_kind target.wrong_zone
                        validation.failed].freeze
      ASSIGN = (TARGET_CODES + %w[gesture.too_large]).freeze
      CLEAR = (ASSIGN + %w[copy.rule_missing reference.in_use]).freeze
      SELECTION = %w[gesture.too_large record.unreadable validation.failed].freeze
      SELECTION_PAGE = (SELECTION + %w[query.cursor_expired query.limit_invalid]).freeze

      REFERENCE = Assignment::Target::REFERENCE
      # An assignment's values as stored: thermal_bridge_type_id and quantity, or whatever an invalid record
      # holds, so a read never refuses the record it is there to help clear.
      VALUES = { "type" => "object" }.freeze
      EXPECTED = VALUES.merge("description" => "The Edge's assignment values as last read; {} or absent for an Edge " \
                                               "with none. A changed value refuses as target.changed.")
      TARGETS = Shapes.list(Shapes.object({ "reference" => REFERENCE, "expected_values" => EXPECTED },
                                          :optional => ["expected_values"]))
                      .merge("minItems" => 1,
                             "description" => "Explicit Edge occurrences, as edges.selection returns them; at most " \
                                              "#{Assignment::GESTURE_EDGE_LIMIT}.")
      EXAMPLE_REFERENCE = { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201], "entity_path" => [1205],
                            "entity_id" => nil }.freeze
      ASSIGN_PARAMS = Shapes.object({
        "targets" => TARGETS,
        "thermal_bridge_type_id" => Shapes.id(Type::KIND.id_prefix, "The Thermal Bridge Type every Edge gets."),
        "quantity" => { "type" => "number", "exclusiveMinimum" => 0,
                        "description" => "How many times each Edge counts; 1 when absent." }
      }, :optional => ["quantity"]).freeze
      ZONE = Shapes.object({ "zone_id" => Shapes::TEXT, "zone_path" => Assignment::Target::PATH,
                             "name" => Shapes::TEXT, "building_segment" => { "type" => %w[string null] },
                             "level" => { "type" => %w[string null] } })
                   .merge("type" => %w[object null], "description" => "The Zone holding the Edge, as " \
                                                                      "ph_composer.zones.containment reads it.")
      REFUSAL = Shapes.object({ "code" => Shapes::TEXT, "message" => Shapes::TEXT })
                      .merge("type" => %w[object null],
                             "description" => "The refusal a write to the Edge meets from its path, or null.")
      SELECTED_ROW = Shapes.object({
        "path" => Assignment::Target::PATH,
        "reference" => REFERENCE.merge("type" => %w[object null],
                                       "description" => "The Edge's reference, or null when no Zone holds it."),
        "zone" => ZONE,
        "reason" => { "type" => %w[string null], "description" => "Why no Zone holds it; null with a Zone." },
        "values" => VALUES.merge("description" => "The Edge's assignment values as stored (thermal_bridge_type_id " \
                                                  "and quantity); empty when it has none."),
        "copied" => { "type" => "boolean",
                      "description" => "Whether another Edge carries the same assignment id, as a split or a copy " \
                                       "leaves it. Routine; nothing repairs it." },
        "record_problem" => { "type" => %w[string null],
                              "description" => "Why the stored assignment is invalid, or null. An invalid one can " \
                                               "still be cleared or reassigned." },
        "write_refusal" => REFUSAL
      })
      SELECTION_ALL = Shapes.object({
        "edges" => Shapes.list(SELECTED_ROW),
        "ignored" => Shapes.list(Shapes.object({ "persistent_id" => { "type" => "integer" }, "type" => Shapes::TEXT }))
                           .merge("description" => "Selected entities that are not Edges, the first " \
                                                   "#{Assignment::Selection::IGNORED_ROWS}; never assigned."),
        "ignored_total" => { "type" => "integer", "minimum" => 0,
                             "description" => "How many selected entities are not Edges." }
      })
      PAGE_PROPERTIES = { "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL }.freeze
      SELECTION_PAGE_RESULT = Shapes.object(SELECTION_ALL.fetch("properties").merge(PAGE_PROPERTIES))
      SELECTION_PARAMS = Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                       :optional => %w[limit cursor])
      CLEAR_RESULT = Shapes.object({ "cleared" => { "type" => "integer", "minimum" => 0,
                                                    "description" => "Edges whose assignment was removed." } })
      PRECONDITIONS = ["Each Edge is inside a Zone, reached through no shared, locked or other Zone storage.",
                       "Each target carries the reference and values edges.selection last read."].freeze

      module_function

      def install(feature)
        feature.reference_target(Assignment::TARGET)
        install_writes(feature)
        feature.query("#{PREFIX}.selection",
                      :description => "One bounded page of the selected Edges under the active path, each with the " \
                                      "Zone holding it, its assignment and the refusal a write meets; other " \
                                      "entities are reported as ignored.",
                      :refuses => SELECTION_PAGE, :params => SELECTION_PARAMS, :result => SELECTION_PAGE_RESULT,
                      :examples => [{}, { "limit" => 50 }]) { |request| Assignment::Selection.page(request) }
        feature.query("#{PREFIX}.selection_all",
                      :description => "Every selected Edge in one read, for the panel and the menu route.",
                      :response => { "bounded" => false, "prefer" => "#{PREFIX}.selection" },
                      :refuses => SELECTION, :params => Shapes::NONE, :result => SELECTION_ALL,
                      :examples => [{}]) { |request| Assignment::Selection.all(request) }
        feature.snapshot_section("#{PREFIX}.selected", :query => "#{PREFIX}.selection_all")
      end

      def install_writes(feature)
        feature.action("#{PREFIX}.assign",
                       :description => "Assign one Thermal Bridge Type and quantity to explicit Edges, or reassign " \
                                       "them; a stale or unwritable target refuses the whole command.",
                       :refuses => ASSIGN, :params => ASSIGN_PARAMS,
                       :result => Shapes.object({ "edge_ids" => Shapes.list(Shapes::TEXT).merge(
                         "description" => "Assignment ids written; empty when every Edge already held these values."
                       ) }),
                       :undo_name => "Assign Thermal Bridge", :preconditions => PRECONDITIONS,
                       :side_effects => "Writes one assignment record on each Edge.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE_REFERENCE }],
                                       "thermal_bridge_type_id" => Shapes.example_id(Type::KIND),
                                       "quantity" => 1 }]) do |request, proposal|
          params = request.params
          Assignment::Operations.assign(request, proposal,
                                        :targets => params.fetch("targets"),
                                        :thermal_bridge_type_id => params.fetch("thermal_bridge_type_id"),
                                        :quantity => params.fetch("quantity", Assignment::DEFAULT_QUANTITY))
        end
        feature.action("#{PREFIX}.clear",
                       :description => "Remove the thermal bridge assignment from explicit Edges.",
                       :refuses => CLEAR, :params => Shapes.object({ "targets" => TARGETS }),
                       :result => CLEAR_RESULT,
                       :undo_name => "Clear Thermal Bridge", :preconditions => PRECONDITIONS,
                       :side_effects => "Removes the assignment record from each Edge.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE_REFERENCE.merge(
                         "entity_id" => "tbe_Ab12Cd34Ef56"
                       ) }] }]) do |request, proposal|
          Assignment::Operations.clear(request, proposal, :targets => request.params.fetch("targets"))
        end
      end
    end
  end
end
