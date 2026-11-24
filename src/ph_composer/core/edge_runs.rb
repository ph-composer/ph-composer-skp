# frozen_string_literal: true

module PhComposer
  # The chain rule (context/TECH_STACK.md, "Edge-owned assignments"): Edges that carry one caller's grouping key
  # join into runs where they share a vertex. Pure Ruby over detached facts, so a live read and an export compute
  # the same runs and a test needs no stub. It names no feature: the caller chooses the key, reads its own `item`
  # back from each run, and names and identifies the runs itself.
  #
  # Edges join where they share a vertex keyed on the Edge's container path plus the vertex id: inside one Entities
  # collection SketchUp has already merged endpoints within 0.0254 mm, so the id is exact, and two placements of one
  # component carry the same vertex ids in different containers, so they never join. A run ends at a free end and at
  # a vertex where the count of joining Edges of its key is not two, so a T of one key is three runs; a chain with no
  # end is one closed run. Order is deterministic over micrometre-rounded points.
  module EdgeRuns
    # Points are compared at a micrometre, so float noise from a transform cannot reorder a run.
    DIGITS = 6

    # One Edge occurrence, detached. `path` is root to Edge; `key` groups the Edges that may join, and is compared by
    # its `to_s`; `vertex_ids` are its two vertices' persistent ids, which belong to its container; `points_m` are its
    # two world endpoints in metres, in the same order; `item` is whatever the caller reads back from the run.
    Fact = Struct.new(:path, :key, :vertex_ids, :points_m, :item, keyword_init: true) do
      def container_path
        path[0...-1]
      end

      def length_m
        EdgeRuns.distance(*points_m)
      end
    end

    # One run: a maximal chain of Edges of one key in one container. `points_m` are in order, the first repeated
    # last when `closed`; `edge_paths[i]` joins `points_m[i]` and `points_m[i + 1]`; `facts` are the Edges in that
    # order.
    Run = Struct.new(:key, :container_path, :closed, :points_m, :edge_paths, :facts, keyword_init: true) do
      def length_m
        points_m.each_cons(2).sum(0.0) { |a, b| EdgeRuns.distance(a, b) }
      end

      def items
        facts.map(&:item)
      end
    end

    module_function

    # Every run of `facts`, key by key in the order of the keys' `to_s`, each key's runs in chain order.
    def build(facts)
      groups = facts.group_by(&:key)
      groups.keys.sort_by(&:to_s).flat_map { |key| chains(groups.fetch(key)) }
    end

    def distance(start, finish)
      Math.sqrt(start.zip(finish).sum { |a, b| (a - b)**2 })
    end

    # Adding 0.0 turns a -0.0 from rounding into 0.0, which would otherwise digest differently.
    def point_key(point)
      point.map { |value| value.round(DIGITS) + 0.0 }
    end

    def point_keys(points)
      points.map { |point| point_key(point) }
    end

    def before?(point, other)
      (point_key(point) <=> point_key(other)).negative?
    end

    # Each vertex an Edge ends at, as the chain rule keys it: its container path and its persistent id.
    def nodes(fact)
      fact.vertex_ids.map { |id| [fact.container_path, id] }
    end

    # The chains in one key, open ones from every vertex that is not a pass-through, then the loops that are left.
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
      canonical(order, points, closed)
    end

    # Open runs start at their lexicographically smaller end, and where the ends meet (a loop hung from a junction)
    # run the way whose points sort first. A closed run starts at its smallest point and turns toward the smaller of
    # that point's neighbours. So two scans of one geometry agree.
    def canonical(order, points, closed)
      sample = order.first
      paths = order.map(&:path)
      if closed
        points = points[0...-1]
        start = (0...points.length).min_by { |i| point_key(points[i]) }
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
      elsif (point_keys(points.reverse) <=> point_keys(points)).negative?
        points = points.reverse
        paths = paths.reverse
        order = order.reverse
      end
      Run.new(:key => sample.key, :container_path => sample.container_path, :closed => closed, :points_m => points,
              :edge_paths => paths, :facts => order)
    end
    private_class_method :chains, :walk, :canonical
  end
end
