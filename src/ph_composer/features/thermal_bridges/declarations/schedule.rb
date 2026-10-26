# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # What the schedule registers: the bounded read, the whole read, and runs.locate. Each read walks the
    # Model, so it shows the geometry as it is. It is read on request and registers no snapshot section,
    # since one read costs about two seconds at 5,000 assigned Edges (context/TECH_STACK.md, "Edge-owned
    # assignments").
    module ScheduleRegistration
      PREFIX = "#{FEATURE_ID}.schedule".freeze
      LOCATE = "#{FEATURE_ID}.runs.locate".freeze
      PATH = Assignment::Target::PATH
      # Zones answers containment and Face classification; one invalid Face record or unreadable Thermal
      # Bridge Type refuses the read as it refuses Zones' and the catalog's own.
      READ = %w[record.unreadable validation.failed].freeze
      PAGE = (READ + %w[query.cursor_expired query.limit_invalid]).freeze
      LOCATE_REFUSES = %w[target.not_found target.locked target.wrong_kind target.shared_definition
                          thermal_bridge.hidden].freeze

      NUMBER = { "type" => "number" }.freeze
      NULLABLE_NUMBER = { "type" => %w[number null] }.freeze
      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      EDGE_PATHS = Shapes.list(PATH).merge("description" => "Root-to-Edge persistent-id paths.")
      LOCATE_PARAMS = Shapes.object({ "edge_paths" => EDGE_PATHS.merge(
        "minItems" => 1, "maxItems" => Pages::MAXIMUM_LIMIT,
        "description" => "The Edges of one run, or of one finding, as the schedule reads them."
      ) })
      FINDING = Shapes.object({
        "code" => Shapes::TEXT, "message" => Shapes::TEXT,
        "blocks_export" => { "type" => "boolean" },
        "locate" => LOCATE_PARAMS.merge("description" => "The params runs.locate takes to show the Edges named.")
      })
      ZONE = Shapes.object({ "zone_id" => Shapes::TEXT, "zone_path" => PATH, "name" => Shapes::TEXT,
                             "building_segment" => { "type" => %w[string null] } })
      RUN = Shapes.object({
        "identifier" => Shapes.described(Shapes::TEXT, "tb_ and a digest of the Zone, type, container path and " \
                                                       "points; derived, and it changes with the geometry."),
        "display_name" => Shapes.described(Shapes::TEXT, "The type name and a counter, numbered per type."),
        "zone" => ZONE, "type_id" => Shapes::TEXT,
        "type_name" => Shapes.described({ "type" => %w[string null] }, "Null when the type no longer exists."),
        "group" => { "type" => %w[string null], "enum" => Type::GROUPS + [nil] },
        "psi_w_mk" => NULLABLE_NUMBER, "quantity" => NUMBER, "length_m" => NUMBER,
        "heat_loss_w_k" => Shapes.described(NULLABLE_NUMBER, "psi times length times quantity; null without a " \
                                                             "psi-value."),
        "closed" => { "type" => "boolean" },
        "points_m" => Shapes.described(Shapes.list({ "type" => "array", "items" => NUMBER }),
                                       "World points in metres, in order; a closed run repeats its first point."),
        "edge_paths" => EDGE_PATHS.merge("description" => "Edge i joins points i and i + 1."),
        "shared" => Shapes.described({ "type" => "boolean" }, "Whether any Edge is in shared component storage."),
        "findings" => Shapes.list(FINDING), "locate" => LOCATE_PARAMS
      })
      TOTALS = Shapes.object({
        "by_type" => Shapes.list(Shapes.object({
          "type_id" => Shapes::TEXT, "type_name" => { "type" => %w[string null] },
          "group" => { "type" => %w[string null] }, "run_count" => COUNT, "edge_count" => COUNT,
          "length_m" => NUMBER, "heat_loss_w_k" => NULLABLE_NUMBER
        })).merge("description" => "Each type with a run; used length and heat loss over every run of it."),
        "by_group" => Shapes.list(Shapes.object({ "group" => Shapes::TEXT, "heat_loss_w_k" => NUMBER }))
                            .merge("description" => "Every group, zero with no run; a run without a psi-value " \
                                                    "adds nothing."),
        "run_count" => COUNT, "heat_loss_w_k" => NUMBER
      })
      EDGE_FINDING = Shapes.object(FINDING.fetch("properties").merge("path" => PATH))
      UNREADABLE = Shapes.object({ "path" => PATH, "code" => Shapes::TEXT, "message" => Shapes::TEXT })
      ALL = {
        "runs" => Shapes.list(RUN),
        "edge_findings" => Shapes.list(EDGE_FINDING).merge("description" => "Assigned Edges in no run because no " \
                                                                            "Zone holds them; not exported."),
        "edge_finding_total" => COUNT,
        "unreadable" => Shapes.list(UNREADABLE).merge("description" => "Assignments that are not valid; not counted."),
        "unreadable_total" => COUNT, "totals" => TOTALS,
        "units" => Shapes.object({ "length_m" => Shapes::TEXT, "psi_w_mk" => Shapes::TEXT,
                                   "heat_loss_w_k" => Shapes::TEXT })
      }.freeze
      LIST_RESULT = Shapes.object(ALL.merge(
        "runs" => Shapes.list(RUN).merge("description" => "One page of runs in schedule order."),
        "edge_findings" => ALL.fetch("edge_findings").merge("description" => "The first #{Scan::DETAIL_ROWS}."),
        "unreadable" => ALL.fetch("unreadable").merge("description" => "The first #{Scan::DETAIL_ROWS}."),
        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
      ))
      LIST_PARAMS = Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR }, :optional => %w[limit cursor])
      LOCATE_RESULT = Shapes.object({ "path" => PATH.merge("description" => "The edit path afterwards."),
                                      "selected" => COUNT })
      EXAMPLE_PATHS = { "edge_paths" => [[1201, 1205], [1201, 1206]] }.freeze

      module_function

      def install(feature)
        feature.query("#{PREFIX}.list",
                      :description => "One bounded page of thermal-bridge runs, each with its Zone, type, length, " \
                                      "psi-value, quantity, heat loss and findings, with totals over every run.",
                      :refuses => PAGE, :params => LIST_PARAMS, :result => LIST_RESULT,
                      :examples => [{}, { "limit" => 20 }]) { |request| Scan.page(request) }
        feature.query("#{PREFIX}.all",
                      :description => "The whole schedule in one read, for the panel's Schedule on open and Refresh.",
                      :response => { "bounded" => false, "prefer" => "#{PREFIX}.list" },
                      :refuses => READ, :params => Shapes::NONE, :result => Shapes.object(ALL),
                      :examples => [{}]) { |request| Scan.schedule(request) }
        feature.view_command(LOCATE,
                             :description => "Select the Edges of one run and bring them into view, opening the " \
                                             "context that holds them.",
                             :refuses => LOCATE_REFUSES, :params => LOCATE_PARAMS, :result => LOCATE_RESULT,
                             :preconditions => ["Every Edge sits in one container and none is hidden."],
                             :side_effects => "Selects and frames the Edges. #{ContextCommands::SIDE_EFFECTS}",
                             :examples => [EXAMPLE_PATHS]) do |request|
          RunLocate.call(request, :edge_paths => request.params.fetch("edge_paths"))
        end
      end
    end
  end
end
