# frozen_string_literal: true

module PhComposer
  module Piping
    # What Piping groups register: the group reference target, create, link and unlink, two reads, and the
    # retargeter a Hot Water System delete runs. Each write is one native Undo step.
    module GroupRegistration
      PREFIX = "#{FEATURE_ID}.groups".freeze
      # The shared layer runs every group operation with this feature's spec (LINE_GROUP).
      Operations = LineGroups::GroupOperations
      LOCATE = %w[record.unreadable target.ambiguous target.changed target.locked target.not_found
                  target.shared_definition target.wrong_hierarchy target.wrong_kind validation.failed].freeze
      CREATE = %w[record.unreadable session.inactive target.not_found validation.failed].freeze
      LINK = (LOCATE + %w[gesture.too_large piping.group_in_zone piping.group_nested]).freeze
      READ = %w[record.unreadable validation.failed].freeze
      PAGE = (READ + %w[query.cursor_expired query.limit_invalid]).freeze

      REFERENCE = Group::Target::REFERENCE
      SYSTEM_ID = Shapes.id("hws", "The Hot Water System the group's pipes serve.")
      TARGETS = Shapes.list(Shapes.object({ "reference" => REFERENCE,
                                            "expected_values" => Shapes.described(
                                              Shapes::OBJECT, "The group's values as last read; a changed one " \
                                                              "refuses as target.changed. {} skips the check."
                                            ) }, :optional => ["expected_values"]))
                      .merge("minItems" => 1, "maxItems" => Operations::TARGET_LIMIT,
                             "description" => "Explicit Piping group occurrences, as groups.all returns them.")
      EXAMPLE = { "group_id" => "ppg_Ab12Cd34Ef56", "group_path" => [1301] }.freeze
      REFUSAL = Shapes.object({ "code" => Shapes::TEXT, "message" => Shapes::TEXT }).merge("type" => %w[object null])
      ROW = Shapes.object({
        "path" => Group::Target::PATH,
        "reference" => REFERENCE.merge("type" => %w[object null],
                                       "description" => "The group's reference, or null when its record holds no " \
                                                        "valid id."),
        "name" => Shapes::TEXT,
        "values" => Shapes.described(Shapes::OBJECT, "The record's values as stored: hot_water_system_id, null " \
                                                     "while unlinked."),
        "pipe_count" => { "type" => "integer", "minimum" => 0,
                          "description" => "Edges directly inside it carrying a pipe assignment." },
        "copied" => Shapes.described({ "type" => "boolean" }, "Another occurrence carries the same id: a pasted " \
                                                              "copy sharing its storage."),
        "findings" => Shapes.described(Shapes.list(Shapes::TEXT), "piping.group_in_zone or piping.group_nested " \
                                                                  "where it sits somewhere pipes may not."),
        "record_problem" => { "type" => %w[string null], "description" => "Why its record is invalid, or null." },
        "write_refusal" => REFUSAL.merge("description" => "What a write through its path meets, or null.")
      })
      ALL = Shapes.object({ "groups" => Shapes.list(ROW) })
      LIST = Shapes.object({ "groups" => Shapes.list(ROW), "next_cursor" => Pages::NEXT_CURSOR,
                             "total" => Pages::TOTAL })
      PRECONDITIONS = ["Each group sits at the Model root or in plain Groups, outside every Zone and Piping group.",
                       "Each target carries the reference and values groups.all last read."].freeze

      module_function

      def install(feature)
        feature.reference_target(Group::TARGET)
        install_writes(feature)
        feature.query("#{PREFIX}.list",
                      :description => "One bounded page of the Piping group occurrences in path order, each with " \
                                      "its Hot Water System, pipe count, copies and placement findings.",
                      :refuses => PAGE, :params => Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                                                 :optional => %w[limit cursor]),
                      :result => LIST, :examples => [{}, { "limit" => 20 }]) do |request|
          rows = Operations.rows(LINE_GROUP, request)
          page, cursor = Pages.bounded(request, "#{PREFIX}.list", rows, :key => ->(row) { row.fetch("path") })
          { "groups" => page, "next_cursor" => cursor, "total" => rows.length }
        end
        feature.query("#{PREFIX}.all", :description => "Every Piping group occurrence in one read.",
                                       :response => { "bounded" => false, "prefer" => "#{PREFIX}.list" },
                                       :refuses => READ, :params => Shapes::NONE, :result => ALL,
                                       :examples => [{}]) do |request|
          { "groups" => Operations.rows(LINE_GROUP, request) }
        end
        system = Mechanical::HOT_WATER_SYSTEM_KIND
        feature.reference_retargeter("#{PREFIX}.retarget_hot_water_system",
                                     :target_kind => system) do |request, proposal, from:, to:|
          Operations.retarget(LINE_GROUP, request, proposal, :from => from, :to => to)
        end
      end

      def install_writes(feature)
        feature.action("#{PREFIX}.create",
                       :description => "Add one empty Piping group at the Model root linked to a Hot Water System " \
                                       "and open it, so lines drawn next land inside it.",
                       :refuses => CREATE,
                       :params => Shapes.object({ "hot_water_system_id" => SYSTEM_ID }),
                       :result => Shapes.object({ "group_id" => Shapes::TEXT }),
                       :undo_name => "New Piping Group",
                       :preconditions => ["The Hot Water System exists.", "SketchUp shows this Model."],
                       :side_effects => "Adds a Group at the root with a Piping group record and moves the edit " \
                                        "path into it, closing any Group open before.",
                       :examples => [{ "hot_water_system_id" => "hws_Ab12Cd34Ef56" }]) do |request, proposal|
          Operations.create(LINE_GROUP, request, proposal, request.params.fetch("hot_water_system_id"))
        end
        result = Shapes.object({ "group_ids" => Shapes.described(Shapes.list(Shapes::TEXT),
                                                                 "Groups rewritten; empty when none changed.") })
        feature.action("#{PREFIX}.link",
                       :description => "Link explicit Piping groups to one Hot Water System, replacing any link.",
                       :refuses => LINK,
                       :params => Shapes.object({ "targets" => TARGETS, "hot_water_system_id" => SYSTEM_ID }),
                       :result => result, :undo_name => "Link Piping Group", :preconditions => PRECONDITIONS,
                       :side_effects => "Rewrites each group's hot_water_system_id.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE }],
                                       "hot_water_system_id" => "hws_Ab12Cd34Ef56" }]) do |request, proposal|
          Operations.link(LINE_GROUP, request, proposal, request.params.fetch("targets"),
                          request.params.fetch("hot_water_system_id"))
        end
        feature.action("#{PREFIX}.unlink",
                       :description => "Unlink explicit Piping groups from their Hot Water System, which blocks " \
                                       "their pipes' export until linked again.",
                       :refuses => LINK, :params => Shapes.object({ "targets" => TARGETS }),
                       :result => result, :undo_name => "Unlink Piping Group", :preconditions => PRECONDITIONS,
                       :side_effects => "Sets each group's hot_water_system_id to null.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE }] }]) do |request, proposal|
          Operations.link(LINE_GROUP, request, proposal, request.params.fetch("targets"), nil)
        end
      end
    end
  end
end
