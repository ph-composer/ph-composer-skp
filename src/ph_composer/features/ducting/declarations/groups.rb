# frozen_string_literal: true

module PhComposer
  module Ducting
    # What Ducting groups register: the group reference target, make, link and unlink, two reads, and the retargeter
    # a Ventilator delete runs. Each write is one native Undo step.
    module GroupRegistration
      PREFIX = "#{FEATURE_ID}.groups".freeze
      # The shared layer runs every group operation with this feature's spec (LINE_GROUP).
      Operations = LineGroups::GroupOperations
      Shapes = Mechanical::Shapes
      OBJECT = { "type" => "object" }.freeze
      LOCATE = %w[record.unreadable target.ambiguous target.changed target.locked target.not_found
                  target.shared_definition target.wrong_hierarchy target.wrong_kind validation.failed].freeze
      LINK = (LOCATE + %W[gesture.too_large #{Codes::GROUP_IN_ZONE} #{Codes::GROUP_NESTED}]).freeze
      MAKE = (LINK + %w[target.edit_path_changed]).sort.freeze
      READ = %w[record.unreadable validation.failed].freeze
      PAGE = (READ + %w[query.cursor_expired query.limit_invalid]).freeze

      REFERENCE = Group::REFERENCE
      VENTILATOR_ID = Shapes.id("vnt", "The Ventilator whose ducts the group holds.")
      TARGETS = Shapes.list(Shapes.object({ "reference" => REFERENCE,
                                            "expected_values" => Shapes.described(
                                              OBJECT, "The group's values as last read; a changed one refuses as " \
                                                      "target.changed. {} skips the check."
                                            ) }, :optional => ["expected_values"]))
                      .merge("minItems" => 1, "maxItems" => Operations::TARGET_LIMIT,
                             "description" => "Explicit Ducting group occurrences, as groups.all returns them.")
      EXAMPLE = { "group_id" => "dcg_Ab12Cd34Ef56", "group_path" => [1301] }.freeze
      REFUSAL = Shapes.object({ "code" => Shapes::TEXT, "message" => Shapes::TEXT }).merge("type" => %w[object null])
      ROW = Shapes.object({
        "path" => LineGroups::PATH,
        "reference" => REFERENCE.merge("type" => %w[object null],
                                       "description" => "The group's reference, or null when its record holds no " \
                                                        "valid id."),
        "name" => Shapes::TEXT,
        "values" => Shapes.described(OBJECT, "The record's values as stored: ventilator_id, null while unlinked."),
        "duct_count" => { "type" => "integer", "minimum" => 0,
                          "description" => "Edges directly inside it carrying a duct assignment." },
        "copied" => Shapes.described({ "type" => "boolean" }, "Another occurrence carries the same id, as a pasted " \
                                                              "copy does, keeping its Ventilator. It says nothing " \
                                                              "of writability: read write_refusal."),
        "findings" => Shapes.described(Shapes.list(Shapes::TEXT), "#{Codes::GROUP_IN_ZONE} or " \
                                                                  "#{Codes::GROUP_NESTED} where it sits somewhere " \
                                                                  "ducts may not."),
        "record_problem" => { "type" => %w[string null], "description" => "Why its record is invalid, or null." },
        "write_refusal" => REFUSAL.merge("description" => "What a write through its path meets, or null.")
      })
      EDGE_PATHS = Shapes.list(LineGroups::PATH)
                         .merge("minItems" => 1,
                                "description" => "Root-to-Edge paths of loose lines in one collection, as " \
                                                 "ducts.selection gives them; at most " \
                                                 "#{Assignment::GESTURE_EDGE_LIMIT}, more refusing " \
                                                 "gesture.too_large.")
      MAKE_PRECONDITIONS = ["The Ventilator exists.",
                            "The lines are loose Edges, bounding no Face but those they alone close, directly in the " \
                            "open context, outside every " \
                            "Zone and every Group another feature owns, reached through plain unlocked unshared " \
                            "Groups.",
                            "ducts.selection reads make_refusal null over them."].freeze
      PRECONDITIONS = ["Each group sits at the Model root or in plain Groups, outside every Zone and Ducting group.",
                       "Each target carries the reference and values groups.all last read."].freeze

      module_function

      def install(feature)
        feature.reference_target(Group::TARGET)
        install_writes(feature)
        install_reads(feature)
        feature.reference_retargeter("#{PREFIX}.retarget_ventilator",
                                     :target_kind => Mechanical::VENTILATOR_KIND) do |request, proposal, from:, to:|
          Operations.retarget(LINE_GROUP, request, proposal, :from => from, :to => to)
        end
      end

      def install_reads(feature)
        feature.query("#{PREFIX}.list",
                      :description => "One bounded page of the Ducting group occurrences in path order, each with " \
                                      "its Ventilator, duct count, copies and placement findings.",
                      :refuses => PAGE, :params => Shapes.object({ "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                                                 :optional => %w[limit cursor]),
                      :result => Shapes.object({ "groups" => Shapes.list(ROW), "next_cursor" => Pages::NEXT_CURSOR,
                                                 "total" => Pages::TOTAL }),
                      :examples => [{}, { "limit" => 20 }]) do |request|
          rows = Operations.rows(LINE_GROUP, request)
          page, cursor = Pages.bounded(request, "#{PREFIX}.list", rows, :key => ->(row) { row.fetch("path") })
          { "groups" => page, "next_cursor" => cursor, "total" => rows.length }
        end
        feature.query("#{PREFIX}.all", :description => "Every Ducting group occurrence in one read.",
                                       :response => { "bounded" => false, "prefer" => "#{PREFIX}.list" },
                                       :refuses => READ, :params => Shapes::NONE,
                                       :result => Shapes.object({ "groups" => Shapes.list(ROW) }),
                                       :examples => [{}]) do |request|
          { "groups" => Operations.rows(LINE_GROUP, request) }
        end
      end

      def install_writes(feature)
        feature.action("#{PREFIX}.make",
                       :description => "Wrap loose lines drawn in the open context in a new Ducting group linked to " \
                                       "a Ventilator, where they are; the lines keep their ids and the edit path " \
                                       "stays.",
                       :refuses => MAKE,
                       :params => Shapes.object({ "edge_paths" => EDGE_PATHS, "ventilator_id" => VENTILATOR_ID }),
                       :result => LineGroups::ScheduleShapes::MAKE_RESULT,
                       :undo_name => "Make Ducting Group", :preconditions => MAKE_PRECONDITIONS,
                       :side_effects => "Adds a Group named \"Ducting group N\" with a Ducting group record in the " \
                                        "lines' collection and moves the lines into it; their persistent ids and " \
                                        "dictionaries stay. Erases any Face the lines alone close; a Face with an " \
                                        "unselected Edge refuses as target.wrong_kind.",
                       :examples => [{ "edge_paths" => [[1305], [1306]],
                                       "ventilator_id" => "vnt_Ab12Cd34Ef56" }]) do |request, proposal|
          Operations.make(LINE_GROUP, request, proposal, request.params.fetch("edge_paths"),
                          request.params.fetch("ventilator_id"), :limit => Assignment.gesture_edge_limit)
        end
        result = Shapes.object({ "group_ids" => Shapes.described(Shapes.list(Shapes::TEXT),
                                                                 "Groups rewritten; empty when none changed.") })
        feature.action("#{PREFIX}.link",
                       :description => "Link explicit Ducting groups to one Ventilator, replacing any link.",
                       :refuses => LINK,
                       :params => Shapes.object({ "targets" => TARGETS, "ventilator_id" => VENTILATOR_ID }),
                       :result => result, :undo_name => "Link Ducting Group", :preconditions => PRECONDITIONS,
                       :side_effects => "Rewrites each group's ventilator_id.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE }],
                                       "ventilator_id" => "vnt_Ab12Cd34Ef56" }]) do |request, proposal|
          Operations.link(LINE_GROUP, request, proposal, request.params.fetch("targets"),
                          request.params.fetch("ventilator_id"))
        end
        feature.action("#{PREFIX}.unlink",
                       :description => "Unlink explicit Ducting groups from their Ventilator, which blocks their " \
                                       "ducts' export until linked again.",
                       :refuses => LINK, :params => Shapes.object({ "targets" => TARGETS }),
                       :result => result, :undo_name => "Unlink Ducting Group", :preconditions => PRECONDITIONS,
                       :side_effects => "Sets each group's ventilator_id to null.",
                       :examples => [{ "targets" => [{ "reference" => EXAMPLE }] }]) do |request, proposal|
          Operations.link(LINE_GROUP, request, proposal, request.params.fetch("targets"), nil)
        end
      end
    end
  end
end
