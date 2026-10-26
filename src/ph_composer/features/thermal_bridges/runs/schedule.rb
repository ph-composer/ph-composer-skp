# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Runs
      # The schedule from facts: one row per run with its length, psi-value, quantity and psi times length
      # times quantity in W/K, totals by type and by group, and each run's findings. All arithmetic is
      # here, in SI; the panel formats (context/CODING_STANDARDS.md, "Layering").
      module Schedule
        module_function

        # `facts` are every assigned Edge occurrence, Zone-held or not; `types` maps a type id to its
        # record. Runs come from the Zone-held facts; the others report as outside a Zone.
        def call(facts, types:)
          held, outside = facts.partition(&:zone)
          runs = Chains.build(held, :type_names => types.transform_values { |type| type.fetch("name") })
          coincident = Findings.coincident(held)
          rows = runs.map { |run| row(run, types, Findings.for_run(run, types, coincident)) }
          { "runs" => rows, "edge_findings" => outside.map { |fact| Findings.outside(fact) },
            "totals" => totals(rows, types) }
        end

        def row(run, types, findings)
          type = types[run.type_id]
          psi = type && type["psi_w_mk"]
          length = run.length_m
          { "identifier" => run.identifier, "display_name" => run.display_name,
            "zone" => run.zone, "type_id" => run.type_id, "type_name" => type && type.fetch("name"),
            "group" => type && type.fetch("group"), "psi_w_mk" => psi, "quantity" => run.quantity,
            "length_m" => length, "heat_loss_w_k" => psi && psi * length * run.quantity,
            "closed" => run.closed, "points_m" => run.points_m, "edge_paths" => run.edge_paths,
            "shared" => run.facts.any?(&:shared), "findings" => findings,
            "locate" => { "edge_paths" => run.edge_paths } }
        end

        # By type for every type that has a run, a missing one included; by group for every group, so a
        # group with no run reads zero. A run whose type or psi-value is missing has no heat loss and adds
        # to no group: its finding blocks export.
        def totals(rows, types)
          by_type = rows.group_by { |row| row.fetch("type_id") }.sort.map do |id, typed|
            losses = typed.map { |row| row.fetch("heat_loss_w_k") }
            { "type_id" => id, "type_name" => types[id]&.fetch("name"), "group" => types[id]&.fetch("group"),
              "run_count" => typed.length, "edge_count" => typed.sum { |row| row.fetch("edge_paths").length },
              "length_m" => typed.sum(0.0) { |row| row.fetch("length_m") },
              "heat_loss_w_k" => losses.any?(&:nil?) ? nil : losses.sum(0.0) }
          end
          by_group = Type::GROUPS.map do |group|
            grouped = rows.select { |row| row.fetch("group") == group }
            { "group" => group, "heat_loss_w_k" => grouped.sum(0.0) { |row| row.fetch("heat_loss_w_k") || 0.0 } }
          end
          { "by_type" => by_type, "by_group" => by_group, "run_count" => rows.length,
            "heat_loss_w_k" => by_group.sum(0.0) { |group| group.fetch("heat_loss_w_k") } }
        end
      end
    end
  end
end
