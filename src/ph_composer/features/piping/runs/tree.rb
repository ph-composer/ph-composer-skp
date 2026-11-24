# frozen_string_literal: true

module PhComposer
  module Piping
    # Runs and the tree they form: what the schedule shows and the export writes. Everything under runs/ is pure Ruby
    # over detached facts and needs no SketchUp, so the live read and the export compute the same runs and offline
    # tests need no stub. Runs are derived, never stored; nothing points at a run.
    module Runs
      # One pipe occurrence, detached. `path` is root to Edge; `group` is its Piping group occurrence as
      # `{ "group_id", "group_path", "name", "hot_water_system_id", "in_zone" }`; `record_id` is its assignment's
      # `ppe_` id, which a split shares; `pipe_type_id`, `role` and `values` (the role's values) are the assignment's.
      # `points_m` are its two world endpoints in metres and `vertex_ids` its two vertices' persistent ids, which
      # belong to the group occurrence; `shared` is true when it is reached through storage another placement draws.
      Fact = Struct.new(:path, :group, :record_id, :pipe_type_id, :role, :values, :points_m, :vertex_ids, :shared,
                        keyword_init: true)

      # One run: a maximal chain of pipes of one role, Pipe Type and role values in one Piping group occurrence.
      # `points_m` are in order, the first repeated last when `closed`; `edge_paths[i]` joins `points_m[i]` and
      # `points_m[i + 1]`; `facts` are the pipes in that order.
      # `parent` is the identifier of the trunk a branch hangs from, or the branch a twig hangs from; `candidates` are
      # every run it touches that could be its parent, and `children` every run of the role below it that touches it.
      Run = Struct.new(:identifier, :display_name, :role, :pipe_type_id, :values, :group, :container_path, :closed,
                       :points_m, :edge_paths, :facts, :parent, :candidates, :children,
                       keyword_init: true) do
        def length_m
          points_m.each_cons(2).sum(0.0) { |a, b| EdgeRuns.distance(a, b) }
        end

        def hot_water_system_id
          group["hot_water_system_id"]
        end

        # Each pipe's segment identifier, in run order (Tree, "identifiers").
        def segments
          facts.map { |fact| Tree.digest("pipe_seg", [fact.path, EdgeRuns.point_keys(fact.points_m).sort]) }
        end

        # Every vertex the run passes, as the chain rule keys it, so two group occurrences never touch.
        def nodes
          facts.flat_map { |fact| fact.vertex_ids.map { |id| [container_path, id] } }.uniq
        end
      end

      # A run's identifier digests its container path, role, Pipe Type, role values and canonical points; a pipe's
      # segment identifier digests its Edge path and canonical endpoints. Neither uses the assignment id, which a
      # split Edge shares. `pipe_` and 16 hex digits for a run, `pipe_seg_` and 16 for a segment.
      module Tree
        ROLE_WORDS = { "trunk" => "Trunk", "branch" => "Branch", "twig" => "Twig",
                       "recirculation" => "Recirculation" }.freeze
        # Which role a role hangs from; recirculation and trunks hang from nothing.
        PARENT_ROLE = { "branch" => "trunk", "twig" => "branch" }.freeze

        module_function

        # Every run of `facts`, parented, identified and named, in schedule order: by Hot Water System, Piping group
        # path, role and the run's smallest point.
        def call(facts)
          keyed = facts.map do |fact|
            EdgeRuns::Fact.new(:path => fact.path, :key => key(fact), :vertex_ids => fact.vertex_ids,
                               :points_m => fact.points_m, :item => fact)
          end
          runs = EdgeRuns.build(keyed).map { |run| run_from(run) }
          parent(runs)
          ordered = order(runs)
          counters = Hash.new(0)
          ordered.each do |run|
            counter = [run.hot_water_system_id, run.role]
            counters[counter] += 1
            run.display_name = "#{ROLE_WORDS.fetch(run.role)} #{counters[counter]}"
          end
          ordered
        end

        # Pipes join when they share a group occurrence, role, Pipe Type and role values. A number is compared as a
        # float, so a multiplier of 12 and one of 12.0 are one trunk, whichever a caller wrote.
        def key(fact)
          [fact.path[0...-1], fact.role, fact.pipe_type_id.to_s, values_key(fact.values)]
        end

        def values_key(values)
          values.sort.map { |name, value| [name, value.is_a?(Numeric) ? value.to_f : value] }
        end

        def run_from(run)
          sample = run.facts.first.item
          points = EdgeRuns.point_keys(run.points_m)
          identifier = digest("pipe", [run.container_path, sample.role, sample.pipe_type_id,
                                       values_key(sample.values), points])
          Run.new(:identifier => identifier, :role => sample.role, :pipe_type_id => sample.pipe_type_id,
                  :values => sample.values, :group => sample.group, :container_path => run.container_path,
                  :closed => run.closed, :points_m => run.points_m, :edge_paths => run.edge_paths,
                  :facts => run.items, :candidates => [], :children => [])
        end

        def digest(prefix, value)
          "#{prefix}_#{CanonicalJson.digest(value)[0, 16]}"
        end

        # A branch's parent is the trunk run of its group occurrence that shares one of its vertices, a twig's the
        # branch run that does. Of two or more, the one whose identifier sorts first.
        def parent(runs)
          at = Hash.new { |hash, node| hash[node] = [] }
          runs.each { |run| run.nodes.each { |node| at[node] << run } }
          runs.each do |run|
            parent_role = PARENT_ROLE[run.role]
            next unless parent_role

            # By identity: a run's Struct hash would walk its pipes and the tree it hangs in.
            run.candidates = run.nodes.flat_map { |node| at.fetch(node) }.select { |other| other.role == parent_role }
                                .uniq(&:object_id).sort_by(&:identifier)
            run.candidates.each { |candidate| candidate.children << run }
            run.parent = run.candidates.first&.identifier
          end
        end

        def order(runs)
          runs.sort_by do |run|
            points = EdgeRuns.point_keys(run.points_m)
            [run.hot_water_system_id.to_s, run.container_path, Assignment::ROLES.index(run.role), points.min, points,
             run.identifier]
          end
        end
      end
    end
  end
end
