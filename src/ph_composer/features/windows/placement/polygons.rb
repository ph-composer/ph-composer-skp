# frozen_string_literal: true

module PhComposer
  module Windows
    module Placement
      # Pure plane polygons in metres. Boundary contact is containment, while an overlap requires
      # positive area. Splitting candidate edges at host crossings handles concave hosts as well
      # as the rectangular case; corner-only tests would admit an opening across a recess.
      module Polygons
        TOLERANCE_M = FaceGeometry::QUANTUM_M

        module_function

        def contained?(candidate, boundary)
          candidate.all? { |point| inside?(point, boundary) } && edges(candidate).all? do |a, b|
            cuts = [0.0, 1.0] + edges(boundary).flat_map { |c, d| intersections(a, b, c, d) }
            cuts.sort.uniq.each_cons(2).all? do |left, right|
              inside?(interpolate(a, b, (left + right) / 2.0), boundary)
            end
          end
        end

        def overlap?(left, right)
          samples(left).any? { |point| inside?(point, right, :strict => true) } ||
            samples(right).any? { |point| inside?(point, left, :strict => true) } ||
            edges(left).any? do |a, b|
              edges(right).any? do |c, d|
                turn(a, b, c) * turn(a, b, d) < 0 && turn(c, d, a) * turn(c, d, b) < 0
              end
            end
        end

        # Whether a corner of either polygon lies on the other's boundary. Crossings are `contained?`'s question.
        def contact?(left, right)
          left.any? { |point| edges(right).any? { |a, b| on_edge?(point, a, b) } } ||
            right.any? { |point| edges(left).any? { |a, b| on_edge?(point, a, b) } }
        end

        def inside?(point, polygon, strict: false)
          return !strict if edges(polygon).any? { |a, b| on_edge?(point, a, b) }

          inside = false
          edges(polygon).each do |a, b|
            next unless (a[1] > point[1]) != (b[1] > point[1])

            crossing = (b[0] - a[0]) * (point[1] - a[1]) / (b[1] - a[1]).to_f + a[0]
            inside = !inside if point[0] < crossing
          end
          inside
        end

        def on_edge?(point, a, b)
          length = Math.hypot(b[0] - a[0], b[1] - a[1])
          turn(a, b, point).abs <= TOLERANCE_M * length &&
            2.times.all? { |axis|
              point[axis].between?([a[axis], b[axis]].min - TOLERANCE_M,
                                   [a[axis], b[axis]].max + TOLERANCE_M)
            }
        end

        def intersections(a, b, c, d)
          ab = difference(b, a)
          cd = difference(d, c)
          determinant = cross(ab, cd)
          if determinant.zero?
            return [c, d].filter_map { |point| parameter(point, a, b) if on_edge?(point, a, b) }
          end

          ac = difference(c, a)
          along = cross(ac, cd) / determinant.to_f
          across = cross(ac, ab) / determinant.to_f
          along.between?(0.0, 1.0) && across.between?(0.0, 1.0) ? [along] : []
        end

        def samples(polygon)
          center = 2.times.map { |axis| polygon.sum { |point| point[axis] } / polygon.length.to_f }
          polygon + edges(polygon).map { |a, b| interpolate(a, b, 0.5) } +
            (inside?(center, polygon, :strict => true) ? [center] : [])
        end

        def edges(polygon)
          polygon.each_with_index.map { |point, index| [point, polygon[(index + 1) % polygon.length]] }
        end

        def parameter(point, a, b)
          axis = (b[0] - a[0]).abs >= (b[1] - a[1]).abs ? 0 : 1
          delta = b[axis] - a[axis]
          delta.zero? ? 0.0 : (point[axis] - a[axis]) / delta.to_f
        end

        def interpolate(a, b, fraction)
          a.zip(b).map { |left, right| left + (right - left) * fraction }
        end

        def difference(a, b)
          a.zip(b).map { |left, right| left - right }
        end

        def cross(a, b)
          a[0] * b[1] - a[1] * b[0]
        end

        def turn(a, b, point)
          cross(difference(b, a), difference(point, a))
        end
        private_class_method :samples, :edges, :parameter, :interpolate, :difference, :cross, :turn,
                             :on_edge?, :intersections
      end
    end
  end
end
