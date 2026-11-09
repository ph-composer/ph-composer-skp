# frozen_string_literal: true

module PhComposer
  module Spaces
    # Pure: whether any two of one Volume's Floor Segments cover the same plan area, which then counts twice. A
    # Floor Segment is its world loops in metres, the outer loop first. Height is ignored, so outlines stacked
    # apart overlap. The test is the area they share, so any shape works and Floors tiled edge to edge share none.
    module FloorOverlap
      # Less shared plan area than this is a drawing tolerance, not a floor counted twice.
      MINIMUM_AREA_M2 = 0.01

      module_function

      def any?(floor_segments)
        plans = floor_segments.map { |loops| plan_edges(loops) }
        plans.combination(2).any? { |left, right| shared_area_m2(left, right) >= MINIMUM_AREA_M2 }
      end

      # Every loop's edges in plan, each running toward +x. An edge along y bounds no span of x, so it is left out.
      def plan_edges(loops)
        loops.flat_map do |loop|
          points = loop.map { |x, y, _z| [x, y] }
          points.zip(points.rotate).reject { |from, to| from[0] == to[0] }.map(&:sort)
        end
      end

      # The plan is cut at every corner and every crossing of the two outlines. Between two cuts nothing changes
      # order, so each strip's shared width varies linearly and its value at mid-strip gives the exact area.
      def shared_area_m2(left, right)
        return 0.0 if left.empty? || right.empty?

        low_x, high_x = common_range(left, right, 0)
        low_y, high_y = common_range(left, right, 1)
        return 0.0 unless low_x < high_x && low_y < high_y

        inner = (corners(left) + corners(right) + crossings(left, right)).select { |x| x > low_x && x < high_x }
        ([low_x] + inner.uniq.sort + [high_x]).each_cons(2).sum do |from, to|
          middle = (from + to) / 2.0
          (to - from) * shared_length(spans(left, middle), spans(right, middle))
        end
      end

      def common_range(left, right, axis)
        ranges = [left, right].map { |edges| edges.flatten(1).map { |point| point[axis] }.minmax }
        [ranges.map(&:first).max, ranges.map(&:last).min]
      end

      def corners(edges)
        edges.flatten(1).map(&:first)
      end

      def crossings(left, right)
        left.product(right).filter_map { |edge, other| crossing_x(edge, other) }
      end

      # Where two edges' lines meet, when that is within both edges' reach in x.
      def crossing_x(edge, other)
        turn = slope(edge) - slope(other)
        return nil if turn.abs < 1.0e-12

        x = (y_at(other, 0.0) - y_at(edge, 0.0)) / turn
        x if x > [edge[0][0], other[0][0]].max && x < [edge[1][0], other[1][0]].min
      end

      def slope(((x0, y0), (x1, y1)))
        (y1 - y0) / (x1 - x0).to_f
      end

      def y_at(edge, x)
        edge[0][1] + (slope(edge) * (x - edge[0][0]))
      end

      # The stretches of y inside the outline at `x`: alternate edges in, then out, so a hole is a gap. An edge
      # holds its low end only, so an `x` exactly on a corner still meets an even number of edges.
      def spans(edges, x)
        edges.select { |from, to| from[0] <= x && x < to[0] }.map { |edge| y_at(edge, x) }.sort.each_slice(2).to_a
      end

      def shared_length(left, right)
        left.product(right).sum do |(low, high), (other_low, other_high)|
          [[high, other_high].min - [low, other_low].max, 0.0].max
        end
      end

      private_class_method :plan_edges, :shared_area_m2, :common_range, :corners, :crossings, :crossing_x, :slope,
                           :y_at, :spans, :shared_length
    end
  end
end
