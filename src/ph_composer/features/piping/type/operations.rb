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

        # A new type takes the next unused colour; `color` overrides how it draws, never the colour it took.
        def create(request, proposal, values:, user_data: nil)
          values = values.merge("assigned_color" => next_color(request))
          Mechanical::CatalogOperations.create(request, proposal, KIND_ID, :defaults => PipeType, :values => values,
                                                                           :user_data => user_data)
        end

        def update(request, proposal, id:, values:, expected_values:)
          Mechanical::CatalogOperations.update(request, proposal, KIND_ID, :id => id, :values => values,
                                                                           :expected_values => expected_values)
        end

        # A copy keeps any colour the original was given and takes the next unused one as its own.
        def duplicate(request, proposal, id:, name: nil)
          colour = { "assigned_color" => next_color(request) }
          derive = ->(values) { values.merge(colour) }
          Mechanical::CatalogOperations.duplicate(request, proposal, KIND_ID, :id => id, :name => name,
                                                                              :derive => derive)
        end

        def next_color(request)
          PipeType.next_color(Mechanical::CatalogOperations.records(request, KIND_ID))
        end

        # The engine's guarded delete: a type a pipe still names refuses as reference.in_use. A `replacement_id`
        # must be another type that exists, or null. `reference_plan` is what the caller that rewrote the pipes in
        # this proposal hands the engine (LineGroups::EdgeOperations.delete_type), so this module names no Edge.
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
