# frozen_string_literal: true

module PhComposer
  module Ducting
    # What the schedule registers: the bounded read, its detail lists and a run's ducts a page at a time, runs.locate,
    # and each Ventilator's two duct lengths for the panel snapshot. Each read walks the Model, so it shows the ducts as
    # they are. The schedule is asked for on opening and on Refresh (context/TECH_STACK.md, "Edge-owned
    # assignments"); the Ventilators read, the walk and the runs without findings or Zones, measured under the refresh
    # budget, is a snapshot section.
    module ScheduleRegistration
      LOCATE = "#{FEATURE_ID}.runs.locate".freeze
      VENTILATORS = "#{FEATURE_ID}.ventilators".freeze
      VENTILATORS_SECTION = "#{FEATURE_ID}.ducting_ventilators".freeze
      Shapes = Mechanical::Shapes
      PATH = LineGroups::PATH
      # An unreadable Duct Type or Ventilator refuses the read, as it refuses its own; the schedule also reads which
      # Ventilators serve a Zone through Mechanical's Ventilators read.
      READ = %w[record.unreadable validation.failed].freeze
      SCHEDULE = (READ + Mechanical::Serves::State::REFUSES).uniq.sort.freeze
      PAGE = (SCHEDULE + %w[query.cursor_expired query.limit_invalid]).freeze
      MEMBERS_REFUSES = (PAGE + %w[target.ambiguous target.not_found]).freeze
      Common = LineGroups::ScheduleShapes

      LENGTH = { "type" => "number", "minimum" => 0, "x-unit" => "m" }.freeze
      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      NULLABLE_TEXT = { "type" => %w[string null] }.freeze
      DIRECTION = { "type" => "string", "enum" => Assignment::DIRECTIONS }.freeze
      RUN = Shapes.object({
        "identifier" => Shapes.described(Shapes::TEXT, "duct_ and a digest of the group occurrence, direction, Duct " \
                                                       "Type, quantity and points; derived, and it changes with the " \
                                                       "geometry."),
        "display_name" => Shapes.described(Shapes::TEXT, "The direction and a counter, numbered per Ventilator."),
        "direction" => DIRECTION,
        "ventilator_id" => Shapes.described(NULLABLE_TEXT, "The group's Ventilator, or null."),
        "ventilator_name" => Shapes.described(NULLABLE_TEXT, "Null when the group names no existing Ventilator."),
        "group" => Shapes.object({ "group_id" => Shapes::TEXT, "group_path" => PATH, "name" => Shapes::TEXT }),
        "duct_type_id" => NULLABLE_TEXT,
        "duct_type_name" => Shapes.described(NULLABLE_TEXT, "Null when the Duct Type no longer exists or is unset."),
        "length_m" => Shapes.described(LENGTH, "Drawn length; the quantity is not applied."),
        "quantity" => COUNT.merge("minimum" => 1, "description" => "How many identical ducts each line stands for."),
        "line_count" => COUNT
      }.merge(Common.run_edges(LINE_GROUP, SchedulePages::MEMBERS)),
                          :optional => %w[edge_paths edge_count index truncated])
      SUMS = { "run_count" => COUNT, "line_count" => COUNT,
               "length_m" => Shapes.described(LENGTH, "Each line times its quantity.") }.freeze
      TOTALS = Shapes.object({
        "by_direction" => Shapes.list(Shapes.object({ "direction" => DIRECTION }.merge(SUMS)))
                                .merge("description" => "Both directions, zero with no run.")
      }.merge(SUMS))
      LENGTHS = Assignment::DIRECTIONS.to_h do |direction|
        ["#{direction}_length_m", Shapes.described(LENGTH, "Its #{Runs::DIRECTION_WORDS.fetch(direction)} ducts, " \
                                                           "each line times its quantity; 0 with none.")]
      end.freeze
      VENTILATOR = Shapes.object({ "ventilator_id" => Shapes::TEXT, "name" => Shapes::TEXT }.merge(LENGTHS)
                                   .merge("truncated" => ContextChildren::TRUNCATED), :optional => ["truncated"])
      VENTILATOR_FINDING = Shapes.object({
        "code" => Shapes::TEXT, "message" => Shapes::TEXT, "blocks_export" => { "type" => "boolean" },
        "locate" => Shapes.described({ "type" => "object" }, "The view command and params opening the Ventilator: " \
                                                             "ph_composer.mechanical.locate.")
      })
      SCHEDULE_VENTILATOR = Shapes.with(VENTILATOR, "findings" => Shapes.list(VENTILATOR_FINDING).merge(
        "description" => "ducting.run_missing when it serves a Zone and has no run of a direction."
      ))
      TYPE = Shapes.object({ "duct_type_id" => Shapes::TEXT, "name" => Shapes::TEXT,
                             "used_length_m" => Shapes.described(LENGTH, "Each line times its quantity."),
                             "line_count" => COUNT, "truncated" => ContextChildren::TRUNCATED },
                           :optional => ["truncated"])
      UNREADABLE = Common::UNREADABLE
      RESULT = Shapes.object({
        "runs" => Shapes.list(RUN).merge("description" => "One page of runs in schedule order: by Ventilator, group " \
                                                          "path, direction and smallest point."),
        "totals" => TOTALS.merge("description" => "Over every run."),
        "ventilators" => Shapes.list(SCHEDULE_VENTILATOR).merge("description" => "Every Ventilator, one with no " \
                                                                                 "ducts included."),
        "types" => Shapes.list(TYPE).merge("description" => "Every Duct Type with its used length."),
        "unreadable" => Shapes.list(UNREADABLE).merge("description" => "The first " \
                                                                       "#{LineGroups::SchedulePages::DETAIL_ROWS} " \
                                                                       "group and duct records that cannot be read; " \
                                                                       "not counted, and each blocks export."),
        "unreadable_total" => COUNT,
        "ventilator_count" => COUNT.merge("description" => "With compact: how many Ventilators; " \
                                                           "#{SchedulePages::DETAILS} pages them."),
        "type_count" => COUNT.merge("description" => "With compact: how many Duct Types; " \
                                                     "#{SchedulePages::DETAILS} pages them."),
        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
      }, :optional => %w[ventilators types unreadable ventilator_count type_count])
      DETAILS_PARAMS = Shapes.object({
        "part" => { "type" => "string", "enum" => SchedulePages::PARTS.keys,
                    "description" => "ventilators, types or unreadable: which of the schedule's lists to page." },
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[limit cursor])
      DETAILS_RESULT = Shapes.object({
        "ventilators" => Shapes.list(SCHEDULE_VENTILATOR).merge("description" => "With part ventilators: by id."),
        "types" => Shapes.list(TYPE).merge("description" => "With part types: Duct Type rows by id."),
        "unreadable" => Shapes.list(UNREADABLE).merge("description" => "With part unreadable: records by path."),
        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
      }, :optional => %w[ventilators types unreadable])
      PAGE_PARAMS = Shapes.object({
        "compact" => { "type" => "boolean",
                       "description" => "Leave out each run's edge_paths and each finding's ducts, counted instead, " \
                                        "and the Ventilator, Duct Type and unreadable rows, which " \
                                        "#{SchedulePages::DETAILS} pages; #{SchedulePages::MEMBERS} pages a run's " \
                                        "ducts. Every page then fits one agent reply. False when absent." },
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[compact limit cursor])

      module_function

      def install(feature)
        feature.query(SchedulePages::PAGE,
                      :description => "One bounded page of ERV duct runs, each with its Ventilator, group, " \
                                      "direction, Duct Type, drawn length, quantity, line count and findings, with " \
                                      "totals by direction, each Ventilator's two lengths and each Duct Type's used " \
                                      "length, quantity applied. It walks the Model.",
                      :refuses => PAGE, :params => PAGE_PARAMS, :result => RESULT,
                      :examples => [{}, { "limit" => 20 }, { "compact" => true }]) do |request|
          SchedulePages::PAGES.page(request)
        end
        install_pages(feature)
        feature.query(VENTILATORS,
                      :description => "Every Ventilator's Outdoor air and Exhaust air duct lengths, each line times " \
                                      "its quantity, 0 with none. It walks the Model.",
                      :refuses => READ, :params => Shapes::NONE,
                      :result => Shapes.object({ "ventilators" => Shapes.list(VENTILATOR) }),
                      :examples => [{}]) { |request| Scan.ventilators(request) }
        feature.snapshot_section(VENTILATORS_SECTION, :query => VENTILATORS)
        Common.install_locate(feature, LINE_GROUP, LOCATE)
      end

      # The parts a compact schedule page leaves out, a bounded page at a time.
      def install_pages(feature)
        feature.query(SchedulePages::DETAILS,
                      :description => "One bounded page of the schedule's Ventilator rows, Duct Type rows or " \
                                      "unreadable records, each name cut, for a compact read.",
                      :refuses => PAGE, :params => DETAILS_PARAMS, :result => DETAILS_RESULT,
                      :examples => [{ "part" => "ventilators" },
                                    { "part" => "unreadable", "limit" => 20 }]) do |request|
          SchedulePages::PAGES.details(request)
        end
        Common.install_members(feature, LINE_GROUP, SchedulePages::PAGES, :members => SchedulePages::MEMBERS,
                                                                          :refuses => MEMBERS_REFUSES,
                                                                          :example => "duct_0a1b2c3d4e5f6a7b")
      end
    end
  end
end
