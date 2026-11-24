# frozen_string_literal: true

module PhComposer
  module Piping
    module Runs
      # The schedule from facts: one row per run with its System, group, role, parent, Pipe Type, drawn length, line
      # count, role values and findings; totals by role; one row per Hot Water System with its distribution length by
      # role and its recirculation sum; one row per Pipe Type with its used length. All arithmetic is here, in SI; a
      # panel formats. Totals are drawn length: a trunk's multiplier is a column, never applied, as honeybee-ph's
      # `total_length` does not apply it.
      module Schedule
        DISTRIBUTION = %w[trunk branch twig].freeze

        module_function

        # `facts` are every readable pipe occurrence; `types` maps a Pipe Type id to its record; `systems` maps a Hot
        # Water System id to its record.
        def call(facts, types:, systems:)
          runs = Tree.call(facts)
          by_id = runs.to_h { |run| [run.identifier, run] }
          rows = runs.map { |run| row(run, by_id, types, systems) }
          { "runs" => rows, "totals" => totals(rows), "systems" => system_rows(runs, systems),
            "types" => type_rows(runs, types) }
        end

        def row(run, by_id, types, systems)
          type = types[run.pipe_type_id]
          parent = run.parent && by_id.fetch(run.parent)
          { "identifier" => run.identifier, "display_name" => run.display_name, "role" => run.role,
            "hot_water_system_id" => run.hot_water_system_id,
            "hot_water_system_name" => systems[run.hot_water_system_id]&.fetch("name"),
            "group" => run.group.slice("group_id", "group_path", "name"),
            "parent" => parent && parent.identifier, "parent_name" => parent && parent.display_name,
            "pipe_type_id" => run.pipe_type_id, "pipe_type_name" => type && type.fetch("name"),
            "length_m" => run.length_m, "line_count" => run.facts.length, "values" => run.values,
            "closed" => run.closed, "edge_paths" => run.edge_paths,
            "shared" => run.facts.any?(&:shared),
            "findings" => Findings.call(run, :types => types, :system_ids => systems.keys) }
        end

        def totals(rows)
          by_role = Assignment::ROLES.map do |role|
            roled = rows.select { |row| row.fetch("role") == role }
            { "role" => role, "run_count" => roled.length, "line_count" => roled.sum { |row| row.fetch("line_count") },
              "length_m" => roled.sum(0.0) { |row| row.fetch("length_m") } }
          end
          { "by_role" => by_role, "run_count" => rows.length,
            "line_count" => rows.sum { |row| row.fetch("line_count") },
            "distribution_length_m" => length(rows, DISTRIBUTION),
            "recirculation_length_m" => length(rows, ["recirculation"]) }
        end

        # One row per Hot Water System in id order, a System with no pipes included: its distribution length by role
        # and its recirculation sum. Runs in a group linked to no existing System add to none. `runs` are in schedule
        # order, which is the order the recirculation sum adds them in.
        def system_rows(runs, systems)
          systems.keys.sort.map do |id|
            mine = runs.select { |run| run.hot_water_system_id == id }
            { "hot_water_system_id" => id, "name" => systems.fetch(id).fetch("name"),
              "distribution_length_m" => DISTRIBUTION.to_h do |role|
                [role, mine.select { |run| run.role == role }.sum(0.0, &:length_m)]
              end }.merge(Recirculation.call(mine.select { |run| run.role == "recirculation" }))
          end
        end

        # One row per Pipe Type in id order, an unused one reading zero.
        def type_rows(runs, types)
          types.keys.sort.map do |id|
            typed = runs.select { |run| run.pipe_type_id == id }
            { "pipe_type_id" => id, "name" => types.fetch(id).fetch("name"),
              "used_length_m" => typed.sum(0.0, &:length_m), "line_count" => typed.sum { |run| run.facts.length } }
          end
        end

        def length(rows, roles)
          rows.select { |row| roles.include?(row.fetch("role")) }.sum(0.0) { |row| row.fetch("length_m") }
        end
      end
    end
  end
end
