# frozen_string_literal: true

require_relative "../../../core/face_capture"
require_relative "../../../core/operations/entity_scope"
require_relative "convert_rectangles"

module PhComposer
  module Windows
    module Units
      # Reads root-to-Face paths into detached rectangles for Convert to Window Type. Sources are named by
      # path because a rectangle outside every Zone has no Zone Face reference. Storage must be a chain of
      # unique, unlocked Groups: a Component's Faces belong to every instance, so Convert could not erase
      # one occurrence's rectangle.
      module ConvertSources
        Source = Struct.new(:path, :parent_path, :face, :transform, :geometry, :corners, :edge_keys,
                            :keyword_init => true)

        module_function

        # [sources, left-out rows] for the paths, which the caller gives once each.
        def read(model, paths)
          left_out = []
          sources = paths.filter_map do |path|
            source(model, path)
          rescue CodedError => error
            left_out << ConvertReview.left_out([path], error)
            nil
          end
          [sources, left_out]
        end

        def source(model, path)
          parent_path = path[0...-1]
          scope = PhComposer::Operations::EntityScope.new(parent_path)
          entities = scope.resolve(model)
          face = leaf(entities, path.last)
          transform = storage_transform(model, scope)
          geometry = FaceCapture.call(face, transform)
          corners = geometry.holes.empty? ? ConvertRectangles.corners(geometry.outer_loop) : nil
          unless corners
            raise CodedError.new("window.not_rectangle", "The Face is not a rectangle: it needs four square corners " \
                                                         "and no hole.")
          end

          Source.new(:path => path, :parent_path => parent_path, :face => face, :transform => transform,
                     :geometry => geometry, :corners => corners,
                     :edge_keys => face.edges.map { |edge| [parent_path, edge.persistent_id] })
        end

        def leaf(entities, persistent_id)
          found = entities.to_a.select { |entity| entity.persistent_id == persistent_id }
          raise CodedError.new("target.not_found", "That Face no longer exists.") unless found.length == 1
          return found.first if found.first.is_a?(Sketchup::Face)

          raise CodedError.new("target.wrong_kind", "That entity is not a Face.")
        end

        def storage_transform(model, scope)
          collection = model.entities
          scope.path.reduce(Geom::Transformation.new) do |transform, id|
            group = scope.find(collection, id)
            raise CodedError.new("target.locked", "The Group holding that Face is locked.") if group.locked?
            if group.definition.instances.length > 1
              raise CodedError.new("target.shared_definition", "The Group holding that Face is shared with a copy.")
            end

            collection = group.entities
            transform * group.transformation
          end
        end
        private_class_method :source, :leaf, :storage_transform
      end
    end
  end
end
