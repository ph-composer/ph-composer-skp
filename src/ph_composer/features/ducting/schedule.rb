# frozen_string_literal: true

module PhComposer
  module Ducting
    # The schedule from facts: one row per run with its Ventilator, group, direction, Duct Type, drawn length, quantity,
    # line count and findings; totals by direction; one row per Ventilator with its two lengths; one row per Duct Type
    # with its used length. All arithmetic is here, in SI; a panel formats. A run row shows its drawn length and its
    # quantity apart; every total applies the quantity, as the export writes a run of quantity N as N elements and
    # honeybee-ph's total lengths count each.
    module Schedule
      module_function

      # `facts` are every readable duct occurrence; `types` maps a Duct Type id to its record; `ventilators` maps a
      # Ventilator id to its record; `served` are the ids of the Ventilators that serve a Zone.
      def call(facts, types:, ventilators:, served:)
        runs = Runs.call(facts)
        rows = runs.map { |run| row(run, types, ventilators) }
        missing = Findings.missing_runs(runs, :served => served)
        { "runs" => rows, "totals" => totals(runs),
          "ventilators" => ventilator_rows(runs, ventilators).map do |ventilator|
            ventilator.merge("findings" => missing.fetch(ventilator.fetch("ventilator_id"), []))
          end,
          "types" => type_rows(runs, types) }
      end

      def row(run, types, ventilators)
        { "identifier" => run.identifier, "display_name" => run.display_name, "direction" => run.direction,
          "ventilator_id" => run.ventilator_id, "ventilator_name" => ventilators[run.ventilator_id]&.fetch("name"),
          "group" => run.group.slice("group_id", "group_path", "name"),
          "duct_type_id" => run.duct_type_id, "duct_type_name" => types[run.duct_type_id]&.fetch("name"),
          "length_m" => run.length_m, "quantity" => run.quantity, "line_count" => run.facts.length,
          "edge_paths" => run.edge_paths, "shared" => run.facts.any?(&:shared),
          "findings" => Findings.call(run, :types => types, :ventilator_ids => ventilators.keys) }
      end

      def totals(runs)
        by_direction = Assignment::DIRECTIONS.map do |direction|
          { "direction" => direction }.merge(sums(runs.select { |run| run.direction == direction }))
        end
        { "by_direction" => by_direction }.merge(sums(runs))
      end

      # One row per Ventilator in id order, one with no ducts reading zero: each direction's length, quantity applied.
      # Runs in a group linked to no existing Ventilator add to none.
      def ventilator_rows(runs, ventilators)
        ventilators.keys.sort.map do |id|
          mine = runs.select { |run| run.ventilator_id == id }
          { "ventilator_id" => id, "name" => ventilators.fetch(id).fetch("name") }
            .merge(Assignment::DIRECTIONS.to_h do |direction|
              ["#{direction}_length_m", mine.select { |run| run.direction == direction }.sum(0.0, &:counted_length_m)]
            end)
        end
      end

      # One row per Duct Type in id order, an unused one reading zero.
      def type_rows(runs, types)
        used = used_lengths(runs)
        types.keys.sort.map do |id|
          { "duct_type_id" => id, "name" => types.fetch(id).fetch("name"), "used_length_m" => used.fetch(id, 0.0),
            "line_count" => runs.select { |run| run.duct_type_id == id }.sum { |run| run.facts.length } }
        end
      end

      # Each Duct Type id's used length, quantity applied.
      def used_lengths(runs)
        runs.group_by(&:duct_type_id).transform_values { |typed| typed.sum(0.0, &:counted_length_m) }
      end

      def sums(runs)
        { "run_count" => runs.length, "line_count" => runs.sum { |run| run.facts.length },
          "length_m" => runs.sum(0.0, &:counted_length_m) }
      end
      private_class_method :row, :totals, :sums
    end

    # The schedule a bounded page at a time (LineGroups::SchedulePages), with the Ventilators and Duct Types as its
    # detail lists.
    module SchedulePages
      PAGE = "#{FEATURE_ID}.schedule".freeze
      MEMBERS = "#{FEATURE_ID}.runs.members".freeze
      DETAILS = "#{FEATURE_ID}.schedule.details".freeze
      # Each list the details read pages, by the key its rows sort by.
      PARTS = { "ventilators" => "ventilator_id", "types" => "duct_type_id", "unreadable" => "path" }.freeze
      PAGES = LineGroups::SchedulePages.new(
        :page => PAGE, :members => MEMBERS, :details => DETAILS, :parts => PARTS,
        :counts => { "ventilators" => "ventilator_count", "types" => "type_count" }.freeze,
        :names => %w[display_name ventilator_name duct_type_name].freeze, :run_label => "duct run",
        :schedule => ->(request) { Scan.schedule(request) }
      )
    end
  end
end
