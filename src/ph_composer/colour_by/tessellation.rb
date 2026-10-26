# frozen_string_literal: true

module PhComposer
  module ColourBy
    # Visibility belongs to an occurrence, not to its leaf entity: two instances may share a Face
    # while only one is hidden. Cache parent paths and entity lookup for one drawing rebuild only.
    class OccurrenceVisibility
      def initialize(model)
        @resolved = { [] => [model, true] }
        @children = {}
      end

      def visible?(path, entity)
        return true if path.nil? # Older projections provide only the leaf's visibility.
        return false unless path.is_a?(Array) && !path.empty?

        resolved, visible = resolve(path)
        resolved.equal?(entity) && visible
      end

      # Whether the occurrence a path names is drawn, for shapes or text with no entity of their own:
      # every entity along it exists and is visible. No path is no constraint.
      def path_visible?(path)
        return true if path.nil?
        return false unless path.is_a?(Array) && !path.empty?

        resolved, visible = resolve(path)
        !resolved.nil? && visible
      end

      private

      def resolve(path)
        return @resolved[path] if @resolved.key?(path)

        parent, visible = resolve(path[0...-1])
        entity = parent && children(parent)[path.last]
        @resolved[path] = [entity, visible && entity && !Tessellation.skipped?(entity)]
      end

      def children(parent)
        @children[parent] ||= begin
          entities = parent.respond_to?(:entities) ? parent.entities : Tessellation.child_entities(parent)
          Array(entities&.to_a).to_h { |entity| [entity.persistent_id, entity] }
        end
      end
    end

    # World-space triangles and outline segments for whatever entity a mode's projection hands over.
    # The service caches what this returns; nothing here reads a record, so a mode may colour any
    # entity kind without the shared service learning about it.
    #
    # A projection's transform maps that entity's own contents to world: a Face's vertices, or the
    # entities inside a Group. That is what `Zones::FaceOccurrence` and `ZoneOccurrence` already carry.
    module Tessellation
      # SketchUp coordinates are inches. The stripe planes are anchored in world space, so a Face's
      # mesh diagonals do not restart the pattern at each triangle. Large meshes widen the spacing
      # as a whole rather than drawing an arbitrarily truncated hatch.
      HATCH_SPACING = 6.0
      MAX_HATCH_SEGMENTS = 8_192
      HATCH_EPSILON = 1.0e-8
      # A derived polygon's points must lie within this many inches of its plane.
      PLANAR_TOLERANCE = 1.0e-3
      HatchTriangle = Struct.new(:vertices, :coordinates, :minimum, :maximum, keyword_init: true)

      module_function

      def call(entity, transform)
        partition(entity, transform, nil) { true }.first(2)
      end

      # Partition at each Face, not at the projected container: one Group may contain both matching
      # and muted geometry. Paths and transforms follow the particular occurrence throughout.
      # Legacy projections without a path keep nil; their full occurrence cannot be inferred here.
      def partition(entity, transform, path)
        triangles = []
        segments = []
        muted = []
        transform ||= Geom::Transformation.new
        return [triangles, segments, muted] if skipped?(entity)

        each_face(entity, transform, path) do |face, world, leaf_path|
          if yield(leaf_path)
            add_face(face, world, triangles, segments)
          else
            add_face(face, world, muted, [])
          end
        end
        [triangles, segments, muted]
      end

      # `transform` maps this entity's contents to world; a child container multiplies in its own.
      def each_face(entity, transform, path, &block)
        if entity.is_a?(Sketchup::Face)
          block.call(entity, transform, path)
        else
          child_entities(entity)&.each do |child|
            next if skipped?(child)

            child_path = path && path + [child.persistent_id]
            # Edges have no transformation and contribute no Face geometry.
            inner = child_entities(child) ? transform * child.transformation : transform
            each_face(child, inner, child_path, &block)
          end
        end
      end

      def child_entities(entity)
        if entity.is_a?(Sketchup::Group)
          entity.entities
        elsif entity.respond_to?(:definition)
          entity.definition.entities
        end
      end

      # Hidden geometry and geometry on a hidden tag are not painted; a tag shows only while it and every
      # tag folder holding it are visible. Tag visibility does not advance the session revision, so the
      # service also invalidates on `tags_changed`.
      def skipped?(entity)
        return true if entity.respond_to?(:hidden?) && entity.hidden?

        tag = entity.respond_to?(:layer) ? entity.layer : nil
        while tag
          return true if tag.respond_to?(:visible?) && !tag.visible?

          tag = tag.respond_to?(:folder) ? tag.folder : nil
        end
        false
      end

      def add_face(face, transform, triangles, segments)
        mesh = face.mesh(0)
        mesh.polygons.each do |polygon|
          polygon.each { |index| triangles << mesh.point_at(index.abs).transform(transform) }
        end
        face.loops.each do |loop|
          points = loop.vertices.map { |vertex| vertex.position.transform(transform) }
          points.each_index { |index| segments << points[index] << points[(index + 1) % points.length] }
        end
      end

      # Intersect global diagonal stripe planes with the already transformed triangles. The mesh is
      # the clipping authority: SketchUp's Face mesh excludes holes and concave exterior regions.
      # Every two returned points form one GL_LINES segment. This reads no Model or Face.
      def hatch(triangles)
        prepared = triangles.each_slice(3).filter_map do |vertices|
          next unless vertices.length == 3

          across = hatch_across(vertices)
          next unless across

          coordinates = vertices.map { |point| dot(point, across) }
          HatchTriangle.new(:vertices => vertices, :coordinates => coordinates,
                            :minimum => coordinates.min, :maximum => coordinates.max)
        end
        spacing = HATCH_SPACING
        # A stripe crosses a triangle in at most one segment. The count omits vertex-only tangencies
        # that would clip to zero length, so they cannot erase real hatch by widening the spacing.
        while prepared.sum { |triangle| stripe_count(triangle, spacing) } > MAX_HATCH_SEGMENTS
          spacing *= 2.0
        end
        hatch_at_spacing(prepared, spacing)
      end

      def stripe_range(triangle, spacing)
        first = ((triangle.minimum / spacing) - 0.5).ceil
        last = ((triangle.maximum / spacing) - 0.5).floor
        first..last
      end

      def stripe_count(triangle, spacing)
        range = stripe_range(triangle, spacing)
        count = range.end - range.begin + 1
        return 0 if count <= 0

        first_level = (range.begin + 0.5) * spacing
        last_level = (range.end + 0.5) * spacing
        count -= 1 if zero_length_extremum?(triangle, first_level, triangle.minimum)
        count -= 1 if range.end != range.begin && zero_length_extremum?(triangle, last_level, triangle.maximum)
        count
      end

      def zero_length_extremum?(triangle, level, extreme)
        return false if (level - extreme).abs > HATCH_EPSILON

        # A near-tangent can still span a real line on a long skinny triangle. Use the same edge
        # fractions as clipping, but keep only numeric coordinates here, without Point3d allocation.
        first_hit = nil
        3.times do |edge|
          following = (edge + 1) % 3
          start_distance = triangle.coordinates[edge] - level
          end_distance = triangle.coordinates[following] - level
          next if start_distance * end_distance > 0
          next if (start_distance - end_distance).abs < HATCH_EPSILON

          fraction = start_distance / (start_distance - end_distance)
          next if fraction < -HATCH_EPSILON || fraction > 1 + HATCH_EPSILON

          start_point = triangle.vertices[edge]
          end_point = triangle.vertices[following]
          hit = [start_point.x + (fraction * (end_point.x - start_point.x)),
                 start_point.y + (fraction * (end_point.y - start_point.y)),
                 start_point.z + (fraction * (end_point.z - start_point.z))]
          if first_hit
            distance = first_hit.zip(hit).sum { |start_value, end_value| (start_value - end_value)**2 }
            return false if distance >= HATCH_EPSILON**2
          else
            first_hit = hit
          end
        end
        true
      end

      def hatch_at_spacing(prepared, spacing)
        segments = []
        prepared.each do |triangle|
          vertices = triangle.vertices
          coordinates = triangle.coordinates
          stripe_range(triangle, spacing).each do |index|
            level = (index + 0.5) * spacing
            hits = []
            3.times do |edge|
              following = (edge + 1) % 3
              start_distance = coordinates[edge] - level
              end_distance = coordinates[following] - level
              next if start_distance * end_distance > 0
              next if (start_distance - end_distance).abs < HATCH_EPSILON

              fraction = start_distance / (start_distance - end_distance)
              next if fraction < -HATCH_EPSILON || fraction > 1 + HATCH_EPSILON

              start_point = vertices[edge]
              end_point = vertices[following]
              hit = Geom::Point3d.new(start_point.x + (fraction * (end_point.x - start_point.x)),
                                      start_point.y + (fraction * (end_point.y - start_point.y)),
                                      start_point.z + (fraction * (end_point.z - start_point.z)))
              hits << hit unless hits.any? { |point| squared_distance(point, hit) < HATCH_EPSILON**2 }
            end
            next unless hits.length == 2
            next if squared_distance(hits[0], hits[1]) < HATCH_EPSILON**2

            segments.concat(hits)
          end
        end
        segments
      end

      def hatch_across(vertices)
        first, second, third = vertices
        edge_a = [second.x - first.x, second.y - first.y, second.z - first.z]
        edge_b = [third.x - first.x, third.y - first.y, third.z - first.z]
        normal = [edge_a[1] * edge_b[2] - edge_a[2] * edge_b[1],
                  edge_a[2] * edge_b[0] - edge_a[0] * edge_b[2],
                  edge_a[0] * edge_b[1] - edge_a[1] * edge_b[0]]
        length = Math.sqrt(normal.sum { |component| component**2 })
        return nil if length < HATCH_EPSILON

        normal.map! { |component| component / length }
        across = projected_axis([1.0, 1.0, 1.0], normal)
        across = projected_axis([1.0, -1.0, 0.0], normal) if across.nil?
        across
      end

      def projected_axis(axis, normal)
        projection = axis.zip(normal).sum { |component, other| component * other }
        result = axis.zip(normal).map { |component, other| component - (projection * other) }
        length = Math.sqrt(result.sum { |component| component**2 })
        return nil if length < HATCH_EPSILON

        result.map { |component| component / length }
      end

      def dot(point, vector)
        (point.x * vector[0]) + (point.y * vector[1]) + (point.z * vector[2])
      end

      def squared_distance(first, second)
        ((first.x - second.x)**2) + ((first.y - second.y)**2) + ((first.z - second.z)**2)
      end

      # World triangles, outline segments and line segments for an entry's derived shapes
      # (ColourBy::Derived). A polygon that is not a planar loop of three or more distinct points draws
      # nothing; a shape that is not points at all raises, which fails the mode through the service.
      def derived(shapes)
        triangles = []
        outlines = []
        lines = []
        Array(shapes.polygons).each do |loop|
          points = points!(loop, "A derived polygon")
          polygon_triangles = triangulate(points)
          next if polygon_triangles.empty?

          triangles.concat(polygon_triangles)
          ring = distinct(points)
          ring.each_with_index { |point, index| outlines << point << ring[(index + 1) % ring.length] }
        end
        Array(shapes.segments).each do |segment|
          points = points!(segment, "A derived segment")
          raise ArgumentError, "A derived segment has two points." unless points.length == 2
          next unless points.all? { |point| finite?(point) }

          lines.concat(points)
        end
        [triangles, outlines, lines]
      end

      # Triangles covering one simple planar loop, convex or concave, by ear clipping in the loop's own
      # plane. Empty for a degenerate loop: fewer than three distinct points, a repeated or non-finite
      # point, collinear, not planar within PLANAR_TOLERANCE inches, or crossing itself.
      def triangulate(points)
        return [] unless points.all? { |point| finite?(point) }

        loop = distinct(points)
        return [] if loop.length < 3 || repeated?(loop)

        normal = newell(loop)
        length = Math.sqrt(normal.sum { |component| component**2 })
        return [] if length < HATCH_EPSILON

        normal = normal.map { |component| component / length }
        origin = loop.first
        return [] if loop.any? { |point| dot(difference(point, origin), normal).abs > PLANAR_TOLERANCE }

        ear_clip(loop, normal)
      end

      # The same points, lifted toward the camera by about `pixels` screen pixels.
      #
      # A fill drawn exactly on the Face it colours z-fights with that Face, and the host blinks
      # between the Face's own colour and the fill as the camera moves; at anything but a close
      # zoom the fill is not reliably visible at all. Measured on 26.1.188, 2026-09-20.
      #
      # The lift is toward the eye rather than along the Face normal, so it is correct whichever
      # side the Face is seen from, and it is scaled from the view, so it stays one or two pixels at
      # every zoom and never separates visibly from the Face it belongs to.
      def lift(points, view, pixels = 2.0)
        return points unless view.respond_to?(:camera) && view.respond_to?(:pixels_to_model)

        eye = view.camera.eye
        points.map do |point|
          direction = eye - point
          direction.length.to_f.zero? ? point : point.offset(direction, view.pixels_to_model(pixels, point))
        end
      end

      def points!(value, label)
        points = value.is_a?(Array) && value.all? { |point| %i[x y z].all? { |axis| point.respond_to?(axis) } }
        raise ArgumentError, "#{label} is a list of points." unless points

        value
      end

      def finite?(point)
        [point.x, point.y, point.z].all? { |value| value.is_a?(Numeric) && value.to_f.finite? }
      end

      # The loop without consecutive repeats, its closing repeat included.
      def distinct(points)
        loop = points.each_with_object([]) do |point, kept|
          kept << point if kept.empty? || squared_distance(kept.last, point) > HATCH_EPSILON**2
        end
        loop.pop if loop.length > 1 && squared_distance(loop.first, loop.last) <= HATCH_EPSILON**2
        loop
      end

      # Any point the loop passes through twice, consecutive or not, makes it degenerate.
      def repeated?(loop)
        loop.combination(2).any? { |first, second| squared_distance(first, second) <= HATCH_EPSILON**2 }
      end

      def newell(loop)
        loop.each_with_index.each_with_object([0.0, 0.0, 0.0]) do |(point, index), normal|
          following = loop[(index + 1) % loop.length]
          normal[0] += (point.y - following.y) * (point.z + following.z)
          normal[1] += (point.z - following.z) * (point.x + following.x)
          normal[2] += (point.x - following.x) * (point.y + following.y)
        end
      end

      def difference(point, origin)
        Geom::Point3d.new(point.x - origin.x, point.y - origin.y, point.z - origin.z)
      end

      # Clips ears from the loop projected onto the plane perpendicular to its dominant normal axis,
      # mirrored when that projection winds clockwise so every ear turns the same way.
      def ear_clip(loop, normal)
        axis = normal.map(&:abs).each_with_index.max.last
        flat = loop.map do |point|
          coordinates = [point.x, point.y, point.z]
          coordinates.delete_at(axis)
          coordinates
        end
        signed = flat.each_with_index.sum do |point, index|
          following = flat[(index + 1) % flat.length]
          (point[0] * following[1]) - (following[0] * point[1])
        end
        flat.map!(&:reverse) if signed.negative?
        remaining = (0...loop.length).to_a
        triangles = []
        guard = remaining.length * remaining.length
        while remaining.length > 3 && guard.positive?
          guard -= 1
          ear = remaining.each_index.find { |index| ear?(flat, remaining, index) }
          break unless ear

          previous = remaining[(ear - 1) % remaining.length]
          following = remaining[(ear + 1) % remaining.length]
          triangles << loop[previous] << loop[remaining[ear]] << loop[following]
          remaining.delete_at(ear)
        end
        # A loop that runs out of ears is not simple (it crosses itself): it draws nothing, not a part.
        return [] unless remaining.length == 3

        triangles.concat(remaining.map { |index| loop[index] })
      end

      def ear?(flat, remaining, index)
        a = flat[remaining[(index - 1) % remaining.length]]
        b = flat[remaining[index]]
        c = flat[remaining[(index + 1) % remaining.length]]
        return false if cross(a, b, c) <= HATCH_EPSILON

        remaining.none? do |other|
          point = flat[other]
          ![a, b, c].include?(point) && inside_triangle?(point, a, b, c)
        end
      end

      def cross(a, b, c)
        ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
      end

      def inside_triangle?(point, a, b, c)
        cross(a, b, point) >= 0 && cross(b, c, point) >= 0 && cross(c, a, point) >= 0
      end

      private_class_method :points!, :finite?, :distinct, :repeated?, :newell, :difference, :ear_clip, :ear?, :cross,
                           :inside_triangle?
      private_class_method :each_face, :add_face, :stripe_range, :stripe_count, :zero_length_extremum?,
                           :hatch_at_spacing, :hatch_across, :projected_axis, :dot, :squared_distance
    end
  end
end
