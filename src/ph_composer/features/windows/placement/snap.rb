# frozen_string_literal: true

require_relative "plane"
require_relative "fit"
require_relative "../units/world_geometry"

module PhComposer
  module Windows
    module Placement
      # Where a Window that has left its Face comes back to, from detached geometry alone. It moves as
      # little as possible: a Window already lying clear on a Face stays exactly where it is; otherwise its
      # outline is squared to the Face and brought just inside the Face's extent, or to the nearest spot
      # clear of whichever Windows are in the way there, beside them or above and below.
      module Snap
        ANCHOR = "center"

        module_function

        # The world matrix for `plan` on `geometry`, or nil when it cannot sit there clear of `others_m`.
        def on_face(geometry, plan, matrix, others_m)
          return matrix if fits?(geometry, Units::WorldGeometry.map(plan, matrix).outer_polygon_m, others_m)

          plane = Plane.new(geometry)
          boundary = geometry.outer_loop.map { |point| plane.project(point) }
          x, y = plane.project(centre_m(plan, matrix))
          extents = [boundary.map(&:first), boundary.map(&:last)]
          sizes = [plan.width_m, plan.height_m]
          start = [inside(x, extents[0], sizes[0]), inside(y, extents[1], sizes[1])]
          return unless start.all?

          landings(plane, others_m, start, extents, sizes).each do |spot|
            mapped = plane.map(plan, :point_m => plane.world(*spot), :anchor => ANCHOR)
            return plane.instance_matrix(mapped) if fits?(geometry, mapped.outer_polygon_m, others_m)
          end
          nil
        end

        # The centre of the outline `matrix` draws, in world metres.
        def centre_m(plan, matrix)
          Units::WorldGeometry.anchor(plan, ANCHOR, matrix)
        end

        # `value` moved the least that keeps a band of `size` centred on it within the extent of `coordinates`;
        # nil when the extent is narrower than the band. Clear of the edge by the geometry's own quantum, since
        # a flush edge is at the mercy of rounding.
        def inside(value, coordinates, size)
          half = size / 2.0 + FaceGeometry::QUANTUM_M
          low = coordinates.min + half
          high = coordinates.max - half
          low <= high ? value.clamp(low, high) : nil
        end

        # `start`, then every spot just clear of a Window on this plane along either axis, nearest first.
        def landings(plane, others_m, start, extents, sizes)
          on_plane = others_m.select do |polygon|
            polygon.all? { |point| plane.signed_distance_m(point).abs <= FaceGeometry::QUANTUM_M }
          end.map { |polygon| polygon.map { |point| plane.project(point) } }
          across = [0, 1].map do |axis|
            clearance = sizes[axis] / 2.0 + FaceGeometry::QUANTUM_M
            spots = on_plane.flat_map do |polygon|
              values = polygon.map { |point| point[axis] }
              [values.min - clearance, values.max + clearance]
            end
            ([start[axis]] + spots.filter_map { |spot| inside(spot, extents[axis], sizes[axis]) }).uniq
          end
          across[0].product(across[1]).sort_by { |spot| spot.zip(start).sum { |value, from| (value - from)**2 } }
        end

        def fits?(geometry, polygon_m, others_m)
          Fit.check!(geometry, polygon_m, :existing_polygons_m => others_m)
        rescue CodedError
          false
        end
        private_class_method :inside, :landings, :fits?
      end
    end
  end
end
