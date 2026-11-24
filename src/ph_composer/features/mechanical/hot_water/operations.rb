# frozen_string_literal: true

module PhComposer
  module Mechanical
    module HotWater
      # Every hot water kind's catalog kind, by id, with the module that gives a new record its defaults.
      KINDS = { Systems::KIND_ID => Systems, Heaters::KIND_ID => Heaters, Tanks::KIND_ID => Tanks }.freeze
      # The kinds that name a System.
      MEMBER_KINDS = [Heaters::KIND_ID, Tanks::KIND_ID].freeze

      # Persistence for the three hot water kinds: the catalog operations every family shares
      # (CatalogOperations), with each kind's defaults, and the move of a System's Heaters and Tanks.
      module Operations
        module_function

        def records(request, kind)
          CatalogOperations.records(request, kind)
        end

        def create(request, proposal, kind, values:, user_data: nil)
          CatalogOperations.create(request, proposal, kind, :defaults => KINDS.fetch(kind), :values => values,
                                                            :user_data => user_data)
        end

        def update(request, proposal, kind, id:, values:, expected_values:)
          CatalogOperations.update(request, proposal, kind, :id => id, :values => values,
                                                            :expected_values => expected_values)
        end

        def duplicate(request, proposal, kind, id:, name: nil)
          CatalogOperations.duplicate(request, proposal, kind, :id => id, :name => name)
        end

        # Moves every Heater and Tank naming System `from` to System `to`, each a guarded edit in the caller's
        # proposal, as a System's delete with a replacement does before the System goes.
        def move_members(request, proposal, from:, to:)
          CatalogOperations.move_references(request, proposal, :kinds => MEMBER_KINDS, :key => "hot_water_system_id",
                                                               :from => from, :to => to)
        end

        # `plan` with every other feature's records naming System `from` moved to `to`, or cleared with nil, through
        # the foundation's registered retargeters (context/CONTRACTS.md, "A definition delete handler"). Mechanical
        # names none of them.
        def with_retargeted(request, plan, from:, to:)
          foreign = request.retarget_references(HOT_WATER_SYSTEM_KIND, :from => from, :to => to)
          Records::ReferencePlan.new(:entries => plan.entries + foreign.entries,
                                     :removals => plan.removals + foreign.removals)
        end

        def delete(request, proposal, kind, id:, expected_values: {}, reference_plan: nil)
          CatalogOperations.delete(request, proposal, kind, :id => id, :expected_values => expected_values,
                                                            :reference_plan => reference_plan)
        end
      end
    end
  end
end
