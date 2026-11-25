# frozen_string_literal: true

module PhComposer
  module Ducting
    # Duct runs: what the schedule shows and the export writes. Pure Ruby over detached facts, so the live read and the
    # export compute the same runs and offline tests need no stub. Runs are derived, never stored; nothing points at a
    # run. Only a run's sum matters, not how its ducts connect, so the chain rule is not used: the ducts of one key in
    # one Ducting group occurrence are one run whether they touch or not.
    #
    # A run's identifier digests its container path, direction, Duct Type, quantity and canonical points (`duct_` and
    # 16 hex digits); a duct's segment identifier digests its Edge path and sorted endpoints (`duct_seg_` and 16).
    # Neither uses the assignment id, which a split Edge shares.
    module Runs
      DIRECTION_WORDS = { "outdoor_air" => "Outdoor air", "exhaust_air" => "Exhaust air" }.freeze

      # One duct occurrence, detached. `path` is root to Edge; `group` is its Ducting group occurrence as
      # `{ "group_id", "group_path", "name", "ventilator_id", "in_zone" }`; `record_id` is its assignment's `dce_` id,
      # which a split shares; `duct_type_id`, `direction` and `quantity` are the assignment's. `points_m` are its two
      # world endpoints in metres; `shared` is true when it is reached through storage another placement draws.
      Fact = Struct.new(:path, :group, :record_id, :duct_type_id, :direction, :quantity, :points_m, :shared,
                        keyword_init: true) do
        def length_m
          EdgeRuns.distance(*points_m)
        end

        # Its endpoints at a micrometre, sorted, so a line drawn either way is the same line.
        def point_keys
          EdgeRuns.point_keys(points_m).sort
        end
      end

      # One run: every duct of one direction, Duct Type and quantity in one Ducting group occurrence, its `facts` in
      # canonical order (by sorted endpoints, then path).
      Run = Struct.new(:identifier, :display_name, :direction, :duct_type_id, :quantity, :group, :container_path,
                       :facts, keyword_init: true) do
        def ventilator_id
          group["ventilator_id"]
        end

        def edge_paths
          facts.map(&:path)
        end

        # The drawn length, the sum of its ducts'.
        def length_m
          facts.sum(0.0, &:length_m)
        end

        # What the export carries: the drawn length once per identical duct the quantity stands for.
        def counted_length_m
          length_m * quantity
        end

        # Each duct's segment identifier, in run order.
        def segments
          facts.map { |fact| Runs.digest("duct_seg", [fact.path, fact.point_keys]) }
        end
      end

      module_function

      # Every run of `facts`, identified and named, in schedule order: by Ventilator, Ducting group path, direction and
      # the run's smallest point. Names are the direction word and a counter per Ventilator and direction.
      def call(facts)
        runs = facts.group_by { |fact| [fact.path[0...-1], fact.direction, fact.duct_type_id, fact.quantity] }
                    .map { |key, members| run(*key, members) }
        counters = Hash.new(0)
        runs.sort_by { |run| order(run) }.each do |run|
          counter = [run.ventilator_id, run.direction]
          counters[counter] += 1
          run.display_name = "#{DIRECTION_WORDS.fetch(run.direction)} #{counters[counter]}"
        end
      end

      def run(container_path, direction, duct_type_id, quantity, members)
        facts = members.sort_by { |fact| [fact.point_keys, fact.path] }
        identifier = digest("duct", [container_path, direction, duct_type_id, quantity, facts.map(&:point_keys)])
        Run.new(:identifier => identifier, :direction => direction, :duct_type_id => duct_type_id,
                :quantity => quantity, :group => facts.first.group, :container_path => container_path,
                :facts => facts)
      end

      def digest(prefix, value)
        "#{prefix}_#{CanonicalJson.digest(value)[0, 16]}"
      end

      def order(run)
        [run.ventilator_id.to_s, run.container_path, Assignment::DIRECTIONS.index(run.direction),
         run.facts.first.point_keys, run.identifier]
      end
      private_class_method :run, :order
    end
  end
end
