# frozen_string_literal: true

module PhComposer
  module Spaces
    # Pure: which Zone a floor surface drawn outside every Zone belongs in, for Create Space's review to
    # preselect. A Zone holds the outline when the outline's plan centroid is inside the plan projection of one
    # of the Zone's Faces and every outline point is inside the Zone's height range. Walls project to nothing,
    # so an L-shaped Zone's notch holds nothing. The first Zone in the order given wins; the user can change it.
    # Points are world metres.
    module ZoneInference
      TOLERANCE_M = 0.01
      # `faces` is one list of loops per Zone Face, the outer loop first.
      Candidate = Struct.new(:reference, :faces, keyword_init: true)

      module_function

      # The reference of the Zone holding `outlines` (one point list per Face), or nil when none does.
      def pick(outlines, candidates)
        points = outlines.flatten(1)
        return nil if points.empty?

        centre = centroid(outlines)
        low, high = points.map { |point| point[2] }.minmax
        found = candidates.find do |candidate|
          heights = candidate.faces.flatten(2).map { |point| point[2] }
          !heights.empty? && low >= heights.min - TOLERANCE_M && high <= heights.max + TOLERANCE_M &&
            candidate.faces.any? { |loops| inside_face?(centre, loops) }
        end
        found&.reference
      end

      # The area-weighted plan centroid of several polygons; their points' mean when they have no plan area.
      def centroid(outlines)
        weighted = outlines.map { |outline| polygon_centroid(outline) }.compact
        total = weighted.sum { |_x, _y, area| area }
        if total.zero?
          points = outlines.flatten(1)
          return [points.sum { |point| point[0] } / points.length, points.sum { |point| point[1] } / points.length]
        end

        [weighted.sum { |x, _y, area| x * area } / total, weighted.sum { |_x, y, area| y * area } / total]
      end

      # [x, y, area] of one polygon in plan, or nil when it has no plan area.
      def polygon_centroid(points)
        doubled = 0.0
        sum_x = 0.0
        sum_y = 0.0
        points.each_with_index do |(x0, y0), index|
          x1, y1 = points[(index + 1) % points.length]
          cross = (x0 * y1) - (x1 * y0)
          doubled += cross
          sum_x += (x0 + x1) * cross
          sum_y += (y0 + y1) * cross
        end
        return nil if doubled.abs < 1e-12

        [sum_x / (3.0 * doubled), sum_y / (3.0 * doubled), doubled.abs / 2.0]
      end

      # Inside the outer loop and outside every hole: inside an odd number of the Face's loops.
      def inside_face?(point, loops)
        loops.count { |loop| inside_loop?(point, loop) }.odd?
      end

      def inside_loop?((x, y), points)
        inside = false
        points.each_with_index do |(x0, y0), index|
          x1, y1 = points[(index + 1) % points.length]
          inside = !inside if (y0 > y) != (y1 > y) && x < x0 + ((y - y0) * (x1 - x0) / (y1 - y0))
        end
        inside
      end
    end
  end
end
