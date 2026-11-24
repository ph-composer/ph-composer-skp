# frozen_string_literal: true

module PhComposer
  module Mechanical
    module HeatPumps
      # Every heat pump kind's catalog kind, by id, with the module that gives a new record its defaults.
      KINDS = { OutdoorEquipment::KIND_ID => OutdoorEquipment, IndoorEquipment::KIND_ID => IndoorEquipment,
                OutdoorUnits::KIND_ID => OutdoorUnits, IndoorUnits::KIND_ID => IndoorUnits }.freeze
      # Who names each kind other than a Zone: the kind and key of each referring record, and whether that key is
      # required (a required one cannot be emptied, so it keeps the record in use until it is moved).
      Referrer = Struct.new(:kind, :key, :required, keyword_init: true)
      REFERRERS = {
        OutdoorEquipment::KIND_ID => [Referrer.new(:kind => OutdoorUnits::KIND_ID, :key => "outdoor_equipment_id",
                                                   :required => true)],
        IndoorEquipment::KIND_ID => [Referrer.new(:kind => OutdoorEquipment::KIND_ID,
                                                  :key => "paired_indoor_equipment_id", :required => false),
                                     Referrer.new(:kind => IndoorUnits::KIND_ID, :key => "indoor_equipment_id",
                                                  :required => true)],
        OutdoorUnits::KIND_ID => [Referrer.new(:kind => IndoorUnits::KIND_ID, :key => "outdoor_unit_id",
                                               :required => true)],
        IndoorUnits::KIND_ID => []
      }.freeze

      # Persistence for the four heat pump kinds: the catalog operations every family shares (CatalogOperations),
      # with each kind's defaults, and the move of what names a record to its replacement.
      module Operations
        module_function

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

        # Moves what names record `from` of `kind` to `to`, each a guarded edit in the caller's proposal, as a
        # delete with a replacement does before the record goes. With `to` nil only an optional reference (an
        # outdoor model's pairing) is emptied; a required one stays and keeps the record in use.
        def move_referrers(request, proposal, kind, from:, to:)
          REFERRERS.fetch(kind).each do |referrer|
            next if to.nil? && referrer.required

            CatalogOperations.move_references(request, proposal, :kinds => [referrer.kind], :key => referrer.key,
                                                                 :from => from, :to => to)
          end
        end

        def delete(request, proposal, kind, id:, expected_values: {}, reference_plan: nil)
          CatalogOperations.delete(request, proposal, kind, :id => id, :expected_values => expected_values,
                                                            :reference_plan => reference_plan)
        end
      end
    end
  end
end
