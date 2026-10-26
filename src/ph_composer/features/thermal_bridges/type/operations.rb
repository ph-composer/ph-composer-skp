# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Type
      # Thermal Bridge Type persistence. Each operation takes its inputs as arguments, so a declaration
      # unpacks its params once and any other caller uses the same operation
      # (context/EXTENSIBILITY.md, "Organization and dependencies"). The engine validates the proposal.
      module Operations
        module_function

        def records(request)
          request.engine.ids(TYPE_KIND).map { |id| request.engine.find(TYPE_KIND, id) }
        end

        def create(request, proposal, values:, user_data: nil)
          Records::Names.unique!(values.fetch("name"), records(request))
          id = request.engine.propose_create(TYPE_KIND, proposal, :values => Type.defaults(values),
                                                                  :user_data => user_data)
          { "id" => id }
        end

        def update(request, proposal, id:, values:, expected_values:, user_data: nil)
          request.engine.find(TYPE_KIND, id)
          values = DeepCopy.call(values)
          if values["name"]
            values["name"] = values["name"].strip
            Records::Names.unique!(values["name"], records(request), :except => id)
          end
          request.engine.propose_update(TYPE_KIND, id, proposal, :values => values,
                                                                 :expected_values => expected_values,
                                                                 :user_data => user_data)
          { "id" => id }
        end

        # A copy is a new type derived from the original: a fresh id, its own name, and `user_data`
        # copied by the engine. Datasheet links stay behind unless asked for.
        def duplicate(request, proposal, id:, name: nil, copy_datasheets: false)
          rows = records(request)
          mapping = request.engine.propose_duplicate(TYPE_KIND, [id], proposal) do |values|
            values["name"] = (name || Records::Names.copy_name(values.fetch("name"), rows)).strip
            Records::Names.unique!(values["name"], rows)
            values["source"] = { "kind" => "derived" }
            values["datasheet_links"] = [] unless copy_datasheets
            values
          end
          { "id" => mapping.fetch(id) }
        end

        # The engine's guarded delete: a type a record still names refuses as reference.in_use. A caller that
        # rewrote those records in this proposal passes them as `reference_plan`, so the check reads them
        # as they will stand.
        def delete(request, proposal, id:, expected_values: {}, reference_plan: nil)
          request.engine.propose_delete(TYPE_KIND, id, proposal, :expected_values => expected_values,
                                                                 :reference_plan => reference_plan)
          { "id" => id }
        end
      end
    end
  end
end
