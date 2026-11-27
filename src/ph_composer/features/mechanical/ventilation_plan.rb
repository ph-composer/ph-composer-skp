# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Ventilator export worked out once, in pure Ruby over plain values, so the export contributor and the
    # preflight read the same pairs and the same findings (context/CONTRACTS.md, "Mechanical equipment"). The
    # Python section builds honeybee-ph objects from the pairs and computes nothing.
    #
    # One pair per (Ventilator, exported Zone) the Ventilator serves. Every pair of one Ventilator carries the same
    # values and the identifiers derived from its id, so honeybee-ph reloads one system for them all and PHX keys one
    # device. A Ventilator that serves no Zone, and a Zone in no Building Segment, give no pair; each has its finding.
    module VentilationPlan
      # The unit's values each pair carries, as the Ventilator stores them; the two optional ones null when absent.
      UNIT_FIELDS = %w[quantity sensible_heat_recovery latent_heat_recovery electric_efficiency_wh_m3
                       frost_protection_reqd temperature_below_defrost_used_c in_conditioned_space
                       subsoil_heat_exchange_efficiency preheated_intake_temperature_c].freeze
      UNIT_SUFFIX = "_unit"

      SLOT = "ventilator_id"
      Finding = ExportZones::Finding
      Plan = Struct.new(:pairs, :findings, keyword_init: true)

      module_function

      # `zones` are ExportZones::Zone values, one per Zone id; `ventilators` maps each stored Ventilator's id to its
      # values, with its `name` and, where the caller passes it through, its `user_data`. `unreadable` are the ids of
      # stored Ventilators that cannot be read, which the caller reports itself: a Zone naming one is not missing one.
      def call(zones:, ventilators:, unreadable: [])
        exported, left_out = zones.sort_by(&:id).partition(&:exported)
        Plan.new(:pairs => pairs(exported, ventilators),
                 :findings => zone_findings(exported, ventilators, unreadable) +
                              ExportZones.item_findings(exported, left_out, ventilators, SLOT, "Ventilator"))
      end

      def pairs(zones, ventilators)
        zones.filter_map do |zone|
          item = ventilators[zone.slot(SLOT)]
          item && pair(zone.slot(SLOT), item, zone)
        end.sort_by { |row| row.fetch("id") }
      end

      def pair(item_id, item, zone)
        row = { "id" => "#{item_id}_#{zone.id}", "item_id" => item_id, "zone_id" => zone.id,
                "system_identifier" => item_id, "unit_identifier" => "#{item_id}#{UNIT_SUFFIX}",
                "display_name" => item.fetch("name") }
        UNIT_FIELDS.each { |key| row[key] = item.fetch(key, nil) }
        item.key?("user_data") ? row.merge("user_data" => DeepCopy.call(item.fetch("user_data"))) : row
      end

      # An exported Zone with no Ventilator, or one naming a Ventilator that is not stored.
      def zone_findings(zones, ventilators, unreadable)
        zones.filter_map do |zone|
          id = zone.slot(SLOT)
          if id.nil?
            Finding.new(:code => Codes::ZONE_UNVENTILATED, :record_id => zone.id, :blocks => false,
                        :message => "#{zone.titled} has no Ventilator.")
          elsif !ventilators.key?(id) && !unreadable.include?(id)
            Finding.new(:code => Codes::ITEM_MISSING, :record_id => zone.id, :blocks => true,
                        :message => "ventilator_id on #{zone.titled} names #{id}, which is not in the Model.")
          end
        end
      end
    end
  end
end
