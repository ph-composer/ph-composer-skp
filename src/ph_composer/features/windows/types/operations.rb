# frozen_string_literal: true

module PhComposer
  module Windows
    module Types
      # Window Type persistence: record proposals and nothing else. What the placed Windows must do to
      # follow a Type is the coordinator's (Windows::Authoring), which calls these. Each operation takes
      # its inputs as arguments, so a library assignment calls the same operation its action does.
      module Operations
        module_function

        def create(request, proposal, values:, user_data: nil)
          Records::Names.unique!(values.fetch("name"), Definitions.records(request, KIND))
          values = Types.defaults(values, :identity => Records::Identity.allocator(request, "values" => values))
          id = request.engine.propose_create(TYPE_KIND, proposal, :values => values, :user_data => user_data)
          { "id" => id }
        end

        def update(request, proposal, id:, values:, expected_values:, user_data: nil)
          request.engine.find(TYPE_KIND, id)
          values = DeepCopy.call(values)
          if values["name"]
            values["name"] = values["name"].strip
            Records::Names.unique!(values["name"], Definitions.records(request, KIND), :except => id)
          end
          request.engine.propose_update(TYPE_KIND, id, proposal,
                                        :values => values,
                                        :expected_values => expected_values, :user_data => user_data)
          { "id" => id }
        end

        def duplicate(request, proposal, id:, name: nil, copy_datasheets: false)
          rows = Definitions.records(request, KIND)
          identity = Records::Identity.allocator(request, "id" => id)
          mapping = request.engine.propose_duplicate(TYPE_KIND, [id], proposal) do |values|
            values["name"] = (name || Records::Names.copy_name(values.fetch("name"), rows)).strip
            Records::Names.unique!(values["name"], rows)
            values["source"] = { "kind" => "derived" }
            values["datasheet_links"] = [] unless copy_datasheets
            values["product_photos"] = []
            values.fetch("elements").each { |element| element["id"] = identity.call("wel") }
            values
          end
          { "id" => mapping.fetch(id) }
        end

        # `retarget` moves every Window of the Type to `replacement_id` first, or removes them when
        # it is nil, through the foundation's reference retargeting.
        def delete(request, proposal, id:, expected_values: {}, retarget: false, replacement_id: nil)
          request.engine.find(TYPE_KIND, id)
          plan = nil
          if retarget
            raise CodedError.new("params.invalid", "Choose a different replacement record.") if replacement_id == id

            request.engine.find(TYPE_KIND, replacement_id) if replacement_id
            plan = request.retarget_references(TYPE_KIND, :from => id, :to => replacement_id)
          end
          request.engine.propose_delete(TYPE_KIND, id, proposal,
                                        :expected_values => expected_values, :reference_plan => plan)
          { "id" => id }
        end

        # One grid gesture on one Window Type. The block takes the stored record and an id allocator
        # and returns the edited record, as a GridOperations function does. `gesture` names it in
        # the allocator's inputs, so two gestures with equal params derive different ids.
        def grid(request, proposal, gesture:, id:, values:, expected_values:)
          before = request.engine.find(TYPE_KIND, id)
          after = yield before, Records::Identity.allocator(request, values.merge("command" => gesture, "id" => id))
          changed = KIND.values(after).select { |key, value| before[key] != value }
          request.engine.propose_update(TYPE_KIND, id, proposal, :values => changed,
                                                                 :expected_values => expected_values)
          { "id" => id }
        end
      end
    end
  end
end
