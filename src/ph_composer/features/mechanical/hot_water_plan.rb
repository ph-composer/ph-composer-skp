# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The hot water export worked out once, in pure Ruby over plain values, so the export contributor and the
    # preflight read the same pairs and the same findings (context/CONTRACTS.md, "Mechanical equipment"). The Python
    # section builds honeybee-ph objects from the pairs and computes nothing.
    #
    # One pair per (Hot Water System, exported Zone) the System serves. Every pair of one System carries the same
    # values: its tap points, its Tanks in the slots Slotting gives them and its Heaters, each under the identifier
    # of its own record, so honeybee-ph holds equal systems on every Room and PHX keys each tank and heater once. A
    # System that serves no Zone, and a Zone in no Building Segment, give no pair; each has its finding.
    module HotWaterPlan
      SLOT = "hot_water_system_id"
      # A Tank's values each slot carries, as the Tank stores them.
      TANK_FIELDS = %w[tank_type quantity in_conditioned_space solar_connection solar_losses_w storage_loss_rate_w_k
                       storage_capacity_l standby_losses_w_k standby_fraction room_temp_c water_temp_c].freeze
      # A Heater's values each pair carries; the efficiency values its variant does not take are null.
      HEATER_FIELDS = (%w[variant percent_coverage in_conditioned_space] + HotWater::Heaters::EFFICIENCY_FIELDS).freeze
      # A pooling note names this many Systems, and counts the rest.
      NAMES_SHOWN = 5
      Finding = ExportZones::Finding
      Plan = Struct.new(:pairs, :findings, keyword_init: true)

      module_function

      # `zones` are ExportZones::Zone values, one per Zone id. `systems` maps each stored System's id to its values
      # with its name; `heaters` and `tanks` are the stored Heaters and Tanks, each with its `user_data` where the
      # caller passes it through. `unreadable` are the ids of stored Systems that cannot be read, which the caller
      # reports itself: a Zone naming one is not missing one.
      def call(zones:, systems:, heaters:, tanks:, unreadable: [])
        exported, left_out = zones.sort_by(&:id).partition(&:exported)
        by_system = members(systems, heaters, tanks)
        served = exported.map { |zone| zone.slot(SLOT) }.compact.uniq.select { |id| systems.key?(id) }
        Plan.new(:pairs => pairs(exported, systems, by_system),
                 :findings => zone_findings(exported, systems, unreadable) +
                              ExportZones.item_findings(exported, left_out, systems, SLOT, "Hot Water System") +
                              unslotted(served.sort, by_system) + pooled(exported, systems))
      end

      # Each System's Heaters in name order and its Tanks' slots, by System id.
      def members(systems, heaters, tanks)
        by_system = ->(rows) { rows.group_by { |row| row.fetch(SLOT) } }
        heaters_of = by_system.call(heaters)
        tanks_of = by_system.call(tanks)
        systems.keys.to_h do |id|
          [id, { :heaters => heaters_of.fetch(id, []).sort_by { |row| [row.fetch("name"), row.fetch("id")] },
                 :slots => HotWater::Slotting.call(tanks_of.fetch(id, [])) }]
        end
      end

      def pairs(zones, systems, members)
        zones.filter_map do |zone|
          id = zone.slot(SLOT)
          systems.key?(id) && pair(id, systems.fetch(id), members.fetch(id), zone)
        end.sort_by { |row| row.fetch("id") }
      end

      def pair(item_id, system, members, zone)
        row = { "id" => "#{item_id}_#{zone.id}", "item_id" => item_id, "zone_id" => zone.id,
                "system_identifier" => item_id, "display_name" => system.fetch("name"),
                "number_tap_points" => system.fetch("number_tap_points", nil),
                "piping_calc_method" => system.fetch("piping_calc_method", nil) }
        members.fetch(:slots).slots.each { |slot, tank| row[slot] = tank && member(tank, TANK_FIELDS) }
        row.merge("heaters" => members.fetch(:heaters).map { |heater| member(heater, HEATER_FIELDS) })
      end

      # A Tank or Heater as its honeybee-ph object carries it: the record's id as its identifier, its name, its
      # values and its `user_data` where the caller passed it through.
      def member(record, fields)
        row = { "identifier" => record.fetch("id"), "display_name" => record.fetch("name") }
        fields.each { |key| row[key] = record.fetch(key, nil) }
        record.key?("user_data") ? row.merge("user_data" => DeepCopy.call(record.fetch("user_data"))) : row
      end

      # An exported Zone with no Hot Water System, or one naming a System that is not stored.
      def zone_findings(zones, systems, unreadable)
        zones.filter_map do |zone|
          id = zone.slot(SLOT)
          if id.nil?
            Finding.new(:code => Codes::ZONE_NO_HOT_WATER, :record_id => zone.id, :blocks => false,
                        :message => "Zone #{zone.label} has no Hot Water System.")
          elsif !systems.key?(id) && !unreadable.include?(id)
            Finding.new(:code => Codes::ITEM_MISSING, :record_id => zone.id, :blocks => true,
                        :message => "#{SLOT} on Zone #{zone.label} names #{id}, which is not in the Model.")
          end
        end
      end

      # Each Tank of an exported System its role has no free slot for: the export leaves it out.
      def unslotted(system_ids, members)
        system_ids.flat_map do |id|
          members.fetch(id).fetch(:slots).unslotted.map do |tank|
            Finding.new(:code => Codes::TANK_UNSLOTTED, :record_id => tank.fetch("id"), :blocks => false,
                        :message => HotWater::Reads.unslotted_message(tank))
          end
        end
      end

      # Each System that shares a Building Segment with another served System, once per Segment: PHX writes one
      # Variant per Segment, so WUFI-Passive and METr pool those Systems' tanks and heaters and keep one tap point
      # count. `zones` are exported Zones. The message names at most NAMES_SHOWN Systems and counts the rest.
      def pooled(zones, systems)
        zones.group_by(&:segment).sort_by { |segment, _zones| segment.to_s }.flat_map do |segment, group|
          ids = group.map { |zone| zone.slot(SLOT) }.compact.uniq.select { |id| systems.key?(id) }
          next [] if ids.length < 2

          names = ids.map { |id| systems.fetch(id).fetch("name") }.sort
          shown = names.first(NAMES_SHOWN).join(", ")
          shown += " and #{names.length - NAMES_SHOWN} more" if names.length > NAMES_SHOWN
          ids.sort.map do |id|
            Finding.new(:code => Codes::HOT_WATER_POOLED, :record_id => id, :blocks => false,
                        :message => "#{shown} serve Building Segment #{segment}; WUFI-Passive and METr pool their " \
                                    "tanks and heaters and keep one tap point count.")
          end
        end
      end
    end
  end
end
