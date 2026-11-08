# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Runs
      # Assigned Edges that lie on one another in different Zones, before they chain into runs
      # (context/TECH_STACK.md, "Edge-owned assignments"). Each Zone holds its own Edge at a junction two Zones
      # meet at, so a user may assign it from either Zone or both. Edges alike in Building-Segment, type and
      # quantity are one bridge and count once; Edges that differ in any of those are a conflict, which both
      # still count until the user clears one, since no rule says which is right. Only whole Edges compare: an
      # Edge one Zone splits where the other does not is neither.
      module Coincidence
        # SketchUp's merge tolerance (context/SKETCHUP_HOST_BEHAVIOR.md), which here only meets Edges in
        # different containers, where no vertex can be shared.
        COINCIDENT_M = 0.0254e-3
        # Coincidence is looked up on a grid this coarse, then checked exactly; a grid at the tolerance
        # itself would miss two endpoints that straddle a cell boundary, so the lookup reads the
        # neighbouring cells too.
        CELL_M = 1.0e-3

        # `facts` are the Edges that count, in the order given. `conflicts` maps the path of each of them that
        # is in conflict to the facts it conflicts with.
        Resolved = Struct.new(:facts, :conflicts, keyword_init: true)

        module_function

        # Of Edges alike, the one in the Zone with the smallest path stands for them, whatever order they
        # arrive in and whatever the Zones are called, so a run's identifier survives a rename and a rescan.
        # It takes their Faces too: the junction is interior only if it is interior from every Zone.
        def resolve(facts)
          others = coinciding(facts)
          kept = facts.reject do |fact|
            others.fetch(fact.path).any? { |other| alike?(fact, other) && first?(other, fact) }
          end
          conflicts = kept.each_with_object({}) do |fact, found|
            differing = others.fetch(fact.path).reject { |other| alike?(fact, other) }
            found[fact.path] = differing unless differing.empty?
          end
          Resolved.new(:facts => kept.map { |fact| standing_for(fact, others.fetch(fact.path)) },
                       :conflicts => conflicts)
        end

        # Each fact's path to the facts in other Zone occurrences on the same line, within the tolerance and
        # either way round, of any type.
        def coinciding(facts)
          cells = Hash.new { |hash, cell| hash[cell] = [] }
          facts.each { |fact| fact.points_m.each { |point| cells[cell(point)] << fact } }
          facts.to_h do |fact|
            candidates = neighbours(cell(fact.points_m.first)).flat_map { |key| cells.fetch(key, []) }.uniq
            [fact.path, candidates.select { |candidate| across?(fact, candidate) && coincide?(fact, candidate) }]
          end
        end

        def across?(one, other)
          one.zone.fetch("zone_path") != other.zone.fetch("zone_path")
        end

        def coincide?(one, other)
          a, b = one.points_m
          c, d = other.points_m
          (near?(a, c) && near?(b, d)) || (near?(a, d) && near?(b, c))
        end

        def near?(one, other)
          Chains.distance(one, other) <= COINCIDENT_M
        end

        # One bridge: Building-Segment, type and quantity, as no single quantity stands for two that differ.
        def alike?(one, other)
          differences(one, other).empty?
        end

        # What sets two coincident Edges apart, in the words a finding uses.
        def differences(one, other)
          words = []
          words << "Thermal Bridge Type" if one.type_id != other.type_id
          words << "quantity" if one.quantity.to_f != other.quantity.to_f
          words << "Building-Segment" if one.zone["building_segment"] != other.zone["building_segment"]
          words
        end

        def first?(one, other)
          (one.zone.fetch("zone_path") <=> other.zone.fetch("zone_path")).negative?
        end

        def standing_for(fact, others)
          alike = others.select { |other| alike?(fact, other) }
          return fact if alike.empty?

          fact.dup.tap { |kept| kept.faces = fact.faces + alike.flat_map(&:faces) }
        end

        def cell(point)
          point.map { |value| (value / CELL_M).floor }
        end

        def neighbours(cell)
          offsets = [-1, 0, 1]
          offsets.product(offsets, offsets).map { |delta| cell.zip(delta).map(&:sum) }
        end
      end
    end
  end
end
