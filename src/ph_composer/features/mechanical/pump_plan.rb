# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Pump export worked out once, in pure Ruby over plain values, so the export contributor and the preflight
    # read the same pairs and the same findings (context/CONTRACTS.md, "Mechanical equipment"). The Python section
    # builds honeybee-ph objects from the pairs and computes nothing.
    #
    # One pair per (Pump, exported Zone) whose pump list names it. Every pair of one pump carries the same values
    # under the pump's id, its usage profile resolved (Pumps.ihg_usage_profile), so honeybee-ph reloads one supportive
    # device for them all and PHX keys one device. A pump that serves no Zone, and a Zone in no Building Segment, give
    # no pair; each has its finding. PHX reads supportive devices through a Room's Spaces, so a served Zone with no
    # Space has a finding too, and its pair is still written.
    module PumpPlan
      SLOT = "pump_ids"
      LABEL = "Pump"
      # The values each pair carries, the record's names.
      VALUES = %w[device_type quantity in_conditioned_space norm_energy_demand_w annual_period_operation_khrs
                  ihg_utilization_factor].freeze
      Finding = ExportZones::Finding
      Plan = Struct.new(:pairs, :findings, keyword_init: true)

      module_function

      # `zones` are ExportZones::Zone values, one per Zone id; `pumps` maps each stored pump's id to its values, with
      # its `name` and, where the caller passes it through, its `user_data`. `spaced` holds the ids of the Zones a
      # Space names, or is nil when they cannot be read, which skips the no-Spaces finding. `unreadable` are the ids
      # of stored pumps that cannot be read, which the caller reports itself: a Zone naming one is not missing one.
      def call(zones:, pumps:, spaced:, unreadable: [])
        exported, left_out = zones.sort_by(&:id).partition(&:exported)
        spaceless = spaced ? ExportZones.spaceless_findings(exported, pumps, SLOT, LABEL, spaced) : []
        Plan.new(:pairs => pairs(exported, pumps),
                 :findings => zone_findings(exported, pumps, unreadable) +
                              ExportZones.item_findings(exported, left_out, pumps, SLOT, LABEL) + spaceless)
      end

      def pairs(zones, pumps)
        zones.flat_map do |zone|
          zone.slot(SLOT).filter_map { |id| pumps.key?(id) && pair(id, pumps.fetch(id), zone) }
        end.sort_by { |row| row.fetch("id") }
      end

      def pair(item_id, item, zone)
        row = { "id" => "#{item_id}_#{zone.id}", "item_id" => item_id, "zone_id" => zone.id,
                "identifier" => item_id, "display_name" => item.fetch("name") }
              .merge(item.slice(*VALUES), "ihg_usage_profile" => Pumps.ihg_usage_profile(item))
        item.key?("user_data") ? row.merge("user_data" => DeepCopy.call(item.fetch("user_data"))) : row
      end

      # Each id an exported Zone's pump list names that is not a stored pump: the export cannot say what it is.
      def zone_findings(zones, pumps, unreadable)
        zones.flat_map do |zone|
          zone.slot(SLOT).reject { |id| pumps.key?(id) || unreadable.include?(id) }.map do |id|
            Finding.new(:code => Codes::ITEM_MISSING, :record_id => zone.id, :blocks => true,
                        :message => "#{SLOT} on #{zone.titled} names #{id}, which is not in the Model.")
          end
        end
      end
    end
  end
end
