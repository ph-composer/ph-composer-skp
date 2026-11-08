# frozen_string_literal: true

require_relative "../../../core/errors"
require_relative "../../../core/face_geometry"
require_relative "../../../core/vector3"
require_relative "../units/anchors"

module PhComposer
  module Windows
    module Placement
      # Detached SI basis for a captured Face. Public placement offsets have their own caller-owned origin.
      class Plane
        UP = [0.0, 0.0, 1.0].freeze
        GREEN = [0.0, 1.0, 0.0].freeze
        MappedPlan = Struct.new(:outer_polygon_m, :panes, :keyword_init => true)

        attr_reader :origin_m, :x_axis, :y_axis, :normal

        def initialize(snapshot)
          @normal = normalize(vector(snapshot.normal))
          outer = snapshot.outer_loop
          invalid!("The host Face has no usable outer plane.") unless outer.is_a?(Array) && outer.length >= 3
          points = outer.map { |point| vector(point) }
          @origin_m = points.first.freeze
          # In-plane up is world up projected onto the Face, or world green on a horizontal Face. Right is
          # up crossed with the normal, and up is then recomputed from the two so the basis is orthonormal.
          projected = subtract(UP, scale(normal, Vector3.dot(UP, normal)))
          projected = subtract(GREEN, scale(normal, Vector3.dot(GREEN, normal))) if projected.all?(&:zero?)
          @y_axis = normalize(projected).freeze
          @x_axis = normalize(cross(y_axis, normal)).freeze
          @y_axis = normalize(cross(normal, x_axis)).freeze
          points.each { |point| assert_on_plane!(point) }
          area = points.each_with_index.sum do |point, index|
            following = points[(index + 1) % points.length]
            Vector3.dot(cross(subtract(point, origin_m), subtract(following, origin_m)), normal)
          end
          invalid!("The host Face outer plane is degenerate.") unless area.finite? && !area.zero?
          freeze
        end

        # Orthogonal projection, measured from the captured outer loop's first vertex. Distance is checked separately.
        def project(point_m)
          relative = subtract(vector(point_m), origin_m)
          vector([Vector3.dot(relative, x_axis), Vector3.dot(relative, y_axis), 0]).take(2).freeze
        end

        # The world point (metres) at in-plane coordinates measured from the origin, as `project` returns them.
        def world(x_m, y_m)
          3.times.map { |axis| origin_m[axis] + (x_axis[axis] * x_m) + (y_axis[axis] * y_m) }
        end

        def signed_distance_m(point_m)
          distance = Vector3.dot(subtract(vector(point_m), origin_m), normal)
          invalid!("The point has no finite plane distance.") unless distance.finite?
          distance
        end

        def assert_on_plane!(point_m, tolerance_m: FaceGeometry::QUANTUM_M)
          unless numeric?(tolerance_m) && tolerance_m >= 0
            invalid!("The plane tolerance must be finite and nonnegative.")
          end
          if signed_distance_m(point_m).abs > tolerance_m
            invalid!("The placement point is outside the host Face plane.")
          end
          true
        end

        # The explicit world point is the requested anchor, never an inferred corner or public offset origin.
        def map(plan, point_m:, anchor: Units::Anchors::DEFAULT)
          target = vector(point_m)
          assert_on_plane!(target)
          local_anchor = Units::Anchors.point(anchor, :width_m => plan.width_m, :height_m => plan.height_m)
          polygon = lambda do |points|
            points.map do |point|
              local = subtract(vector(point), local_anchor)
              world = 3.times.map do |axis|
                target[axis] + x_axis[axis] * local[0] + y_axis[axis] * local[1] + normal[axis] * local[2]
              end
              vector(world).freeze
            end.freeze
          end
          panes = plan.panes.map do |pane|
            Units::DefinitionPlan::Pane.new(:element_id => pane.element_id.dup.freeze,
                                            :polygon_m => polygon.call(pane.polygon_m)).freeze
          end.freeze
          MappedPlan.new(:outer_polygon_m => polygon.call(plan.outer_polygon_m), :panes => panes).freeze
        end

        # The world matrix of an instance drawn as `mapped`: this plane's axes, its native origin in inches.
        def instance_matrix(mapped)
          origin = mapped.outer_polygon_m.last.map { |value| value / FaceGeometry::INCH_TO_M }
          x_axis + [0] + y_axis + [0] + normal + [0] + origin + [1]
        end

        private

        def numeric?(value)
          (value.is_a?(Integer) || value.is_a?(Float)) && value.to_f.finite?
        end

        def vector(value)
          unless value.is_a?(Array) && value.length == 3 && value.all? { |coordinate| numeric?(coordinate) }
            invalid!("Plane vectors and points must contain three finite coordinates.")
          end
          value.map(&:to_f)
        end

        def normalize(value)
          vector(Vector3.normalize(value, :message => "The host Face normal or plane axis has no direction.")).freeze
        end

        def subtract(left, right)
          vector(Vector3.subtract(left, right))
        end

        def scale(value, factor)
          vector(value.map { |coordinate| coordinate * factor })
        end

        def cross(a, b)
          vector(Vector3.cross(a, b))
        end

        def invalid!(message)
          raise CodedError.new("geometry.invalid", "#{message} Nothing was written.")
        end
      end
    end
  end
end
