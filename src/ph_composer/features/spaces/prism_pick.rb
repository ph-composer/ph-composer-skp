# frozen_string_literal: true

module PhComposer
  module Spaces
    # Pure: what a pointer ray means for a Volume's prism, in world metres. A prism is drawn, not modelled, so the
    # host's pick cannot find it; Set Height asks here instead.
    module PrismPick
      # Below this (the squared sine of the angle between the ray and the vertical, about 6 degrees) a ray looks
      # too nearly along a vertical line for a pointer move to mean a sensible height along it.
      VERTICAL_RAY = 0.01
      FLAT = 1.0e-12

      module_function

      # The ray distance to every face of `shapes` in front of `origin`, nearest first, so a caller can pass over
      # a face a section plane has cut away.
      def distances(shapes, origin, direction)
        shapes.flat_map(&:polygons).filter_map { |polygon| along(polygon, origin, direction) }.sort
      end

      # Each axis's [low, high] over `shapes`, or nil for no shape: what `crosses?` tests first, so a pointer move
      # does a polygon test only on the prisms its ray can reach.
      def bounds(shapes)
        corners = shapes.flat_map(&:polygons).flatten(1)
        (0..2).map { |axis| corners.map { |corner| corner[axis] }.minmax } unless corners.empty?
      end

      # Whether the ray passes through `bounds`, by the slab test.
      def crosses?(bounds, origin, direction)
        near = 0.0
        far = Float::INFINITY
        bounds.each_with_index do |(low, high), axis|
          if direction[axis].abs < FLAT
            return false unless origin[axis].between?(low, high)

            next
          end
          enter, leave = [(low - origin[axis]) / direction[axis], (high - origin[axis]) / direction[axis]].minmax
          near = [near, enter].max
          far = [far, leave].min
          return false if near > far
        end
        true
      end

      # How far up the vertical line through `anchor` the point nearest the ray lies: Push/Pull's mapping of a
      # pointer to a height, from any camera. Nil when the ray runs along the line or the nearest point is behind
      # the eye.
      def rise(anchor, origin, direction)
        offset = Vector3.subtract(anchor, origin)
        lift = direction[2]
        square = Vector3.dot(direction, direction)
        along_ray = Vector3.dot(direction, offset)
        denominator = square - (lift * lift)
        return nil if denominator < VERTICAL_RAY

        return nil unless (along_ray - (offset[2] * lift)) / denominator > 0

        ((lift * along_ray) - (square * offset[2])) / denominator
      end

      def along(polygon, origin, direction)
        normal = normal_of(polygon)
        denominator = Vector3.dot(normal, direction)
        return nil if denominator.abs < FLAT

        distance = Vector3.dot(normal, Vector3.subtract(polygon.first, origin)) / denominator
        return nil unless distance.positive?

        point = origin.zip(direction).map { |start, step| start + (step * distance) }
        inside?(polygon, point, normal) ? distance : nil
      end

      # Newell's normal, unscaled: a polygon that has collapsed answers zero, and is never hit.
      def normal_of(polygon)
        polygon.each_with_index.reduce([0.0, 0.0, 0.0]) do |sum, (point, index)|
          following = polygon[(index + 1) % polygon.length]
          [sum[0] + ((point[1] - following[1]) * (point[2] + following[2])),
           sum[1] + ((point[2] - following[2]) * (point[0] + following[0])),
           sum[2] + ((point[0] - following[0]) * (point[1] + following[1]))]
        end
      end

      # The crossing test, in the plane that drops the normal's largest component.
      def inside?(polygon, point, normal)
        dropped = normal.each_index.max_by { |axis| normal[axis].abs }
        u_axis, v_axis = [0, 1, 2] - [dropped]
        polygon.each_with_index.count do |corner, index|
          following = polygon[(index + 1) % polygon.length]
          next false unless (corner[v_axis] > point[v_axis]) != (following[v_axis] > point[v_axis])

          fraction = (point[v_axis] - corner[v_axis]) / (following[v_axis] - corner[v_axis])
          point[u_axis] < corner[u_axis] + (fraction * (following[u_axis] - corner[u_axis]))
        end.odd?
      end
    end
  end
end
