# frozen_string_literal: true

module PhComposer
  module ColourBy
    # What SketchUp's view hides or cuts that the overlay has to follow by itself, read once per rebuild:
    # View > Component Edit (Hide Rest of Model, Hide Similar Components) and the active section plane at the
    # Model root. A Group's own active section plane is not followed. `key` says when a repaint is due.
    class ViewState
      NONE = {}.freeze
      PLANE_TOLERANCE = 1.0e-6

      def initialize(model)
        @options = model.respond_to?(:rendering_options) ? model.rendering_options : NONE
        @active = Array(model.active_path).map(&:persistent_id)
        @open = Array(model.active_path).last
        @plane = section_plane(model)
      end

      def key
        @active.empty? ? [@plane] : [@options["InactiveHidden"], @options["InstanceHidden"], @active, @plane]
      end

      # Whether Component Edit is hiding this occurrence. `entity_at` resolves a path prefix to its entity.
      def hidden?(path, entity_at)
        return false if @active.empty?
        return true if @options["InactiveHidden"] && !around_open_context?(path)

        @options["InstanceHidden"] && similar_elsewhere?(path, entity_at)
      end

      # Whether the section plane has cut away this point.
      def cut?(point)
        !@plane.nil? && side(point).positive?
      end

      # Triplets of points; a triangle crossing the plane is cut to the side SketchUp keeps.
      def clip_triangles(points)
        return points unless @plane

        points.each_slice(3).flat_map { |triangle| fan(clip_polygon(triangle)) }
      end

      # Pairs of points, cut the same way.
      def clip_segments(points)
        return points unless @plane

        points.each_slice(2).flat_map { |first, last| clip_segment(first, last) }
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

      # A coincident point counts as on the plane, so float noise cannot shred a Face in the cut's own plane.
      def side(point)
        a, b, c, d = @plane
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

      def clip_polygon(points)
        points.each_with_index.flat_map do |point, index|
          following = points[(index + 1) % points.length]
          here = side(point)
          there = side(following)
          kept = here <= 0 ? [point] : []
          (here <= 0) != (there <= 0) ? kept + [crossing(point, following, here, there)] : kept
        end
      end

      def fan(polygon)
        (1...(polygon.length - 1)).flat_map { |index| [polygon[0], polygon[index], polygon[index + 1]] }
      end

      def clip_segment(first, last)
        here = side(first)
        there = side(last)
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
