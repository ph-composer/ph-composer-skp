# frozen_string_literal: true

module PhComposer
  module Spaces
    # Pure: a Volume's preview prism, one prism per Floor Segment. Each segment's loops are projected onto the
    # horizontal plane at the outer loop's mean height, the projection the metrics use, and extruded up by the
    # Volume's average clear ceiling height: a base, a top and one side per edge, a hole's edges included.
    # Points are world coordinates in metres, so the Colour-by modes draw it and the export writes it from the
    # same value, and it encloses the segment's projected area less its holes times the height. A Volume with
    # no height has no prism.
    #
    # A drawn polygon has one loop, so a base with holes is cut into trapezoids between the heights of its
    # vertices, each convex; a base without holes stays one polygon.
    module Prism
      # Projected points closer than this (metres) are one point.
      COINCIDENT_M = 1e-9

      Shape = Struct.new(:base, :top, :sides, keyword_init: true) do
        def polygons
          base + top + sides
        end
      end

      module_function

      # `segments` holds each Floor Segment's world loops in metres, outer first; answers one Shape each.
      def call(segments, height_m)
        return [] if height_m.nil? || height_m <= 0

        segments.filter_map { |loops| segment(loops, height_m) }
      end

      def segment(loops, height_m)
        outer, *holes = loops
        base_z = outer.sum { |point| point[2].to_f } / outer.length
        flat = ->(loop) { distinct(loop.map { |x, y, _z| [x, y, base_z] }) }
        rings = [flat.call(outer)]
        return nil if rings.first.length < 3

        rings.concat(holes.map(&flat).select { |ring| ring.length >= 3 })

        base = rings.length == 1 ? [rings.first] : trapezoids(rings, base_z)
        Shape.new(:base => base, :top => base.map { |polygon| raised(polygon, height_m) },
                  :sides => rings.flat_map { |ring| sides(ring, height_m) })
      end

      def raised(polygon, height_m)
        polygon.map { |x, y, z| [x, y, z + height_m] }
      end

      def sides(ring, height_m)
        ring.each_index.map do |index|
          following = ring[(index + 1) % ring.length]
          [ring[index], following, raised([following], height_m).first, raised([ring[index]], height_m).first]
        end
      end

      # The region inside an odd number of rings, cut at every vertex height into trapezoids: within one band
      # the edges crossing it pair up left to right, each pair bounding one piece.
      def trapezoids(rings, base_z)
        edges = rings.flat_map { |ring| ring.each_index.map { |index| [ring[index], ring[(index + 1) % ring.length]] } }
                     .reject { |from, to| (from[1] - to[1]).abs < COINCIDENT_M }
        levels = rings.flatten(1).map { |point| point[1] }.sort
                      .each_with_object([]) { |y, kept| kept << y unless kept.last && y - kept.last < COINCIDENT_M }
        levels.each_cons(2).flat_map do |low, high|
          middle = (low + high) / 2.0
          crossing = edges.select { |from, to| [from[1], to[1]].min < middle && [from[1], to[1]].max > middle }
          crossing.map { |from, to| [x_at(from, to, low), x_at(from, to, high), x_at(from, to, middle)] }
                  .sort_by(&:last).each_slice(2).filter_map do |left, right|
            next unless right

            piece = distinct([[left[0], low, base_z], [right[0], low, base_z], [right[1], high, base_z],
                              [left[1], high, base_z]])
            piece if piece.length >= 3
          end
        end
      end

      def x_at(from, to, y_value)
        from[0] + ((to[0] - from[0]) * (y_value - from[1]) / (to[1] - from[1]))
      end

      # Drops a point that repeats the one before it in plan, as a vertical edge of a sloped loop would.
      def distinct(points)
        points.each_with_object([]) do |point, kept|
          kept << point unless kept.last && same?(kept.last, point)
        end.then { |kept| kept.length > 1 && same?(kept.first, kept.last) ? kept[0...-1] : kept }
      end

      def same?(first, second)
        (first[0] - second[0]).abs < COINCIDENT_M && (first[1] - second[1]).abs < COINCIDENT_M
      end

      # The prisms' outline as `[from, to]` pairs of world points in metres: each ring's edges at the floor and
      # at the height, and one vertical per corner. Taken from the sides, so a base cut into trapezoids around a
      # hole shows none of its cuts.
      def outline(shapes)
        shapes.flat_map(&:sides).flat_map do |floor_from, floor_to, top_to, top_from|
          [[floor_from, floor_to], [top_from, top_to], [floor_from, top_from]]
        end
      end

      # The prisms' enclosed volume in m3: each base piece's plan area times the height.
      def volume_m3(shapes, height_m)
        shapes.sum do |shape|
          shape.base.sum { |polygon| Metrics.plan_area(polygon, polygon.first) } * height_m
        end
      end
    end
  end
end
