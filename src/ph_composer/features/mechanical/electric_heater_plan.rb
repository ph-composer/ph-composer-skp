# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Electric Heater export worked out once, in pure Ruby over plain values, so the export contributor and the
    # preflight read the same pairs and the same findings (context/CONTRACTS.md, "Mechanical equipment"). The Python
    # section builds honeybee-ph objects from the pairs and computes nothing.
    #
    # One pair per (Electric Heater, exported Zone) whose heater list names it. Every pair of one heater carries the
    # same values under the heater's id, so honeybee-ph reloads one heating system for them all and PHX keys one
    # device. A Zone may hold several heaters; their coverages are not summed or checked against each other or
    # against a heat pump's. A heater that serves no Zone, and a Zone in no Building Segment, give no pair; each has
    # its finding. PHX reads heating systems through a Room's Spaces, so a served Zone with no Space has a finding
    # too, and its pair is still written.
    module ElectricHeaterPlan
      SLOT = "heater_ids"
      LABEL = "Electric Heater"
      Finding = ExportZones::Finding
      Plan = Struct.new(:pairs, :findings, keyword_init: true)

      module_function

      # `zones` are ExportZones::Zone values, one per Zone id; `heaters` maps each stored heater's id to its values,
      # with its `name` and, where the caller passes it through, its `user_data`. `spaced` holds the ids of the Zones
      # a Space names, or is nil when they cannot be read, which skips the no-Spaces finding. `unreadable` are the
      # ids of stored heaters that cannot be read, which the caller reports itself: a Zone naming one is not missing
      # one.
      def call(zones:, heaters:, spaced:, unreadable: [])
        exported, left_out = zones.sort_by(&:id).partition(&:exported)
        spaceless = spaced ? ExportZones.spaceless_findings(exported, heaters, SLOT, LABEL, spaced) : []
        Plan.new(:pairs => pairs(exported, heaters),
                 :findings => zone_findings(exported, heaters, unreadable) +
                              ExportZones.item_findings(exported, left_out, heaters, SLOT, LABEL) + spaceless)
      end

      def pairs(zones, heaters)
        zones.flat_map do |zone|
          zone.slot(SLOT).filter_map { |id| heaters.key?(id) && pair(id, heaters.fetch(id), zone) }
        end.sort_by { |row| row.fetch("id") }
      end

      def pair(item_id, item, zone)
        row = { "id" => "#{item_id}_#{zone.id}", "item_id" => item_id, "zone_id" => zone.id,
                "identifier" => item_id, "display_name" => item.fetch("name"),
                "percent_coverage" => item.fetch("percent_coverage") }
        item.key?("user_data") ? row.merge("user_data" => DeepCopy.call(item.fetch("user_data"))) : row
      end

      # Each id an exported Zone's heater list names that is not a stored heater: the export cannot say what heats it.
      def zone_findings(zones, heaters, unreadable)
        zones.flat_map do |zone|
          zone.slot(SLOT).reject { |id| heaters.key?(id) || unreadable.include?(id) }.map do |id|
            Finding.new(:code => Codes::ITEM_MISSING, :record_id => zone.id, :blocks => true,
                        :message => "#{SLOT} on #{zone.titled} names #{id}, which is not in the Model.")
          end
        end
      end
    end
  end
end
