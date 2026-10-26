# frozen_string_literal: true

require_relative "vector3"

module PhComposer
  # What is under the pointer, as a root-to-leaf instance path.
  #
  # A path is what an occurrence reference is built from, so a tool that picks one per pointer move
  # never walks the Model to find out where the pointer is. That distinction is the whole reason this
  # exists: a whole-Model walk costs tens to hundreds of milliseconds on a Model of a few thousand
  # Faces (the measurement is in features/zones/zone/index.rb), far too much per move.
  #
  # It names no feature; the Classify tool and Spaces' Mark floor pick Faces with it, and an edge tool picks
  # Edges.
  module Pick
    module_function

    # The topmost picked Face and every container reaching it, root first, or nil when the pointer
    # is over no Face. `PickHelper` reports the best pick first, so the first path ending in a Face
    # is the Face the user means; an Edge or a Group's own pick is skipped rather than followed.
    #
    # Nil means one thing here, and it is not "the pointer is over something this feature refuses".
    # A caller that must tell those apart asks this first and decides the second for itself.
    #
    # `path_at` answers relative to the open edit context, not from the Model root: inside a Group,
    # a Face's path is the Face alone. The active path is prepended, which is always right, because
    # inside a context SketchUp picks nothing outside it: a pick over another Group's Face while a
    # Group is open returns no hits at all. Measured on 26.1.188, 2026-09-20.
    #
    # A host with no pick helper, which is every offline view that does not supply one, picks
    # nothing.
    def face_path(view, x, y)
      first_path(view, x, y, Sketchup::Face)
    end

    # The same for an Edge: the first picked path ending in an Edge, with the active path prepended, or
    # nil when the pointer is over no Edge. A Face under the pointer is skipped, as `face_path` skips an
    # Edge, so the two never answer for each other.
    def edge_path(view, x, y)
      first_path(view, x, y, Sketchup::Edge)
    end

    # The same single native pick, plus the camera ray's intersection with that Face's world
    # plane. Unlike InputPoint, this does not perform a second pick that could choose a nearby
    # edge or another occurrence. The point remains in native inches, like every SDK Point3d.
    def face_point(view, x, y)
      path = face_path(view, x, y)
      return nil unless path && view.respond_to?(:pickray)

      transform = path[0...-1].reduce(Geom::Transformation.new) do |carried, entity|
        carried * entity.transformation
      end
      face = path.last
      origin = face.outer_loop.vertices.first.position.transform(transform)
      inverse = transform.inverse.to_a
      normal = [0, 4, 8].map do |offset|
        inverse[offset] * face.normal.x + inverse[offset + 1] * face.normal.y + inverse[offset + 2] * face.normal.z
      end
      ray_origin, direction = view.pickray(x, y)
      denominator = Vector3.dot(normal, coordinates(direction))
      return nil if denominator.abs < 1.0e-12

      distance = Vector3.dot(normal, Vector3.subtract(coordinates(origin), coordinates(ray_origin))) / denominator
      return nil if distance.negative?

      point = coordinates(ray_origin).zip(coordinates(direction)).map { |a, b| a + b * distance }
      { :path => path, :point => Geom::Point3d.new(*point) }
    end

    def coordinates(vector)
      [vector.x.to_f, vector.y.to_f, vector.z.to_f]
    end

    def first_path(view, x, y, kind)
      helper = view.respond_to?(:pick_helper) ? view.pick_helper : nil
      return nil unless helper

      count = helper.do_pick(x, y).to_i
      context = view.respond_to?(:model) ? Array(view.model.active_path) : []
      (0...count).each do |index|
        path = Array(helper.path_at(index))
        return context + path if path.last.is_a?(kind)
      end
      nil
    end
    private_class_method :coordinates, :first_path
  end
end
