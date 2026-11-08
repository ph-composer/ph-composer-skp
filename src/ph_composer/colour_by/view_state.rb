# frozen_string_literal: true

module PhComposer
  module ColourBy
    # What SketchUp's view hides or cuts that the overlay has to follow by itself, read once per rebuild:
    # View > Component Edit (Hide Rest of Model, Hide Similar Components) and the active section planes, at
    # the Model root and in each container along an occurrence's path. `key` says when a repaint is due; a
    # plane activated in a container changes no key, so that event forces a rebuild.
    class ViewState
      NONE = {}.freeze
      PLANE_TOLERANCE = 1.0e-6

      def initialize(model)
        @options = model.respond_to?(:rendering_options) ? model.rendering_options : NONE
        @active = Array(model.active_path).map(&:persistent_id)
        @open = Array(model.active_path).last
        @root_plane = section_plane(model)
      end

      def key
        cuts = [@options["DisplaySectionCuts"], @root_plane]
        @active.empty? ? cuts : cuts + [@options["InactiveHidden"], @options["InstanceHidden"], @active]
      end

      # Whether Component Edit is hiding this occurrence. `entity_at` resolves a path prefix to its entity.
      def hidden?(path, entity_at)
        return false if @active.empty?
        return true if @options["InactiveHidden"] && !around_open_context?(path)

        @options["InstanceHidden"] && similar_elsewhere?(path, entity_at)
      end

      # Whether a section plane cutting this occurrence has cut away this point.
      def cut?(point, planes)
        planes.any? { |plane| side(point, plane).positive? }
      end

      # Every active section plane cutting this occurrence, in world coordinates: the Model root's and each
      # container's along its path. `entity_at` resolves a path prefix to its entity.
      def planes(path, entity_at)
        return [] if @options["DisplaySectionCuts"] == false

        found = @root_plane ? [@root_plane] : []
        transform = Geom::Transformation.new
        Array(path).each_index do |index|
          entity = entity_at.call(path[0..index])
          break unless entity.respond_to?(:transformation)

          transform *= entity.transformation
          plane = container_plane(entity)
          found << world_plane(plane, transform) if plane
        end
        found
      end

      # Triplets of points; a triangle crossing a plane is cut to the side SketchUp keeps.
      def clip_triangles(points, planes)
        planes.reduce(points) do |kept, plane|
          kept.each_slice(3).flat_map { |triangle| fan(clip_polygon(triangle, plane)) }
        end
      end

      # Pairs of points, cut the same way.
      def clip_segments(points, planes)
        planes.reduce(points) do |kept, plane|
          kept.each_slice(2).flat_map { |first, last| clip_segment(first, last, plane) }
        end
      end

      private

      # SketchUp keeps the side of `get_plane` where a*x + b*y + c*z + d is not positive
      # (context/SKETCHUP_HOST_BEHAVIOR.md, "Overlays").
      def section_plane(model)
        return nil if @options["DisplaySectionCuts"] == false

        entities = model.respond_to?(:entities) ? model.entities : nil
        plane = entities.respond_to?(:active_section_plane) ? entities.active_section_plane : nil
        plane&.get_plane
      end

      def container_plane(entity)
        entities = entity.respond_to?(:entities) ? entity.entities : entity.definition.entities
        entities.respond_to?(:active_section_plane) ? entities.active_section_plane&.get_plane : nil
      end

      # A plane is a row of coefficients, so it maps through the inverse: this stays right under scaling.
      def world_plane(plane, transform)
        a, b, c, d = plane
        m = transform.inverse.to_a
        coefficients = [0, 4, 8, 12].map do |column|
          (a * m[column]) + (b * m[column + 1]) + (c * m[column + 2]) + (d * m[column + 3])
        end
        length = Math.sqrt(coefficients.first(3).sum { |value| value**2 })
        coefficients.map { |value| value / length }
      end

      # A coincident point counts as on the plane, so float noise cannot shred a Face in the cut's own plane.
      def side(point, plane)
        a, b, c, d = plane
        value = a * point.x + b * point.y + c * point.z + d
        value.abs < PLANE_TOLERANCE ? 0.0 : value
      end

      # Inside the open context, or an ancestor of it (a Zone holding the open Group).
      def around_open_context?(path)
        path.first(@active.length) == @active || @active.first(path.length) == path
      end

      def crossing(first, last, first_side, last_side)
        ratio = first_side / (first_side - last_side)
        Geom::Point3d.new(first.x + (last.x - first.x) * ratio, first.y + (last.y - first.y) * ratio,
                          first.z + (last.z - first.z) * ratio)
      end

      def clip_polygon(points, plane)
        points.each_with_index.flat_map do |point, index|
          following = points[(index + 1) % points.length]
          here = side(point, plane)
          there = side(following, plane)
          kept = here <= 0 ? [point] : []
          (here <= 0) != (there <= 0) ? kept + [crossing(point, following, here, there)] : kept
        end
      end

      def fan(polygon)
        (1...(polygon.length - 1)).flat_map { |index| [polygon[0], polygon[index], polygon[index + 1]] }
      end

      def clip_segment(first, last, plane)
        here = side(first, plane)
        there = side(last, plane)
        return [first, last] if here <= 0 && there <= 0
        return [] if here > 0 && there > 0

        point = crossing(first, last, here, there)
        here <= 0 ? [first, point] : [point, last]
      end

      # Another instance of the definition being edited, anywhere along the path.
      def similar_elsewhere?(path, entity_at)
        # SketchUp hands back a new wrapper on each call, so definitions are compared by id.
        definition = @open.respond_to?(:definition) ? @open.definition.persistent_id : nil
        return false unless definition

        path.each_index.any? do |index|
          prefix = path[0..index]
          entity = entity_at.call(prefix)
          next false if prefix == @active.first(prefix.length)

          entity.respond_to?(:definition) && entity.definition.persistent_id == definition
        end
      end
    end
  end
end
