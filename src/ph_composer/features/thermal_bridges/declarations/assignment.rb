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
      POINT = { "type" => "array", "items" => { "type" => "number" }, "minItems" => 3, "maxItems" => 3,
                "x-unit" => "m" }.freeze
      PATH_ROW = Shapes.object(SELECTED_ROW.fetch("properties").merge(
        "reason" => { "type" => %w[string null],
                      "description" => "Why there is no reference: not_found or not_an_edge when the path names no " \
                                       "Edge, otherwise why no Zone holds it, as zones.containment reads it; null " \
                                       "with a Zone." },
        "hidden" => { "type" => %w[boolean null],
                      "description" => "Hidden itself, or on a hidden tag or tag folder; null with no Edge." },
        "endpoints_m" => Shapes.list(POINT).merge("type" => %w[array null],
                                                  "description" => "The Edge's two ends in world metres, through " \
                                                                   "every transform from the root; null with no Edge."),
        "truncated" => { "type" => "array", "items" => { "type" => "string" },
                         "description" => "Zone labels cut to #{OccurrencePath::NAME_CHARACTERS} characters, such as " \
                                          "zone.name; absent when none was." }
      ), :optional => ["truncated"])
      PATH_PAGE = { "edges" => Shapes.list(PATH_ROW), "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL,
                    "units" => Shapes.object({ "endpoints_m" => { "type" => "string", "enum" => ["m"] } }) }.freeze
      AT_PARAMS = Shapes.object({
        "paths" => Shapes.list(Assignment::Target::PATH.merge("minItems" => 1))
                         .merge("minItems" => 1, "maxItems" => Pages::MAXIMUM_LIMIT,
                                "description" => "Root-to-Edge persistent-id paths, such as a schedule run's " \
                                                 "edge_paths; answered in this order."),
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[limit cursor]).freeze
      CANDIDATE_PARAMS = Shapes.object({
        "path" => Assignment::Target::PATH.merge("description" => "The root-to-container path, a Zone's or a Group's " \
                                                                  "inside it; [] or absent for the Model root."),
        "assigned" => { "type" => "string", "enum" => Assignment::PathReads::ASSIGNED,
                        "description" => "Only Edges with an assignment record, or only those without; any when " \
                                         "absent." },
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[path assigned limit cursor]).freeze
      CONTAINER = Shapes.object({ "path" => Assignment::Target::PATH,
                                  "locked" => { "type" => "boolean", "description" => "A step on the path is locked." },
                                  "hidden" => { "type" => "boolean", "description" => "A step on the path is hidden." },
                                  "shared" => { "type" => "boolean",
                                                "description" => "A step on the path is shared storage." } })
      PATH_READ = %w[query.cursor_expired query.limit_invalid validation.failed record.unreadable].freeze
      CLEAR_RESULT = Shapes.object({ "cleared" => { "type" => "integer", "minimum" => 0,
                                                    "description" => "Edges whose assignment was removed." } })
      PRECONDITIONS = ["Each Edge is inside a Zone, reached through no shared, locked or other Zone storage.",
                       "Each target carries the reference and values edges.selection last read."].freeze
      REPAIR = %w[record.unreadable reference.in_use target.changed target.locked target.not_found
                  target.shared_definition target.wrong_kind thermal_bridge.repair_not_needed].freeze
      FINGERPRINT = { "type" => "string", "pattern" => "^[0-9a-f]{64}$",
                      "description" => "SHA-256 of the stored text (a non-text value's canonical JSON), hex, as " \
                                       "edges.repair_candidates gives it." }.freeze
      REPAIR_ROW = Shapes.object({
        "path" => Assignment::Target::PATH,
        "condition" => { "type" => "string", "enum" => %w[unreadable stranded],
                         "description" => "unreadable: the stored text is not a JSON object; stranded: a readable " \
                                          "record on an Edge no Zone holds, which edges.clear cannot name." },
        "containment" => { "type" => %w[string null],
                           "description" => "Why no Zone holds the Edge, as zones.containment reads it; null in " \
                                            "a Zone." },
        "fingerprint" => FINGERPRINT, "bytes" => { "type" => "integer", "minimum" => 0 },
        "record" => { "type" => %w[object null],
                      "description" => "A readable record's id, thermal_bridge_type_id and quantity; null otherwise." },
        "write_refusal" => REFUSAL
      })
      REPAIR_PARAMS = Shapes.object({
        "path" => Assignment::Target::PATH.merge("minItems" => 1,
                                                 "description" => "The root-to-Edge persistent-id path."),
        "fingerprint" => FINGERPRINT
      }).freeze
      REPAIR_RESULT = Shapes.object({
        "path" => Assignment::Target::PATH,
        "condition" => REPAIR_ROW.dig("properties", "condition"),
        "containment" => REPAIR_ROW.dig("properties", "containment"),
        "stored" => { "type" => "object",
                      "description" => "The text removed: bytes, sha256, readable, valid and excerpt, its first " \
                                       "#{Assignment::Repair::EXCERPT} characters." },
        "discarded" => { "type" => %w[object null],
                         "description" => "What a readable record held: id, thermal_bridge_type_id, quantity, the " \
                                          "first #{Assignment::Repair::MAX_KEYS} user_data_keys and " \
                                          "extension_namespaces with user_data_key_total and " \
                                          "extension_namespace_total; a long or structured value cut and named " \
                                          "in truncated; null for unreadable text." }
      })

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
        install_path_reads(feature)
        install_repair(feature)
      end

      def install_repair(feature)
        feature.query(Assignment::Repair::CANDIDATES,
                      :description => "One bounded page of the Edges whose stored assignment edges.clear cannot " \
                                      "reach: text that is not a JSON object anywhere, or a readable record on an " \
                                      "Edge no Zone holds. Each row gives the fingerprint edges.repair takes. " \
                                      "Removing a readable record needs every assignment readable, so repair the " \
                                      "unreadable ones first.",
                      :refuses => %w[query.cursor_expired query.limit_invalid],
                      :params => SELECTION_PARAMS,
                      :result => Shapes.object({ "edges" => Shapes.list(REPAIR_ROW) }.merge(PAGE_PROPERTIES)),
                      :examples => [{}, { "limit" => 50 }]) { |request| Assignment::Repair.candidates(request) }
        feature.action(Assignment::Repair::ACTION,
                       :description => "Remove one Edge's unreadable or stranded thermal-bridge assignment, named by " \
                                       "its root-to-Edge path and the fingerprint of the text read; the preview " \
                                       "says what is discarded. Geometry, the Type and every other record stay.",
                       :refuses => REPAIR, :params => REPAIR_PARAMS, :result => REPAIR_RESULT,
                       :undo_name => "Repair Thermal Bridge Assignment",
                       :preconditions => ["The Edge's path crosses no locked or shared storage.",
                                          "The stored text is still the one the fingerprint names."],
                       :side_effects => "Removes the ph_composer.thermal_bridge record from that one Edge.",
                       :examples => [{ "path" => [1201, 1205], "fingerprint" => "0" * 64 }]) do |request, proposal|
          Assignment::Repair.repair(request, proposal, :path => request.params.fetch("path"),
                                                       :fingerprint => request.params.fetch("fingerprint"))
        end
      end

      def install_path_reads(feature)
        feature.query(Assignment::PathReads::AT,
                      :description => "The Edges at explicit root-to-Edge paths, a bounded page at a time in the " \
                                      "order given, each with the Zone holding it, its complete reference, its " \
                                      "assignment and the refusal a write meets, as edges.selection reads them, and " \
                                      "its world endpoints. Needs no selection; a path naming no Edge is a row " \
                                      "with its reason.",
                      :refuses => PATH_READ, :params => AT_PARAMS, :result => Shapes.object(PATH_PAGE),
                      :examples => [{ "paths" => [[1201, 1205]] }]) { |request| Assignment::PathReads.at(request) }
        feature.query(Assignment::PathReads::CANDIDATES,
                      :description => "One bounded page of the Edges directly inside one container, the root when " \
                                      "path is absent, by persistent id, in edges.at's rows: with assigned " \
                                      "\"unassigned\", the Edges an assignment could start from. Needs no " \
                                      "selection; walks that container only.",
                      :refuses => (PATH_READ + %w[target.not_found target.wrong_kind]).uniq,
                      :params => CANDIDATE_PARAMS,
                      :result => Shapes.object(PATH_PAGE.merge("container" => CONTAINER)),
                      :examples => [{ "path" => [1201], "assigned" => "unassigned" }]) do |request|
          Assignment::PathReads.candidates(request)
        end
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
