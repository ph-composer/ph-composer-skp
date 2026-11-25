# frozen_string_literal: true

require_relative "spec"

module PhComposer
  module LineGroups
    # What every line group's schedule declares alike, worded by the spec's Edge noun: a finding, the parts of a run
    # row that name its Edges, an unreadable record, a run's members a page at a time and runs.locate. The feature
    # declares the rest of its schedule, whose rows and lists are its own.
    module ScheduleShapes
      extend SchemaShapes

      TEXT = { "type" => "string" }.freeze
      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      EDGE_PATHS = list(PATH).merge("description" => "Root-to-Edge persistent-id paths.").freeze
      UNREADABLE = object({ "path" => PATH, "code" => TEXT, "message" => TEXT }).freeze
      MEMBERS_RESULT = object({
        "identifier" => TEXT,
        "members" => list(object({ "index" => COUNT.merge("description" => "Its place in the run."), "path" => PATH })),
        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
      }).freeze
      LOCATE_RESULT = object({ "path" => PATH.merge("description" => "The edit path afterwards."),
                               "selected" => COUNT }).freeze
      # One locate takes a whole run, however long, since a second call would replace the first selection. The bound
      # only stops a runaway request.
      LOCATE_EDGE_LIMIT = 10_000

      module_function

      def nouns(spec)
        "#{spec.edge_noun}s"
      end

      # A run's finding; `members` is the feature's members query.
      def finding(spec, members)
        object({
          "code" => TEXT,
          "message" => described(TEXT, "Cut to #{RecordQueries::MAX_MESSAGE} characters."),
          "blocks_export" => { "type" => "boolean" },
          "locate" => described(object({ "edge_paths" => EDGE_PATHS }),
                                "The #{nouns(spec)} named, as runs.locate takes them; without compact."),
          "edge_count" => COUNT.merge("description" => "With compact: how many #{nouns(spec)} it names; " \
                                                       "#{members} with finding pages them.")
        }, :optional => %w[locate edge_count])
      end

      # The properties of a run row that name its Edges and findings, the first three left out or added by compact.
      def run_edges(spec, members)
        { "edge_paths" => EDGE_PATHS.merge("description" => "The run's #{nouns(spec)} in order; runs.locate takes " \
                                                            "them. Left out with compact."),
          "edge_count" => COUNT.merge("description" => "With compact: how many #{nouns(spec)}."),
          "index" => COUNT.merge("description" => "With compact: the run's place in the schedule, which names it to " \
                                                  "#{members} when two runs share an identifier."),
          "truncated" => ContextChildren::TRUNCATED,
          "shared" => described({ "type" => "boolean" }, "Whether any #{spec.edge_noun} is in storage another " \
                                                         "placement draws."),
          "findings" => list(finding(spec, members)) }
      end

      # `pages` is the feature's LineGroups::SchedulePages, `members` its members query, `refuses` its codes and
      # `example` a run identifier.
      def install_members(feature, spec, pages, members:, refuses:, example:)
        params = object({
          "identifier" => described(TEXT, "The run's identifier from the schedule."),
          "index" => COUNT.merge("description" => "The run's index from a compact schedule row; needed only when " \
                                                  "two runs share the identifier."),
          "finding" => COUNT.merge("description" => "Only the #{nouns(spec)} of the run's finding at this index."),
          "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
        }, :optional => %w[index finding limit cursor])
        feature.query(members,
                      :description => "One bounded page of one run's #{nouns(spec)} in run order, each with its " \
                                      "path, or only those one of its findings names.",
                      :refuses => refuses, :params => params, :result => MEMBERS_RESULT,
                      :examples => [{ "identifier" => example },
                                    { "identifier" => example, "finding" => 0 }]) do |request|
          pages.members(request)
        end
      end

      # The view command `name` over Locate, refusing the spec's hidden code with the path refusals.
      def install_locate(feature, spec, name)
        params = object({ "edge_paths" => EDGE_PATHS.merge(
          "minItems" => 1, "maxItems" => LOCATE_EDGE_LIMIT,
          "description" => "The #{nouns(spec)} of one run, or of one finding, as the schedule reads them."
        ) })
        refuses = %w[session.inactive target.ambiguous target.not_found target.locked target.wrong_kind
                     target.shared_definition] + [spec.code(:hidden)]
        feature.view_command(name,
                             :description => "Select the #{nouns(spec)} of one run and bring them into view, " \
                                             "opening the #{spec.label} that holds them.",
                             :refuses => refuses, :params => params, :result => LOCATE_RESULT,
                             :preconditions => ["Every #{spec.edge_noun} sits in one #{spec.label} and none is " \
                                                "hidden."],
                             :side_effects => "Selects and frames the #{nouns(spec)}. " \
                                              "#{ContextCommands::SIDE_EFFECTS}",
                             :examples => [{ "edge_paths" => [[1301, 1305], [1301, 1306]] }]) do |request|
          Locate.call(spec, request, :edge_paths => request.params.fetch("edge_paths"))
        end
      end
    end
  end
end
