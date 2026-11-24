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
      # shared Group storage. `record_id` is its assignment's `tbe_` id, which only names it in a finding.
      Fact = Struct.new(:path, :zone, :reason, :record_id, :type_id, :quantity, :points_m, :vertex_ids, :faces,
                        :shared, keyword_init: true) do
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

      # Thermal bridges' runs by the chain rule in `core/edge_runs.rb`: Edges join within one Zone occurrence, type
      # and quantity. This adapter keys the facts, reads each run's Zone, type and quantity back from its first Edge,
      # and names and identifies the runs.
      module Chains
        module_function

        # Runs from facts that each have a Zone, in a deterministic order, named and identified.
        # `type_names` maps a type id to its name; a type id with no name keeps the id.
        def build(facts, type_names:)
          # A quantity of 1 and one of 1.0 are one quantity, whichever a caller wrote.
          keyed = facts.map do |fact|
            EdgeRuns::Fact.new(:path => fact.path, :key => [fact.zone.fetch("zone_path"), fact.type_id,
                                                            fact.quantity.to_f],
                               :vertex_ids => fact.vertex_ids, :points_m => fact.points_m, :item => fact)
          end
          runs = EdgeRuns.build(keyed).map do |run|
            sample = run.facts.first.item
            Run.new(:zone => sample.zone, :type_id => sample.type_id, :quantity => sample.quantity,
                    :container_path => run.container_path, :closed => run.closed, :points_m => run.points_m,
                    :edge_paths => run.edge_paths, :facts => run.items)
          end
          name(runs, type_names)
        end

        def distance(start, finish)
          EdgeRuns.distance(start, finish)
        end

        def key(point)
          EdgeRuns.point_key(point)
        end

        def keys(points)
          EdgeRuns.point_keys(points)
        end

        # A run's name is the type name and a counter, numbered per type across the Model by Building-Segment,
        # Zone name and the run's smallest point; the identifier digests the Zone, type, container path and
        # the canonical points, so two coincident placements of one component get two. Both are derived and
        # may change with the geometry; nothing points at a run.
        def name(runs, type_names)
          ordered = runs.sort_by do |run|
            [run.type_id, run.zone["building_segment"].to_s, run.zone["name"].to_s, run.zone.fetch("zone_path"),
             keys(run.points_m).min, run.container_path, keys(run.points_m)]
          end
          counters = Hash.new(0)
          ordered.each do |run|
            counters[run.type_id] += 1
            run.display_name = "#{type_names.fetch(run.type_id, run.type_id)} #{counters[run.type_id]}"
            digest = CanonicalJson.digest([run.zone.fetch("zone_id"), run.type_id, run.container_path,
                                           keys(run.points_m)])
            run.identifier = "tb_#{digest[0, 16]}"
          end
          ordered
        end
      end
    end
  end
end
