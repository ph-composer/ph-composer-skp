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
      LOCATE_REFUSES = %w[session.inactive target.not_found target.locked target.wrong_kind
                          target.shared_definition thermal_bridge.hidden].freeze

      NUMBER = { "type" => "number" }.freeze
      NULLABLE_NUMBER = { "type" => %w[number null] }.freeze
      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      # One locate takes a whole run, however long, since a second call would replace the first selection.
      # The bound only stops a runaway request; a run this long is not a real thermal bridge.
      LOCATE_EDGE_LIMIT = 10_000
      EDGE_PATHS = Shapes.list(PATH).merge("description" => "Root-to-Edge persistent-id paths.")
      LOCATE_PARAMS = Shapes.object({ "edge_paths" => EDGE_PATHS.merge(
        "minItems" => 1, "maxItems" => LOCATE_EDGE_LIMIT,
        "description" => "The Edges of one run, or of one finding, as the schedule reads them."
      ) })
      # A finding names every Edge it is about, as runs.locate takes them.
      FINDING = Shapes.object({
        "code" => Shapes::TEXT, "message" => Shapes::TEXT,
        "blocks_export" => { "type" => "boolean" },
        "locate" => Shapes.object({ "edge_paths" => EDGE_PATHS })
                          .merge("description" => "The Edges named, as runs.locate takes them.")
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
        "edge_paths" => EDGE_PATHS.merge("description" => "Edge i joins points i and i + 1; runs.locate takes " \
                                                          "them as its edge_paths."),
        "shared" => Shapes.described({ "type" => "boolean" }, "Whether any Edge is in shared component storage."),
        "findings" => Shapes.list(FINDING)
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
      # A run row as schedule.list answers it: whole, or with compact without its points, its Edge paths and
      # each finding's Edges, counted instead.
      LIST_FINDING = Shapes.object(FINDING.fetch("properties").merge("edge_count" => COUNT),
                                   :optional => %w[locate edge_count])
      LIST_RUN = Shapes.object(
        RUN.fetch("properties").merge(
          "edge_count" => COUNT.merge("description" => "With compact: how many Edges."),
          "point_count" => COUNT.merge("description" => "With compact: how many points."),
          "index" => COUNT.merge("description" => "With compact: the run's place in the schedule, which names it " \
                                                  "to #{Scan::MEMBERS} when two runs share an identifier."),
          "findings" => Shapes.list(LIST_FINDING).merge("description" => "With compact, each finding's Edges " \
                                                                         "counted; #{Scan::MEMBERS} with finding " \
                                                                         "pages them."),
          "truncated" => ContextChildren::TRUNCATED
        ), :optional => %w[points_m edge_paths index edge_count point_count truncated]
      )
      COMPACT_TOTALS = TOTALS.merge(
        "required" => TOTALS.fetch("required") - ["by_type"],
        "properties" => TOTALS.fetch("properties").merge(
          "type_count" => COUNT.merge("description" => "With compact: how many types by_type has; " \
                                                       "#{Scan::BY_TYPE} pages them.")
        ),
        "description" => "Over every run; with compact without by_type, counted in type_count."
      )
      LIST_RESULT_ANY = LIST_RESULT.merge(
        "required" => LIST_RESULT.fetch("required") - %w[edge_findings unreadable],
        "properties" => LIST_RESULT.fetch("properties").merge(
          "runs" => Shapes.list(LIST_RUN).merge("description" => "One page of runs in schedule order."),
          "totals" => COMPACT_TOTALS
        )
      )
      LIST_PARAMS = Shapes.object({
        "compact" => { "type" => "boolean",
                       "description" => "Leave out each run's points_m and edge_paths and each finding's Edges, " \
                                        "counted instead, and the Edge findings and unreadable assignments, which " \
                                        "#{Scan::EDGE_FINDINGS} and #{Scan::UNREADABLE} page; #{Scan::MEMBERS} " \
                                        "pages a run's Edges. False when absent." },
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[compact limit cursor])
      MEMBER_INDEX = COUNT.merge("description" => "The run's index from a compact schedule row; needed only when " \
                                                  "two runs share the identifier.").freeze
      MEMBER_FINDING = COUNT.merge("description" => "Only the Edges of the run's finding at this index.").freeze
      PAGING = Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR }, :optional => Pages::PAGE_KEYS)
      MEMBER = Shapes.object({
        "index" => COUNT.merge("description" => "The Edge's place in the run: it joins points_m i and i + 1."),
        "path" => PATH, "points_m" => Shapes.list(Shapes.list(NUMBER), :description => "Its world end points in " \
                                                                                       "metres, in run order.")
      })
      LOCATE_RESULT = Shapes.object({ "path" => PATH.merge("description" => "The edit path afterwards."),
                                      "selected" => COUNT })
      EXAMPLE_PATHS = { "edge_paths" => [[1201, 1205], [1201, 1206]] }.freeze

      module_function

      # The schedule's parts that grow with the Model, a bounded page at a time.
      def install_pages(feature)
        page = { "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL }
        feature.query(Scan::MEMBERS,
                      :description => "One bounded page of one run's Edges in run order, each with its path and " \
                                      "world end points, or only those one of its findings names.",
                      :refuses => PAGE + %w[target.ambiguous target.not_found],
                      :params => Shapes.object({
                        "identifier" => Shapes.described(Shapes::TEXT, "The run's identifier from the schedule."),
                        "index" => MEMBER_INDEX, "finding" => MEMBER_FINDING,
                        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
                      }, :optional => %w[index finding limit cursor]),
                      :result => Shapes.object({ "identifier" => Shapes::TEXT,
                                                 "members" => Shapes.list(MEMBER) }.merge(page)),
                      :examples => [{ "identifier" => "tb_0a1b2c3d4e5f" },
                                    { "identifier" => "tb_0a1b2c3d4e5f", "finding" => 0 }]) do |request|
          Scan.members(request)
        end
        feature.query(Scan::BY_TYPE,
                      :description => "One bounded page of the schedule's totals by Thermal Bridge Type, over " \
                                      "every run, as schedule.list's totals.by_type; a name over " \
                                      "#{OccurrencePath::NAME_CHARACTERS} characters is cut and named in truncated.",
                      :refuses => PAGE, :params => PAGING,
                      :result => Shapes.object({ "by_type" => TOTALS.dig("properties", "by_type").merge(
                        "items" => Shapes.object(TOTALS.dig("properties", "by_type", "items", "properties")
                                                       .merge("truncated" => ContextChildren::TRUNCATED),
                                                 :optional => ["truncated"])
                      ) }.merge(page)),
                      :examples => [{}]) { |request| Scan.by_type(request) }
        feature.query(Scan::EDGE_FINDINGS,
                      :description => "One bounded page of the assigned Edges no Zone holds, by path: in no run, " \
                                      "not exported.",
                      :refuses => PAGE, :params => PAGING,
                      :result => Shapes.object({ "edge_findings" => Shapes.list(EDGE_FINDING) }.merge(page)),
                      :examples => [{}]) { |request| Scan.edge_findings(request) }
        feature.query(Scan::UNREADABLE,
                      :description => "One bounded page of the Edge assignments that are not valid, by path; not " \
                                      "counted. A message over #{Scan::MAX_MESSAGE} characters is cut.",
                      :refuses => PAGE, :params => PAGING,
                      :result => Shapes.object({ "unreadable" => Shapes.list(UNREADABLE) }.merge(page)),
                      :examples => [{}]) { |request| Scan.unreadable(request) }
      end

      def install(feature)
        feature.query("#{PREFIX}.list",
                      :description => "One bounded page of thermal-bridge runs, each with its Zone, type, length, " \
                                      "psi-value, quantity, heat loss and findings, with totals over every run.",
                      :refuses => PAGE, :params => LIST_PARAMS, :result => LIST_RESULT_ANY,
                      :examples => [{}, { "limit" => 20 }, { "compact" => true }]) { |request| Scan.page(request) }
        install_pages(feature)
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
