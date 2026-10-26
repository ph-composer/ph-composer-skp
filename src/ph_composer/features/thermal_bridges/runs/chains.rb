# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # Runs: what the schedule shows and the export writes. Everything under runs/ is pure Ruby over
    # detached facts and needs no SketchUp, so the live read and the export contributor compute runs with
    # the same functions and offline tests need no stub.
    module Runs
      # One assigned Edge occurrence, detached. `path` is root to Edge; `zone` is the holding Zone as
      # `{ "zone_id", "zone_path", "name", "building_segment" }`, or nil with `reason` saying why none holds
      # it. `points_m` are its two world endpoints in metres and `vertex_ids` its two vertices' persistent
      # ids, which belong to the Edge's container, as the export snapshot's `edge` entry carries them.
      # `faces` are the recorded values of its Zone Faces, as ph_composer.zones.faces.host_context reads
      # them, empty for an unclassified one; `shared` is true when the Edge is reached through component or
      # shared Group storage.
      Fact = Struct.new(:path, :zone, :reason, :type_id, :quantity, :points_m, :vertex_ids, :faces, :shared,
                        keyword_init: true) do
        def container_path
          path[0...-1]
        end

        def length_m
          Chains.distance(*points_m)
        end
      end

      # One run: a maximal chain of Edges with one Zone occurrence, type and quantity. `points_m` are in
      # order, the first repeated last when `closed`; `edge_paths[i]` joins `points_m[i]` and
      # `points_m[i + 1]`. `facts` are the Edges in that order.
      Run = Struct.new(:zone, :type_id, :quantity, :container_path, :closed, :points_m, :edge_paths, :facts,
                       :display_name, :identifier, keyword_init: true) do
        def length_m
          points_m.each_cons(2).sum(0.0) { |a, b| Chains.distance(a, b) }
        end
      end

      # The chain rule (context/TECH_STACK.md, "Edge-owned assignments"). Edges join where they share a
      # vertex, keyed on the Edge's container path plus the vertex id: inside one Entities collection
      # SketchUp has already merged endpoints within 0.0254 mm, so the id is exact, and two placements of
      # one component carry the same vertex ids in different containers, so they never join. A run ends at
      # a free end and at a vertex where the count of joining Edges is not two, so a T is three runs; a
      # chain with no end is one closed run.
      module Chains
        # Points are compared and digested at a micrometre, so float noise from a transform cannot reorder
        # a run or change its identifier.
        DIGITS = 6

        module_function

        # Runs from facts that each have a Zone, in a deterministic order, named and identified.
        # `type_names` maps a type id to its name; a type id with no name keeps the id.
        def build(facts, type_names:)
          groups = facts.group_by { |fact| [fact.zone.fetch("zone_path"), fact.type_id, fact.quantity] }
          runs = groups.keys.sort_by(&:to_s).flat_map { |key| chains(groups.fetch(key)) }
          name(runs, type_names)
        end

        def distance(start, finish)
          Math.sqrt(start.zip(finish).sum { |a, b| (a - b)**2 })
        end

        def key(point)
          point.map { |value| value.round(DIGITS) }
        end

        def before?(point, other)
          (key(point) <=> key(other)).negative?
        end

        # The chains in one group, open ones from every vertex that is not a pass-through, then the loops
        # that are left.
        def chains(facts)
          at = Hash.new { |hash, node| hash[node] = [] }
          facts.each_with_index do |fact, index|
            nodes(fact).each { |node| at[node] << index }
          end
          used = Array.new(facts.length, false)
          runs = []
          at.keys.sort_by(&:to_s).each do |node|
            next if at.fetch(node).length == 2

            at.fetch(node).each do |index|
              runs << walk(facts, at, used, node, index, :closed => false) unless used[index]
            end
          end
          facts.each_index do |index|
            runs << walk(facts, at, used, nodes(facts[index]).first, index, :closed => true) unless used[index]
          end
          runs
        end

        def nodes(fact)
          fact.vertex_ids.map { |id| [fact.container_path, id] }
        end

        # Follows Edges from `node` through `index` while the next vertex passes straight through.
        def walk(facts, at, used, node, index, closed:)
          points = [facts[index].points_m[nodes(facts[index]).index(node)]]
          order = []
          loop do
            used[index] = true
            fact = facts[index]
            order << fact
            node = (nodes(fact) - [node]).first || node
            points << fact.points_m[nodes(fact).index(node)]
            following = at.fetch(node)
            break unless following.length == 2

            index = (following - [index]).first
            break if index.nil? || used[index]
          end
          canonical(order.first, order, points, closed)
        end

        # Open runs start at their lexicographically smaller end. A loop starts at its smallest point and
        # turns toward the smaller of that point's neighbours. So two scans of one geometry agree.
        def canonical(sample, order, points, closed)
          paths = order.map(&:path)
          if closed
            points = points[0...-1]
            start = (0...points.length).min_by { |i| key(points[i]) }
            points = points.rotate(start)
            paths = paths.rotate(start)
            order = order.rotate(start)
            # Edge i joins points i and i + 1, so turning the other way reverses the Edges outright.
            if before?(points.last, points[1])
              points = [points.first] + points[1..-1].reverse
              paths = paths.reverse
              order = order.reverse
            end
            points += [points.first]
          elsif before?(points.last, points.first)
            points = points.reverse
            paths = paths.reverse
            order = order.reverse
          end
          Run.new(:zone => sample.zone, :type_id => sample.type_id, :quantity => sample.quantity,
                  :container_path => sample.container_path, :closed => closed, :points_m => points,
                  :edge_paths => paths, :facts => order)
        end

        # A run's name is the type name and a counter, numbered per type across the Model by Building-Segment,
        # Zone name and the run's smallest point; the identifier digests the Zone, type, container path and
        # the canonical points, so two coincident placements of one component get two. Both are derived and
        # may change with the geometry; nothing points at a run.
        def name(runs, type_names)
          ordered = runs.sort_by do |run|
            [run.type_id, run.zone["building_segment"].to_s, run.zone["name"].to_s, run.zone.fetch("zone_path"),
             run.points_m.map { |point| key(point) }.min, run.container_path]
          end
          counters = Hash.new(0)
          ordered.each do |run|
            counters[run.type_id] += 1
            run.display_name = "#{type_names.fetch(run.type_id, run.type_id)} #{counters[run.type_id]}"
            digest = CanonicalJson.digest([run.zone.fetch("zone_id"), run.type_id, run.container_path,
                                           run.points_m.map { |point| key(point) }])
            run.identifier = "tb_#{digest[0, 16]}"
          end
        end
      end
    end
  end
end
