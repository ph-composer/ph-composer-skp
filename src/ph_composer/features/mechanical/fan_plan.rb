# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Fan export worked out once, in pure Ruby over plain values, so the export contributor and the preflight
    # read the same pairs and the same findings (context/CONTRACTS.md, "Mechanical equipment"). The Python section
    # builds honeybee-ph objects from the pairs and computes nothing.
    #
    # One pair per (Fan, exported Zone) whose fan list names it. Every pair of one fan carries the same values under
    # the fan's id, its operation resolved (Fans.annual_period_operation_khrs), so honeybee-ph reloads one exhaust
    # ventilator, and with Power one supportive device, for them all and PHX keys one of each. Power is null when the
    # fan has none, which exports no supportive device. A fan that serves no Zone, and a Zone in no Building Segment,
    # give no pair; each has its finding. PHX reads both objects through a Room's Spaces, so a served Zone with no
    # Space has a finding too, and its pair is still written.
    module FanPlan
      SLOT = "fan_ids"
      LABEL = "Fan"
      # The values each pair carries, the record's names; Power and the operation follow.
      VALUES = %w[exhaust_type quantity exhaust_flow_rate_m3h annual_runtime_minutes in_conditioned_space].freeze
      Finding = ExportZones::Finding
      Plan = Struct.new(:pairs, :findings, keyword_init: true)

      module_function

      # `zones` are ExportZones::Zone values, one per Zone id; `fans` maps each stored fan's id to its values, with
      # its `name` and, where the caller passes it through, its `user_data`. `spaced` holds the ids of the Zones a
      # Space names, or is nil when they cannot be read, which skips the no-Spaces finding. `unreadable` are the ids
      # of stored fans that cannot be read, which the caller reports itself: a Zone naming one is not missing one.
      def call(zones:, fans:, spaced:, unreadable: [])
        exported, left_out = zones.sort_by(&:id).partition(&:exported)
        spaceless = spaced ? ExportZones.spaceless_findings(exported, fans, SLOT, LABEL, spaced) : []
        Plan.new(:pairs => pairs(exported, fans),
                 :findings => zone_findings(exported, fans, unreadable) +
                              ExportZones.item_findings(exported, left_out, fans, SLOT, LABEL) + spaceless)
      end

      def pairs(zones, fans)
        zones.flat_map do |zone|
          zone.slot(SLOT).filter_map { |id| fans.key?(id) && pair(id, fans.fetch(id), zone) }
        end.sort_by { |row| row.fetch("id") }
      end

      def pair(item_id, item, zone)
        row = { "id" => "#{item_id}_#{zone.id}", "item_id" => item_id, "zone_id" => zone.id,
                "identifier" => item_id, "display_name" => item.fetch("name") }
              .merge(item.slice(*VALUES), "norm_energy_demand_w" => item["norm_energy_demand_w"],
                                          "annual_period_operation_khrs" => Fans.annual_period_operation_khrs(item))
        item.key?("user_data") ? row.merge("user_data" => DeepCopy.call(item.fetch("user_data"))) : row
      end

      # Each id an exported Zone's fan list names that is not a stored fan: the export cannot say what it is.
      def zone_findings(zones, fans, unreadable)
        zones.flat_map do |zone|
          zone.slot(SLOT).reject { |id| fans.key?(id) || unreadable.include?(id) }.map do |id|
            Finding.new(:code => Codes::ITEM_MISSING, :record_id => zone.id, :blocks => true,
                        :message => "#{SLOT} on #{zone.titled} names #{id}, which is not in the Model.")
          end
        end
      end
    end
  end
end
