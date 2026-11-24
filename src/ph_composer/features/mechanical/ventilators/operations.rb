# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Ventilators
      # Ventilator persistence. Each operation takes its inputs as named arguments, so a declaration unpacks its
      # params once and any other caller uses the same operation (context/EXTENSIBILITY.md, "Organization and
      # dependencies"). The engine validates the proposal, and each action is one Undo step.
      module Operations
        module_function

        def records(request)
          request.engine.ids(VENTILATOR_KIND).map { |id| request.engine.find(VENTILATOR_KIND, id) }
        end

        # A new Ventilator: `values` over the defaults, its name unique among Ventilators.
        def create(request, proposal, values:, user_data: nil)
          values = Ventilators.defaults(values)
          Records::Names.unique!(values.fetch("name"), records(request))
          id = request.engine.propose_create(VENTILATOR_KIND, proposal, :values => values, :user_data => user_data)
          { "id" => id }
        end

        # A guarded edit: a value in `expected_values` that changed since it was read refuses the whole proposal,
        # before any check of the new values, so a stale caller always learns to read again. A taken name then
        # refuses the proposal whole, so a caller composing it cannot commit the staged write. A null removes an
        # optional value; on a required one the engine refuses it.
        def update(request, proposal, id:, values:, expected_values:)
          values = DeepCopy.call(values)
          values["name"] = values["name"].strip if values["name"]
          request.engine.propose_update(VENTILATOR_KIND, id, proposal, :values => values,
                                                                       :expected_values => expected_values)
          Records::Names.unique!(values["name"], records(request), :except => id) if values["name"]
          { "id" => id }
        rescue StandardError => error
          proposal.refuse(error)
          raise
        end

        # A copy is a new Ventilator derived from the original: a fresh id, its own name, and `user_data` copied
        # by the engine.
        def duplicate(request, proposal, id:, name: nil)
          rows = records(request)
          mapping = request.engine.propose_duplicate(VENTILATOR_KIND, [id], proposal) do |values|
            values["name"] = (name || Records::Names.copy_name(values.fetch("name"), rows)).strip
            Records::Names.unique!(values["name"], rows)
            values["source"] = { "kind" => "derived" }
            values
          end
          { "id" => mapping.fetch(id) }
        end

        # The engine's guarded delete: a Ventilator another record still names refuses as reference.in_use.
        # `reference_plan` projects the records a caller moved off it in the same proposal.
        def delete(request, proposal, id:, expected_values: {}, reference_plan: nil)
          { "id" => id }.merge(request.engine.propose_delete(VENTILATOR_KIND, id, proposal,
                                                             :expected_values => expected_values,
                                                             :reference_plan => reference_plan))
        end
      end
    end
  end
end
