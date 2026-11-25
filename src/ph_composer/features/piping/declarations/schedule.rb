# frozen_string_literal: true

module PhComposer
  module Piping
    # What the schedule registers: the bounded read, a run's pipes a page at a time, runs.locate, and each Hot Water
    # System's piping lengths and recirculation for the panel snapshot. Each read walks the Model, so it shows the
    # pipes as they are. The schedule is asked for on opening and on Refresh (context/TECH_STACK.md, "Edge-owned
    # assignments"); the Systems read, the walk and the tree without findings, measured under the refresh budget, is a
    # snapshot section.
    module ScheduleRegistration
      LOCATE = "#{FEATURE_ID}.runs.locate".freeze
      SYSTEMS = "#{FEATURE_ID}.systems".freeze
      SYSTEMS_SECTION = "#{FEATURE_ID}.piping_systems".freeze
      PATH = Group::Target::PATH
      # An unreadable Pipe Type or Hot Water System refuses the read, as it refuses its own.
      READ = %w[record.unreadable validation.failed].freeze
      PAGE = (READ + %w[query.cursor_expired query.limit_invalid]).freeze
      MEMBERS_REFUSES = (PAGE + %w[target.ambiguous target.not_found]).freeze
      LOCATE_REFUSES = %w[session.inactive target.ambiguous target.not_found target.locked target.wrong_kind
                          target.shared_definition piping.hidden].freeze

      NUMBER = { "type" => "number" }.freeze
      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      NULLABLE_TEXT = { "type" => %w[string null] }.freeze
      # One locate takes a whole run, however long, since a second call would replace the first selection. The bound
      # only stops a runaway request.
      LOCATE_EDGE_LIMIT = 10_000
      EDGE_PATHS = Shapes.list(PATH).merge("description" => "Root-to-Edge persistent-id paths.")
      FINDING = Shapes.object({
        "code" => Shapes::TEXT,
        "message" => Shapes.described(Shapes::TEXT, "Cut to #{SchedulePages::MAX_MESSAGE} characters."),
        "blocks_export" => { "type" => "boolean" },
        "locate" => Shapes.object({ "edge_paths" => EDGE_PATHS })
                          .merge("description" => "The pipes named, as runs.locate takes them; without compact."),
        "edge_count" => COUNT.merge("description" => "With compact: how many pipes it names; " \
                                                     "#{SchedulePages::MEMBERS} with finding pages them.")
      }, :optional => %w[locate edge_count])
      RUN = Shapes.object({
        "identifier" => Shapes.described(Shapes::TEXT, "pipe_ and a digest of the group occurrence, role, Pipe Type, " \
                                                       "role values and points; derived, and it changes with the " \
                                                       "geometry."),
        "display_name" => Shapes.described(Shapes::TEXT, "The role and a counter, numbered per Hot Water System."),
        "role" => { "type" => "string", "enum" => Assignment::ROLES },
        "hot_water_system_id" => Shapes.described(NULLABLE_TEXT, "The group's Hot Water System, or null."),
        "hot_water_system_name" => Shapes.described(NULLABLE_TEXT, "Null when the group names no existing System."),
        "group" => Shapes.object({ "group_id" => Shapes::TEXT, "group_path" => PATH, "name" => Shapes::TEXT }),
        "parent" => Shapes.described(NULLABLE_TEXT, "The identifier of the trunk a branch hangs from, or the branch " \
                                                    "a twig hangs from; null for a trunk, a recirculation run and an " \
                                                    "unconnected run."),
        "parent_name" => NULLABLE_TEXT,
        "pipe_type_id" => NULLABLE_TEXT,
        "pipe_type_name" => Shapes.described(NULLABLE_TEXT, "Null when the Pipe Type no longer exists or is unset."),
        "length_m" => Shapes.described(NUMBER, "Drawn length; a trunk's multiplier is not applied."),
        "line_count" => COUNT,
        "values" => Shapes.described(Shapes::OBJECT, "The role's values: a trunk's multiplier and " \
                                                     "demand_recirculation, a recirculation run's water_temp_c and " \
                                                     "daily_period, none for a branch or twig."),
        "closed" => { "type" => "boolean" },
        "edge_paths" => EDGE_PATHS.merge("description" => "The run's pipes in order; runs.locate takes them. Left " \
                                                          "out with compact."),
        "edge_count" => COUNT.merge("description" => "With compact: how many pipes."),
        "index" => COUNT.merge("description" => "With compact: the run's place in the schedule, which names it to " \
                                                "#{SchedulePages::MEMBERS} when two runs share an identifier."),
        "truncated" => ContextChildren::TRUNCATED,
        "shared" => Shapes.described({ "type" => "boolean" }, "Whether any pipe is in storage another placement " \
                                                              "draws."),
        "findings" => Shapes.list(FINDING)
      }, :optional => %w[edge_paths edge_count index truncated])
      ROLE_TOTAL = Shapes.object({ "role" => Shapes::TEXT, "run_count" => COUNT, "line_count" => COUNT,
                                   "length_m" => NUMBER })
      TOTALS = Shapes.object({
        "by_role" => Shapes.list(ROLE_TOTAL).merge("description" => "Every role, zero with no run."),
        "run_count" => COUNT, "line_count" => COUNT, "distribution_length_m" => NUMBER,
        "recirculation_length_m" => NUMBER
      })
      SYSTEM = Shapes.object({
        "hot_water_system_id" => Shapes::TEXT, "name" => Shapes::TEXT,
        "distribution_length_m" => Shapes.described(
          Shapes.object(Runs::Schedule::DISTRIBUTION.to_h { |role| [role, NUMBER] }),
          "Drawn length by distribution role in the groups linked to it."
        ),
        "recirculation_length_m" => NUMBER,
        "recirculation_temperature_c" => Shapes.described(NUMBER, "Length-weighted, as honeybee-ph's recirc_temp; " \
                                                                  "60 with no recirculation pipe."),
        "recirculation_hours" => Shapes.described(COUNT, "Length-weighted and truncated, as honeybee-ph's " \
                                                         "recirc_hours; 24 with no recirculation pipe."),
        "from_piping" => Shapes.described({ "type" => "boolean" }, "Whether a recirculation pipe sets the two " \
                                                                   "values above."),
        "truncated" => ContextChildren::TRUNCATED
      }, :optional => ["truncated"])
      TYPE = Shapes.object({ "pipe_type_id" => Shapes::TEXT, "name" => Shapes::TEXT, "used_length_m" => NUMBER,
                             "line_count" => COUNT, "truncated" => ContextChildren::TRUNCATED },
                           :optional => ["truncated"])
      UNREADABLE = Shapes.object({ "path" => PATH, "code" => Shapes::TEXT, "message" => Shapes::TEXT })
      RESULT = Shapes.object({
        "runs" => Shapes.list(RUN).merge("description" => "One page of runs in schedule order: by Hot Water " \
                                                          "System, group path, role and smallest point."),
        "totals" => TOTALS.merge("description" => "Over every run."),
        "systems" => Shapes.list(SYSTEM).merge("description" => "Every Hot Water System, one with no pipes " \
                                                                "included."),
        "types" => Shapes.list(TYPE).merge("description" => "Every Pipe Type with its used length."),
        "unreadable" => Shapes.list(UNREADABLE).merge("description" => "The first #{SchedulePages::DETAIL_ROWS} " \
                                                                       "group and pipe records that cannot be read; " \
                                                                       "not counted, and each blocks export."),
        "unreadable_total" => COUNT,
        "system_count" => COUNT.merge("description" => "With compact: how many Systems; " \
                                                       "#{SchedulePages::DETAILS} pages them."),
        "type_count" => COUNT.merge("description" => "With compact: how many Pipe Types; " \
                                                     "#{SchedulePages::DETAILS} pages them."),
        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
      }, :optional => %w[systems types unreadable system_count type_count])
      ALL = "#{FEATURE_ID}.schedule.all".freeze
      WHOLE = %w[totals systems types unreadable unreadable_total].freeze
      ALL_RESULT = Shapes.object(RESULT.fetch("properties").slice(*WHOLE)
                                       .merge("runs" => Shapes.list(RUN).merge("description" => "Every run in " \
                                                                                                "schedule order.")))
      DETAILS_PARAMS = Shapes.object({
        "part" => { "type" => "string", "enum" => SchedulePages::PARTS.keys,
                    "description" => "systems, types or unreadable: which of the schedule's lists to page." },
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[limit cursor])
      DETAILS_RESULT = Shapes.object({
        "systems" => Shapes.list(SYSTEM).merge("description" => "With part systems: System rows by id."),
        "types" => Shapes.list(TYPE).merge("description" => "With part types: Pipe Type rows by id."),
        "unreadable" => Shapes.list(UNREADABLE).merge("description" => "With part unreadable: records by path."),
        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
      }, :optional => %w[systems types unreadable])
      LOCATE_PARAMS = Shapes.object({ "edge_paths" => EDGE_PATHS.merge(
        "minItems" => 1, "maxItems" => LOCATE_EDGE_LIMIT,
        "description" => "The pipes of one run, or of one finding, as the schedule reads them."
      ) })
      LOCATE_RESULT = Shapes.object({ "path" => PATH.merge("description" => "The edit path afterwards."),
                                      "selected" => COUNT })
      PAGE_PARAMS = Shapes.object({
        "compact" => { "type" => "boolean",
                       "description" => "Leave out each run's edge_paths and each finding's pipes, counted instead, " \
                                        "and the System, Pipe Type and unreadable rows, which " \
                                        "#{SchedulePages::DETAILS} pages; #{SchedulePages::MEMBERS} pages a run's " \
                                        "pipes. Every page then fits one agent reply. False when absent." },
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[compact limit cursor])
      MEMBERS_PARAMS = Shapes.object({
        "identifier" => Shapes.described(Shapes::TEXT, "The run's identifier from the schedule."),
        "index" => COUNT.merge("description" => "The run's index from a compact schedule row; needed only when two " \
                                                "runs share the identifier."),
        "finding" => COUNT.merge("description" => "Only the pipes of the run's finding at this index."),
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[index finding limit cursor])
      MEMBERS_RESULT = Shapes.object({
        "identifier" => Shapes::TEXT,
        "members" => Shapes.list(Shapes.object({ "index" => COUNT.merge("description" => "Its place in the run."),
                                                 "path" => PATH })),
        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
      })

      module_function

      # The parts a compact schedule page leaves out, a bounded page at a time.
      def install_pages(feature)
        feature.query(SchedulePages::DETAILS,
                      :description => "One bounded page of the schedule's System rows, Pipe Type rows or unreadable " \
                                      "records, each name cut, for a compact read.",
                      :refuses => PAGE, :params => DETAILS_PARAMS, :result => DETAILS_RESULT,
                      :examples => [{ "part" => "systems" }, { "part" => "unreadable", "limit" => 20 }]) do |request|
          SchedulePages.details(request)
        end
        feature.query(SchedulePages::MEMBERS,
                      :description => "One bounded page of one run's pipes in run order, each with its path, or only " \
                                      "those one of its findings names.",
                      :refuses => MEMBERS_REFUSES, :params => MEMBERS_PARAMS, :result => MEMBERS_RESULT,
                      :examples => [{ "identifier" => "pipe_0a1b2c3d4e5f6a7b" },
                                    { "identifier" => "pipe_0a1b2c3d4e5f6a7b", "finding" => 0 }]) do |request|
          SchedulePages.members(request)
        end
      end

      def install(feature)
        feature.query(SchedulePages::PAGE,
                      :description => "One bounded page of hot water piping runs, each with its Hot Water System, " \
                                      "group, role, parent, Pipe Type, drawn length, line count, role values and " \
                                      "findings, with totals by role, each System's distribution and recirculation " \
                                      "and each Pipe Type's used length. It walks the Model.",
                      :refuses => PAGE,
                      :params => PAGE_PARAMS, :result => RESULT,
                      :examples => [{}, { "limit" => 20 }, { "compact" => true }]) do |request|
          SchedulePages.page(request)
        end
        install_pages(feature)
        feature.query(ALL, :description => "Every hot water piping run in one read, for the panel, with the totals, " \
                                           "System and Pipe Type rows and unreadable records. It walks the Model.",
                           :response => { "bounded" => false, "prefer" => SchedulePages::PAGE },
                           :refuses => READ, :params => Shapes::NONE, :result => ALL_RESULT,
                           :examples => [{}]) { |request| Scan.schedule(request) }
        feature.query(SYSTEMS,
                      :description => "Every Hot Water System's drawn distribution length by role and its " \
                                      "recirculation length, temperature and hours from its recirculation pipes, as " \
                                      "honeybee-ph works them out; 60 and 24 with none. It walks the Model.",
                      :refuses => READ, :params => Shapes::NONE,
                      :result => Shapes.object({ "systems" => RESULT.dig("properties", "systems") }),
                      :examples => [{}]) { |request| Scan.systems(request) }
        feature.snapshot_section(SYSTEMS_SECTION, :query => SYSTEMS)
        feature.view_command(LOCATE,
                             :description => "Select the pipes of one run and bring them into view, opening the " \
                                             "Piping group that holds them.",
                             :refuses => LOCATE_REFUSES, :params => LOCATE_PARAMS, :result => LOCATE_RESULT,
                             :preconditions => ["Every pipe sits in one Piping group and none is hidden."],
                             :side_effects => "Selects and frames the pipes. #{ContextCommands::SIDE_EFFECTS}",
                             :examples => [{ "edge_paths" => [[1301, 1305], [1301, 1306]] }]) do |request|
          RunLocate.call(request, :edge_paths => request.params.fetch("edge_paths"))
        end
      end
    end
  end
end
