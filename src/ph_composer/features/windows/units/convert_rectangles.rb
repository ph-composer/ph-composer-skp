# frozen_string_literal: true

require_relative "../../../core/face_geometry"
require_relative "../../../core/vector3"
require_relative "definition_geometry"

module PhComposer
  module Windows
    module Units
      # Convert to Window Type's reading of hand-drawn rectangles, over detached values only: which Faces
      # are rectangles, which share an Edge, and the bands and spans a tiling group becomes. Sizes are the
      # frame outer size (W7-4). "Right" and "up" are the host Face's axes (Placement::Plane); columns run
      # left to right as seen from outside and rows top down, as a Window Type's bands do.
      module ConvertRectangles
        # The right-angle tolerance the design names, used for parallelism to the host's axes as well.
        ANGLE_TOLERANCE_DEGREES = 0.1
        MAXIMUM_COSINE = Math.sin(ANGLE_TOLERANCE_DEGREES * Math::PI / 180.0)
        MINIMUM_COSINE = Math.cos(ANGLE_TOLERANCE_DEGREES * Math::PI / 180.0)
        # SketchUp's own vertex tolerance, 0.001 in: Faces drawn on one plane agree only to this, as the
        # Zones adjacency solver also takes it.
        COORDINATE_TOLERANCE_M = 0.0000254
        DIGITS = 6

        # One rectangle in the host's plane, in metres.
        Extent = Struct.new(:left, :right, :bottom, :top, :keyword_init => true)
        # `spans` holds one [row_span, column_span] per rectangle, in the order the extents were given.
        Layout = Struct.new(:columns_m, :rows_m, :spans, :keyword_init => true)

        module_function

        # The four corners of an outer loop once collinear vertices are merged (a side split by a T junction
        # is still one side), or nil when it is not a rectangle.
        def corners(points)
          contour = DefinitionGeometry.normalized_contour(points)
          return nil unless contour.length == 4

          sides = directions(contour)
          right_angles = sides.each_index.all? do |index|
            Vector3.dot(sides[index], sides[(index + 1) % 4]).abs <= MAXIMUM_COSINE
          end
          right_angles ? contour : nil
        end

        # Whether every side runs along the host's right or up axis.
        def aligned?(contour, plane)
          directions(contour).all? do |side|
            [plane.x_axis, plane.y_axis].any? { |axis| Vector3.dot(side, axis).abs >= MINIMUM_COSINE }
          end
        end

        def extent(contour, plane)
          xs, ys = contour.map { |point| plane.project(point) }.transpose
          Extent.new(:left => xs.min, :right => xs.max, :bottom => ys.min, :top => ys.max)
        end

        # Index groups of the rectangles joined, directly or through others, by a shared Edge key. `joined`
        # says whether two rectangles sharing an Edge may join, so a corner's two walls stay apart.
        def clusters(edge_keys, &joined)
          owners = Hash.new { |hash, key| hash[key] = [] }
          edge_keys.each_with_index { |keys, index| keys.each { |key| owners[key] << index } }
          seen = {}
          edge_keys.each_index.filter_map do |start|
            next if seen[start]

            seen[start] = true
            members = [start]
            members.each do |index|
              edge_keys[index].flat_map { |key| owners[key] }.uniq.each do |other|
                next if seen[other] || !joined.call(index, other)

                seen[other] = true
                members << other
              end
            end
            members.sort
          end
        end

        # The bands and spans of rectangles that tile one rectangle exactly, each grid cell covered once;
        # nil for a gap, an overlap or an L.
        def layout(extents)
          lefts = coordinates(extents.flat_map { |extent| [extent.left, extent.right] })
          tops = coordinates(extents.flat_map { |extent| [extent.bottom, extent.top] }).reverse
          spans = extents.map do |extent|
            [[position(tops, extent.top), position(tops, extent.bottom) - 1],
             [position(lefts, extent.left), position(lefts, extent.right) - 1]]
          end
          coverage = {}
          overlaps = spans.flat_map { |rows, columns| Types.cover(coverage, rows, columns) }
          return nil unless overlaps.empty? && coverage.length == (tops.length - 1) * (lefts.length - 1)

          Layout.new(:columns_m => bands(lefts), :rows_m => bands(tops), :spans => spans)
        end

        # Whether two layouts have the same grid and spans, each band within `tolerance_m`. An incomplete
        # Type's missing band matches nothing.
        def same_layout?(left, right, tolerance_m)
          same_bands?(left.columns_m, right.columns_m, tolerance_m) &&
            same_bands?(left.rows_m, right.rows_m, tolerance_m) && left.spans.sort == right.spans.sort
        end

        def same_bands?(left, right, tolerance_m)
          left.length == right.length && left.zip(right).all? do |a, b|
            !a.nil? && !b.nil? && (a - b).abs <= tolerance_m
          end
        end

        def directions(contour)
          contour.each_with_index.map do |point, index|
            Vector3.normalize(Vector3.subtract(contour[(index + 1) % 4], point))
          end
        end

        def coordinates(values)
          values.sort.each_with_object([]) do |value, distinct|
            distinct << value unless distinct.last && value - distinct.last <= COORDINATE_TOLERANCE_M
          end
        end

        def position(distinct, value)
          distinct.index { |coordinate| (coordinate - value).abs <= COORDINATE_TOLERANCE_M }
        end

        def bands(distinct)
          distinct.each_cons(2).map { |a, b| (b - a).abs.round(DIGITS) }
        end
        private_class_method :same_bands?, :directions, :coordinates, :position, :bands
      end
    end
  end
end
