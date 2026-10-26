# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Runs
      # The schedule's findings (CONTRACTS section 6) that need no Windows read. A run's findings sit on its
      # row; an assigned Edge no Zone holds is in no run and reports on its own. Each locates the Edges it is
      # about with runs.locate's params. Only a missing type and a missing psi-value block export.
      module Findings
        # SketchUp's merge tolerance (context/SKETCHUP_HOST_BEHAVIOR.md), used here only across Zones, where
        # no vertex can be shared.
        COINCIDENT_M = 0.0254e-3
        # Coincidence is looked up on a grid this coarse, then checked exactly; a grid at the tolerance
        # itself would miss two endpoints that straddle a cell boundary, so the lookup reads the
        # neighbouring cells too.
        CELL_M = 1.0e-3
        INTERIOR = %w[Surface Adiabatic].freeze

        module_function

        # `types` maps a type id to its record, or has no key for a type that no longer exists.
        def for_run(run, types, coincident)
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
          twice = run.facts.select { |fact| coincident.key?(fact.path) }
          unless twice.empty?
            found << finding("thermal_bridge.counted_twice", "#{count(twice)} also assigned in another Zone, so the " \
                                                             "bridge is counted twice; clear one.",
                             twice.map(&:path), false)
          end
          shared = run.facts.select(&:shared)
          unless shared.empty?
            found << finding("thermal_bridge.shared_definition", "#{count(shared)} inside shared component " \
                                                                 "storage, counted once per placement.",
                             shared.map(&:path), false)
          end
          found
        end

        # An Edge with no classified Face is likely a stray line; one whose classified Faces all face
        # another Zone (Surface or To neighbour) is an interior junction. An unclassified Face
        # beside a classified one changes neither.
        def face_findings(run)
          stray = run.facts.select { |fact| classified(fact).empty? }
          interior = run.facts.select do |fact|
            faces = classified(fact)
            !faces.empty? && faces.all? { |values| INTERIOR.include?(values["boundary_condition"]) }
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
                                                 "so it is not exported. Move it into a Zone, or clear it.",
                  [fact.path], false).merge("path" => fact.path)
        end

        # The paths, as Hash keys, of Zone-held facts coincident, within the tolerance and either way round,
        # with a fact in another Zone occurrence, of any type. Only whole Edges compare: an Edge one Zone
        # splits where the other does not is not found.
        def coincident(facts)
          cells = Hash.new { |hash, cell| hash[cell] = [] }
          facts.each { |fact| fact.points_m.each { |point| cells[cell(point)] << fact } }
          facts.each_with_object([]) do |fact, found|
            candidates = neighbours(cell(fact.points_m.first)).flat_map { |key| cells.fetch(key, []) }.uniq
            other = candidates.find do |candidate|
              candidate.zone.fetch("zone_path") != fact.zone.fetch("zone_path") && same_segment?(fact, candidate)
            end
            found << fact.path if other
          end.to_h { |path| [path, true] }
        end

        def same_segment?(one, other)
          a, b = one.points_m
          c, d = other.points_m
          (near?(a, c) && near?(b, d)) || (near?(a, d) && near?(b, c))
        end

        def near?(one, other)
          Chains.distance(one, other) <= COINCIDENT_M
        end

        def cell(point)
          point.map { |value| (value / CELL_M).floor }
        end

        def neighbours(cell)
          offsets = [-1, 0, 1]
          offsets.product(offsets, offsets).map { |delta| cell.zip(delta).map(&:sum) }
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
