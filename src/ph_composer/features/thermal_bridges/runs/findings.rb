# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Runs
      # The findings of CONTRACTS section 6. A run's findings sit on its row; an assigned Edge no Zone holds is
      # in no run and reports on its own. Each locates the Edges it is about with runs.locate's params. Only a
      # missing type and a missing psi-value block export. The window-perimeter finding needs Windows' outlines,
      # which the export preflight and contributor read and the schedule does not.
      module Findings
        COINCIDENT_M = Coincidence::COINCIDENT_M
        INTERIOR = %w[Surface Adiabatic].freeze

        module_function

        # `types` maps a type id to its record, or has no key for a type that no longer exists. `conflicts` is
        # Coincidence's map of an Edge's path to the Edges it conflicts with. `outlines` are placed Windows'
        # world outlines in metres, each a list of corner points; none when not read.
        def for_run(run, types, conflicts, outlines = [])
          type = types[run.type_id]
          found = []
          if type.nil?
            found << finding("thermal_bridge.type_missing", "Thermal Bridge Type #{run.type_id} no longer exists; " \
                                                            "reassign or clear these Edges.", run.edge_paths, true)
          elsif type["psi_w_mk"].nil?
            found << finding("thermal_bridge.psi_missing", "#{type.fetch('name')} has no psi-value.",
                             run.edge_paths, true)
          end
          found.concat(face_findings(run))
          found.concat(conflict(run, conflicts))
          shared = run.facts.select(&:shared)
          unless shared.empty?
            found << finding("thermal_bridge.shared_definition", "#{count(shared)} inside shared component " \
                                                                 "storage, counted once per placement.",
                             shared.map(&:path), false)
          end
          found.concat(perimeter(run, outlines))
        end

        # A run's Edges that coincide with an Edge another Zone assigns differently: which Zones, and what differs.
        def conflict(run, conflicts)
          facts = run.facts.select { |fact| conflicts.key?(fact.path) }
          return [] if facts.empty?

          others = facts.flat_map { |fact| conflicts.fetch(fact.path) }
          zones = others.map { |other| other.zone["name"].to_s }.uniq.sort.join(", ")
          words = others.flat_map { |other| Coincidence.differences(facts.first, other) }.uniq.join(" and ")
          [finding("thermal_bridge.coincident_conflict", "#{count(facts)} also assigned in #{zones} with a different " \
                                                         "#{words}, so both are counted; clear one.",
                   facts.map(&:path), false)]
        end

        # An Edge lying on a placed Window's outline, both its ends within the merge tolerance of one side of it.
        # A placed Window adds no Edge to its wall, so this is a line drawn around the opening, and a psi-value
        # there belongs to the Window Type's install.
        def perimeter(run, outlines)
          # Most Edges are nowhere near a given Window: its box rules them out before any side is measured.
          boxed = outlines.map { |outline| [outline, outline.transpose.map(&:minmax)] }
          on = run.facts.select do |fact|
            boxed.any? do |outline, box|
              next false unless fact.points_m.all? { |point| within?(point, box) }

              outline.zip(outline.rotate).any? do |a, b|
                fact.points_m.all? { |point| segment_distance(point, a, b) <= COINCIDENT_M }
              end
            end
          end
          return [] if on.empty?

          [finding("thermal_bridge.on_window_perimeter", "#{count(on)} on a placed Window's outline; its install " \
                                                         "psi-value belongs to the Window Type. Clear them.",
                   on.map(&:path), false)]
        end

        # Whether `point` lies in `box`, each axis's [min, max], grown by the merge tolerance.
        def within?(point, box)
          point.zip(box).all? { |value, (low, high)| value.between?(low - COINCIDENT_M, high + COINCIDENT_M) }
        end

        # The distance from `point` to the segment from `a` to `b`.
        def segment_distance(point, a, b)
          along = b.zip(a).map { |end_value, start| end_value - start }
          offset = point.zip(a).map { |value, start| value - start }
          squared = along.sum { |value| value * value }
          t = squared.zero? ? 0.0 : (offset.zip(along).sum { |x, y| x * y } / squared).clamp(0.0, 1.0)
          Chains.distance(point, a.zip(along).map { |start, delta| start + (t * delta) })
        end

        # An Edge with no classified Face is likely a stray line; one whose Zone Faces all face another
        # Zone (Surface or To neighbour) is an interior junction. An unclassified Face beside an interior one
        # shows nothing about its side, so that Edge is neither.
        def face_findings(run)
          stray = run.facts.select { |fact| classified(fact).empty? }
          interior = run.facts.select do |fact|
            !classified(fact).empty? && fact.faces.all? { |values| INTERIOR.include?(values["boundary_condition"]) }
          end
          found = []
          unless stray.empty?
            found << finding("thermal_bridge.no_envelope_face", "#{count(stray)} on no classified envelope Face; " \
                                                                "likely a stray line.", stray.map(&:path), false)
          end
          unless interior.empty?
            found << finding("thermal_bridge.interior_junction", "#{count(interior)} only between interior Faces " \
                                                                 "(Surface or To neighbour).",
                             interior.map(&:path), false)
          end
          found
        end

        # A Face with any recorded value is classified (Zones' rule); one with none is not.
        def classified(fact)
          fact.faces.reject(&:empty?)
        end

        # The finding on an assigned Edge no Zone holds; it is not exported.
        def outside(fact)
          finding("thermal_bridge.outside_zone", "An assigned Edge is not in a Zone (#{fact.reason.tr('_', ' ')}), " \
                                                 "so it is not exported. Move it into a Zone, or remove its " \
                                                 "assignment: #{Assignment::Repair::ROUTE}.",
                  [fact.path], false).merge("path" => fact.path)
        end

        def count(facts)
          facts.length == 1 ? "1 Edge is" : "#{facts.length} Edges are"
        end

        def finding(code, message, paths, blocks)
          { "code" => code, "message" => message, "blocks_export" => blocks, "locate" => { "edge_paths" => paths } }
        end
      end
    end
  end
end
