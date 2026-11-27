# frozen_string_literal: true

module PhComposer
  module Ducting
    module DuctType
      # Duct Type persistence, one Undo step per action. Mechanical's catalog operations already do what a flat
      # catalog needs (unique names, guarded edits, a derived copy, the engine's guarded delete), so these name the
      # kind and its defaults and hand over. Ducting requires Mechanical, so reading its module points down a layer.
      #
      # A type's dimensions follow its shape. The kind holds that rule for every stored record; create and update
      # check it first on the values they would write and refuse params.invalid, since a missing or other-shape
      # dimension is a wrong request, not a stored record gone bad.
      module Operations
        # The delete's `replacement_id` when the caller gave none.
        KEEP = Object.new.freeze

        module_function

        # A new type takes the next unused colour; `color` overrides how it draws, never the colour it took.
        def create(request, proposal, values:, user_data: nil)
          check_shape!(DuctType.defaults(values))
          values = values.merge("assigned_color" => next_color(request))
          Mechanical::CatalogOperations.create(request, proposal, KIND_ID, :defaults => DuctType, :values => values,
                                                                           :user_data => user_data)
        end

        # A change of shape removes the old shape's dimensions in the same write. A stale `expected_values` refuses
        # as target.changed before the shape is checked, as every guarded edit refuses before its new values are.
        def update(request, proposal, id:, values:, expected_values:)
          before = request.engine.find(KIND_ID, id)
          values = DuctType.reshaped(before, values)
          check_shape!(written(before, values)) if expected_values.all? { |key, value| before[key] == value }
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
          DuctType.next_color(Mechanical::CatalogOperations.records(request, KIND_ID))
        end

        # The engine's guarded delete: a type a duct still names refuses as reference.in_use. A `replacement_id`
        # must be another type that exists, or null. `reference_plan` is what the caller that rewrote the ducts in
        # this proposal hands the engine (LineGroups::EdgeOperations.delete_type), so this module names no Edge.
        def delete(request, proposal, id:, expected_values: {}, replacement_id: KEEP, reference_plan: nil)
          check_replacement!(request, id, replacement_id) unless replacement_id.equal?(KEEP)
          Mechanical::CatalogOperations.delete(request, proposal, KIND_ID, :id => id,
                                                                           :expected_values => expected_values,
                                                                           :reference_plan => reference_plan)
        end

        # The record's values as the edit would leave them: each given value set, each null removed.
        def written(before, values)
          before.merge(values).compact
        end

        def check_shape!(values)
          problems = DuctType.shape_problems(values)
          raise CodedError.new("params.invalid", problems.join(" ")) unless problems.empty?
        end

        def check_replacement!(request, id, replacement_id)
          raise CodedError.new("params.invalid", "Choose a different replacement Duct Type.") if replacement_id == id

          request.engine.find(KIND_ID, replacement_id) if replacement_id
        end
      end
    end
  end
end
