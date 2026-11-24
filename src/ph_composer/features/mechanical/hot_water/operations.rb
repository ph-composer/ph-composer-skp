# frozen_string_literal: true

module PhComposer
  module Mechanical
    module HotWater
      # Every hot water kind's catalog kind, by id, with the module that gives a new record its defaults.
      KINDS = { Systems::KIND_ID => Systems, Heaters::KIND_ID => Heaters, Tanks::KIND_ID => Tanks }.freeze
      # The kinds that name a System.
      MEMBER_KINDS = [Heaters::KIND_ID, Tanks::KIND_ID].freeze

      # Persistence for the three hot water kinds. Each operation takes the kind and its inputs as named arguments,
      # so a declaration unpacks its params once and any other caller uses the same operation (context/
      # EXTENSIBILITY.md, "Organization and dependencies"). The engine validates the proposal, and each action is one
      # Undo step. Names are unique within a kind.
      module Operations
        module_function

        def records(request, kind)
          request.engine.ids(kind).map { |id| request.engine.find(kind, id) }
        end

        # A new record: `values` over the kind's defaults, its name unique among its kind.
        def create(request, proposal, kind, values:, user_data: nil)
          values = KINDS.fetch(kind).defaults(values)
          Records::Names.unique!(values.fetch("name"), records(request, kind))
          id = request.engine.propose_create(kind, proposal, :values => values, :user_data => user_data)
          { "id" => id }
        end

        # A guarded edit: a value in `expected_values` that changed since it was read refuses the whole proposal,
        # before any check of the new values. A taken name then refuses it whole. A null removes an optional value;
        # on a required one the engine refuses it.
        def update(request, proposal, kind, id:, values:, expected_values:)
          values = DeepCopy.call(values)
          values["name"] = values["name"].strip if values["name"]
          request.engine.propose_update(kind, id, proposal, :values => values, :expected_values => expected_values)
          Records::Names.unique!(values["name"], records(request, kind), :except => id) if values["name"]
          { "id" => id }
        rescue StandardError => error
          proposal.refuse(error)
          raise
        end

        # A copy is a new record derived from the original: a fresh id, its own name, the same System for a Heater
        # or Tank, and `user_data` copied by the engine.
        def duplicate(request, proposal, kind, id:, name: nil)
          rows = records(request, kind)
          mapping = request.engine.propose_duplicate(kind, [id], proposal) do |values|
            values["name"] = (name || Records::Names.copy_name(values.fetch("name"), rows)).strip
            Records::Names.unique!(values["name"], rows)
            values["source"] = { "kind" => "derived" }
            values
          end
          { "id" => mapping.fetch(id) }
        end

        # Moves every Heater and Tank naming System `from` to System `to`, each a guarded edit in the caller's
        # proposal, as a System's delete with a replacement does before the System goes.
        def move_members(request, proposal, from:, to:)
          MEMBER_KINDS.each do |kind|
            records(request, kind).select { |record| record.fetch("hot_water_system_id") == from }.each do |record|
              request.engine.propose_update(kind, record.fetch("id"), proposal,
                                            :values => { "hot_water_system_id" => to },
                                            :expected_values => { "hot_water_system_id" => from })
            end
          end
        end

        # The engine's guarded delete: a record another still names refuses as reference.in_use. `reference_plan`
        # projects the entity records a caller moved off it in the same proposal.
        def delete(request, proposal, kind, id:, expected_values: {}, reference_plan: nil)
          { "id" => id }.merge(request.engine.propose_delete(kind, id, proposal, :expected_values => expected_values,
                                                                                 :reference_plan => reference_plan))
        end
      end
    end
  end
end
