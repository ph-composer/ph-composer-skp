# frozen_string_literal: true

require_relative "records"
require_relative "definition_index"
require_relative "occurrences"

module PhComposer
  module Windows
    module Units
      # The owning scope verifies native aborts beyond an Entities collection: unused
      # definitions, shared materials, definition behavior and glue are Model state too.
      class MutationScope
        attr_reader :path

        def initialize(definition_ids: [])
          @definition_ids = definition_ids.map { |id| Integer(id) }.uniq.sort.freeze
          raise ArgumentError, "Definition identities must be positive." if @definition_ids.any? { |id| id <= 0 }

          @path = ["ph_composer.windows.units.mutation", *@definition_ids.map { |id| id.to_s.freeze }].freeze
        end

        def capture(model, expected_records: {})
          # Dangling pointers are readable pre-images an explicit rebuild may repair.
          # Validate storage shape here; operation preparation owns semantic resolution.
          DefinitionIndex.read(model)
          definitions = model.definitions.to_a
          ids = definitions.map(&:persistent_id)
          unless ids.uniq.length == ids.length && ids.all? { |id| id.is_a?(Integer) && id.positive? }
            raise CodedError.new("record.unreadable", "The definition catalog has invalid identities.")
          end

          value = { "index" => model.get_attribute(DefinitionIndex::STORE.dictionary, DefinitionIndex::STORE.key),
                    "definition_ids" => ids.sort, "definitions" => selected_definitions(definitions),
                    "materials" => model.materials.map { |material|
                                     material_values(material)
                                   }.sort_by { |row| row["name"] },
                    "units" => unit_values(model, expected_records) }
          unless JsonValue.problems(value).empty?
            raise CodedError.new("record.unreadable", "Window mutation state is not detached JSON.")
          end

          CanonicalJson.digest(value)
        rescue CodedError
          raise
        rescue StandardError
          raise CodedError.new("record.unreadable", "Window mutation state could not be captured."), :cause => nil
        end

        def unchanged?(model, before)
          capture(model) == before
        rescue StandardError
          false
        end

        # The same detached native preimage is usable by a step's drift guard without including
        # preceding identity repairs on unrelated instances.
        def definition_snapshot(definition)
          id = definition.persistent_id
          check_stamp!(DEFINITION_STORE, definition, %w[window_type_id])
          { "id" => id, "name" => definition.name, "dictionaries" => dictionaries(definition),
            "behavior" => behavior_values(definition.behavior),
            "entities" => entity_values(definition.entities, [id]) }
        end

        private

        def selected_definitions(definitions)
          @definition_ids.map do |id|
            definition = definitions.find { |item| item.persistent_id == id }
            raise CodedError.new("target.not_found", "A scoped Window definition no longer exists.") unless definition

            definition_snapshot(definition)
          end
        end

        def behavior_values(behavior)
          { "is2d" => behavior.is2d?, "cuts_opening" => behavior.cuts_opening?,
            "snapto" => behavior.snapto, "no_scale_mask" => behavior.no_scale_mask? }
        end

        def dictionaries(entity)
          collection = entity.attribute_dictionaries
          return {} unless collection

          collection.to_a.select { |dictionary| dictionary.name.start_with?("ph_composer.") }.to_h do |dictionary|
            values = {}
            dictionary.each { |key, value| values[key.to_s] = DeepCopy.call(value) }
            [dictionary.name, values]
          end
        end

        def entity_values(entities, ancestors)
          entities.map do |entity|
            row = { "id" => entity.persistent_id, "kind" => entity.class.name,
                    "dictionaries" => dictionaries(entity) }
            if entity.is_a?(Sketchup::Face)
              check_stamp!(PANE_STORE, entity, %w[window_type_id element_id])
              row.merge!("loops" => entity.loops.map { |loop| loop.vertices.map { |vertex| point(vertex.position) } },
                         "normal" => point(entity.normal), "material" => material_name(entity.material),
                         "back_material" => material_name(entity.back_material))
            elsif entity.is_a?(Sketchup::Edge)
              row["vertices"] = [point(entity.start.position), point(entity.end.position)]
            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
              capture_container(row, entity, ancestors)
            else
              raise CodedError.new("record.unreadable", "A Window definition contains unsupported geometry.")
            end
            row
          end.sort_by { |row| row.fetch("id") }
        end

        def capture_container(row, entity, ancestors)
          definition = entity.definition
          id = definition.persistent_id
          raise CodedError.new("record.unreadable", "Window definition storage is recursive.") if ancestors.include?(id)

          row.merge!("name" => entity.name, "transformation" => entity.transformation.to_a,
                     "definition_id" => id, "entities" => entity_values(definition.entities, ancestors + [id]))
        end

        def material_name(material)
          material && material.name
        end

        def check_stamp!(store, entity, keys)
          record = store.read(entity)
          return if record.nil? && entity.get_attribute(store.dictionary, store.key).nil?
          return if record.is_a?(Hash) && keys.all? { |key| record[key].is_a?(String) && !record[key].empty? }

          raise CodedError.new("record.unreadable", "A Window geometry stamp is invalid.")
        end

        def material_values(material)
          { "name" => material.name, "color" => material.color.to_a, "alpha" => material.alpha,
            "dictionaries" => dictionaries(material) }
        end

        def unit_values(model, expected_records)
          occurrences = Occurrences.all(model)
          unless expected_records.is_a?(Hash) && (expected_records.keys - occurrences.map(&:path)).empty?
            raise CodedError.new("target.not_found", "A projected Window occurrence does not exist.")
          end

          occurrences.map do |occurrence|
            entity = occurrence.entity
            record = expected_records.fetch(occurrence.path, occurrence.record)
            Units.validate!(record)
            attrs = dictionaries(entity)
            if expected_records.key?(occurrence.path)
              attrs.fetch(STORE.dictionary)[STORE.key] = CanonicalJson.generate(record)
            end
            { "path" => occurrence.path, "record" => DeepCopy.call(record), "dictionaries" => attrs,
              "name" => entity.name, "transformation" => entity.transformation.to_a,
              "world_transform" => occurrence.transform.to_a,
              "definition_id" => entity.definition.persistent_id, "glued_face_id" => entity.glued_to&.persistent_id }
          end.sort_by { |row| row.fetch("path") }
        end

        def point(value)
          [value.x.to_f, value.y.to_f, value.z.to_f]
        end
      end
    end
  end
end
