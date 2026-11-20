# frozen_string_literal: true

module PhComposer
  module Shading
    # `shading.list`: one walk of the Model for every marked entity and every shading component, the Shading
    # Faces grouped by the name they export under, with their count and world area. Cutting components are not
    # walked, as export does not read their Faces. Reads only.
    module Inventory
      module_function

      def list(request)
        marked = []
        components = Hash.new do |hash, name|
          hash[name] = { "display_name" => name, "face_count" => 0, "area_m2" => 0.0 }
        end
        zones = Targets.zone_names(request.model)
        walk(request.model.entities, [], [], Geom::Transformation.new, zones) do |entity, path, containers, transform|
          marked << { "entity_path" => path, "kind" => Mark.kind(entity), "readable" => Mark.readable?(entity) } if
            Mark.marked?(entity)
          next unless entity.is_a?(Sketchup::Face) &&
                      Reads.shading_face?(:marked => Mark.marked?(entity), :owned => Targets.owned?(entity),
                                          :containers => containers)

          component = components[Reads.component_name(containers)]
          component["face_count"] += 1
          component["area_m2"] += FaceCapture.call(entity, transform).area_m2
        end
        { "marked" => marked.sort_by { |row| row.fetch("entity_path") },
          "components" => components.values.sort_by { |row| row.fetch("display_name") },
          "units" => { "area_m2" => "m2" } }
      end

      # Yields each Face, Group and component with its root path, the Reads::Container rows above it and the
      # transform from its collection to world, once per placement. `zones` maps Zone paths to names.
      def walk(entities, path, containers, transform, zones, &block)
        entities.each do |entity|
          next unless Mark.kind(entity)

          current = path + [entity.persistent_id]
          yield entity, current, containers, transform
          next if entity.is_a?(Sketchup::Face) || Targets.cutting?(entity)

          walk(Targets.contents(entity), current, containers + [Targets.container(entity, current, zones)],
               transform * entity.transformation, zones, &block)
        end
      end
    end
  end
end
