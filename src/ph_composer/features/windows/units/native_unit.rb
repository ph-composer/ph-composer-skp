# frozen_string_literal: true

require_relative "records"
require_relative "occurrences"
require_relative "definition_geometry"
require_relative "definition_writer"

module PhComposer
  module Windows
    module Units
      # The native guards and the one native write every Unit step shares. Each function either
      # returns or refuses with a coded error before anything is written; a step keeps only the
      # checks that belong to its own repair.
      module NativeUnit
        module_function

        # The one occurrence at `reference`'s entity path, at plan time. Its live record must carry the
        # reference's Unit id, or, when `expected_record` is given, that record's id: a copied identity
        # the same proposal repairs first. The occurrence must also be writable.
        def resolve!(occurrences, reference, expected_record: nil)
          found = occurrences.select { |item| item.path == reference.fetch("entity_path") }
          ids = [found.first&.record&.fetch("id"), expected_record&.fetch("id")].compact
          unless found.length == 1 && ids.include?(reference.fetch("unit_id"))
            changed!("A Window occurrence no longer resolves uniquely.")
          end
          Occurrences.mutable!(found.first)
          found.first
        end

        # The one occurrence at `path`, at apply, whose live record is still exactly `record`.
        def unchanged!(occurrences, path, record)
          found = occurrences.select { |item| item.path == path }
          changed!("A Window record changed after preview.") unless found.length == 1 && found.first.record == record
          Occurrences.mutable!(found.first)
          found.first
        end

        # The native state a step compares at apply to prove nobody moved, re-glued or edited the Unit.
        def preimage(item)
          entity = item.entity
          { "matrix" => entity.transformation.to_a, "world_matrix" => item.transform.to_a,
            "definition_id" => entity.definition.persistent_id,
            "definition_before" => DefinitionGeometry.capture(entity.definition),
            "glued_face_id" => entity.glued_to&.persistent_id }
        end

        # Whether the user has `definition_id` open for editing, where a definition write would land
        # inside the edit the user is making.
        def editing?(model, definition_id)
          return false unless definition_id

          Array(model.active_path).any? { |entity| entity.definition.persistent_id == definition_id }
        end

        # Point the instance at `definition` with local `matrix`, keeping its glue: the glued Face is read
        # first and set again last, and each of the three values is read back.
        def replace_definition!(entity, definition, matrix)
          glue = entity.glued_to
          entity.definition = definition
          entity.transformation = Geom::Transformation.new(matrix)
          entity.glued_to = glue
          return if entity.definition == definition && entity.transformation.to_a == matrix && entity.glued_to == glue

          raise CodedError.new("geometry.failed",
                               "The Window definition, transform or glue could not be preserved.")
        end

        # A primary definition must still match its Type's generated geometry and behaviour before a Unit
        # is placed from it.
        def check_primary!(definition, type_id:, plan:)
          return if DefinitionWriter.configured?(definition.behavior) &&
                    DefinitionGeometry.matches?(definition, :type_id => type_id, :plan => plan)

          raise CodedError.new("window.definition_changed",
                               "The canonical Window definition geometry or behavior differs from its Type. " \
                               "Nothing was written.")
        end

        # One new instance of `definition` in `entities`, glued to `face` and carrying `record`.
        def add_glued!(entities, definition, local_transform, face, record)
          instance = entities.add_instance(definition, local_transform)
          raise CodedError.new("geometry.failed", "The native Window instance could not be created.") unless instance

          instance.glued_to = face
          unless instance.glued_to == face
            raise CodedError.new("geometry.failed", "The native Window instance could not glue to its host Face.")
          end

          Units.write(instance, record)
          instance
        end

        def changed!(message)
          raise CodedError.new("target.changed", "#{message} Nothing was written.")
        end
      end
    end
  end
end
