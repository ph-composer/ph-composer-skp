# frozen_string_literal: true

module PhComposer
  module Spaces
    # Pure: whether a Space is drawn off to the side of its Zone, which export allows and the report
    # names in one line. A Space is outside when any point of its Floor Segments' outer loops falls outside the
    # plan rectangle around its Zone's own Faces, by more than the tolerance. Points are world metres.
    module Extents
      TOLERANCE_M = 0.01

      module_function

      def outside?(space_points, zone_points)
        outside_bounds?(space_points, bounds(zone_points))
      end

      # The plan rectangle around `zone_points` as [min_x, max_x, min_y, max_y], or nil for no points: computed
      # once, so many Spaces can be measured against one Zone.
      def bounds(zone_points)
        return nil if zone_points.empty?

        xs = zone_points.map { |point| point[0] }
        ys = zone_points.map { |point| point[1] }
        [xs.min, xs.max, ys.min, ys.max]
      end

      def outside_bounds?(space_points, bounds)
        return false if space_points.empty? || bounds.nil?

        min_x, max_x, min_y, max_y = bounds
        space_points.any? do |x, y, _z|
          x < min_x - TOLERANCE_M || x > max_x + TOLERANCE_M || y < min_y - TOLERANCE_M || y > max_y + TOLERANCE_M
        end
      end
    end
  end
end
