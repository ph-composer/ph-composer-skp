# frozen_string_literal: true

module PhComposer
  module Shading
    # `shading.list`: every marked entity and every shading component, the Shading Faces grouped by the name they
    # export under, with their count and world area. A mark inside a cutting component is listed, so clear can
    # find it, but those Faces count in no component, as export does not read them. Two walks: Zones' walk of
    # its occurrences, which says which Groups are Zones without Shading reading Zones' records, then one walk
    # of the Model. A Face whose transform is singular refuses the read as geometry.invalid. Reads only.
    # `shading_faces` is the same two walks for a reader that needs only the Shading Face occurrences, such as
    # the Colour-by mode; `shading_face?` is the one rule both apply.
    module Inventory
      module_function

      def list(request)
        marked = []
        components = Hash.new do |hash, name|
          hash[name] = { "display_name" => name, "face_count" => 0, "area_m2" => 0.0 }
        end
        zones = Targets.zone_names(request.model)
        walk(request.model.entities, [], [], Geom::Transformation.new,
             zones) do |entity, path, containers, transform, cut|
          marked << { "entity_path" => path, "kind" => Mark.kind(entity), "readable" => Mark.readable?(entity) } if
            Mark.marked?(entity)
          next unless shading_face?(entity, containers, cut)

          component = components[Reads.component_name(containers)]
          component["face_count"] += 1
          component["area_m2"] += FaceCapture.call(entity, transform).area_m2
        end
        { "marked" => marked.sort_by { |row| row.fetch("entity_path") },
          "components" => components.values.sort_by { |row| row.fetch("display_name") },
          "units" => { "area_m2" => "m2" } }
      end

      # Yields each Shading Face occurrence, once per placement: the Face, its root path, the transform from its
      # collection to world and the component name it exports under.
      def shading_faces(model)
        zones = Targets.zone_names(model)
        walk(model.entities, [], [], Geom::Transformation.new, zones) do |entity, path, containers, transform, cut|
          yield entity, path, transform, Reads.component_name(containers) if shading_face?(entity, containers, cut)
        end
      end

      # Whether `entity`, reached under `containers`, is a Shading Face that export reads: not inside a cutting
      # component, marked or inheriting a mark, and not a classified Zone Face shading only through a container,
      # which stays envelope.
      def shading_face?(entity, containers, cut)
        return false unless entity.is_a?(Sketchup::Face) && !cut

        marked = Mark.marked?(entity)
        return false unless Reads.shading_face?(:marked => marked, :owned => Targets.owned?(entity),
                                                :containers => containers)

        marked || !(containers.any?(&:zone?) && Zones::Occurrences.classified_face?(entity))
      end

      # Yields each Face, Group and component with its root path, the Reads::Container rows above it, the
      # transform from its collection to world and whether a cutting component holds it, once per placement.
      # `zones` maps Zone paths to names.
      def walk(entities, path, containers, transform, zones, cut = false, &block)
        entities.each do |entity|
          next unless Mark.kind(entity)

          current = path + [entity.persistent_id]
          yield entity, current, containers, transform, cut
          next if entity.is_a?(Sketchup::Face)

          walk(Targets.contents(entity), current, containers + [Targets.container(entity, current, zones)],
               transform * entity.transformation, zones, cut || Targets.cutting?(entity), &block)
        end
      end
    end
  end
end
