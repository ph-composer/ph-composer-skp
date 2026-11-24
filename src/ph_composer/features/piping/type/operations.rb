# frozen_string_literal: true

module PhComposer
  module Piping
    module PipeType
      # Pipe Type persistence, one Undo step per action. Mechanical's catalog operations already do what a flat
      # catalog needs (unique names, guarded edits, a derived copy, the engine's guarded delete), so these name the
      # kind and its defaults and hand over. Piping requires Mechanical, so reading its module points down a layer.
      module Operations
        # The delete's `replacement_id` when the caller gave none.
        KEEP = Object.new.freeze

        module_function

        def create(request, proposal, values:, user_data: nil)
          Mechanical::CatalogOperations.create(request, proposal, KIND_ID, :defaults => PipeType, :values => values,
                                                                           :user_data => user_data)
        end

        def update(request, proposal, id:, values:, expected_values:)
          Mechanical::CatalogOperations.update(request, proposal, KIND_ID, :id => id, :values => values,
                                                                           :expected_values => expected_values)
        end

        def duplicate(request, proposal, id:, name: nil)
          Mechanical::CatalogOperations.duplicate(request, proposal, KIND_ID, :id => id, :name => name)
        end

        # The engine's guarded delete: a type a pipe still names refuses as reference.in_use. A `replacement_id`
        # names the type that takes its place on those pipes, and null clears them; either must be another type that
        # exists. No pipe names a type yet, so the delete has nothing to move: `reference_plan` is what a caller
        # that rewrote referring records in this proposal hands the engine.
        def delete(request, proposal, id:, expected_values: {}, replacement_id: KEEP, reference_plan: nil)
          check_replacement!(request, id, replacement_id) unless replacement_id.equal?(KEEP)
          Mechanical::CatalogOperations.delete(request, proposal, KIND_ID, :id => id,
                                                                           :expected_values => expected_values,
                                                                           :reference_plan => reference_plan)
        end

        def check_replacement!(request, id, replacement_id)
          raise CodedError.new("params.invalid", "Choose a different replacement Pipe Type.") if replacement_id == id

          request.engine.find(KIND_ID, replacement_id) if replacement_id
        end
      end
    end
  end
end
