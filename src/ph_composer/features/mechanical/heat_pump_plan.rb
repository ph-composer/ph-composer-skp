# frozen_string_literal: true

require "digest"

module PhComposer
  module Mechanical
    # The heat pump export worked out once, in pure Ruby over plain values, so the export contributor, the preflight
    # and the Blended result read the same blends and the same findings (context/CONTRACTS.md, "Mechanical
    # equipment"). The Python section builds honeybee-ph objects from the pairs and computes nothing.
    #
    # One blended heat pump per exported Building Segment: from the outdoor models whose outdoor units have
    # indoor units serving that Segment's Zones, one row per model with its outdoor units' summed quantity, blended
    # as the Phius estimator does (HeatPumps::Blend). One pair per (Segment's blend, served Zone), each carrying the
    # same values under the Segment's identifier, so honeybee-ph reloads one system on every served Room and PHX
    # keys one device. A Segment exports its blend whole, however large: PHX splits cooling over WUFI-Passive's
    # limit, and the note says so.
    module HeatPumpPlan
      SLOT = "hp_indoor_unit_ids"
      Finding = ExportZones::Finding
      Plan = Struct.new(:blends, :pairs, :findings, keyword_init: true)
      # Above this the estimator would split cooling over more systems; 200 kW is WUFI-Passive's per-device limit.
      OVER_LIMIT_KBTUH = HeatPumps::Blend::SYSTEM_LIMIT_KBTUH

      module_function

      # `zones` are ExportZones::Zone values, one per Zone id. `outdoor_equipment`, `outdoor_units` and
      # `indoor_units` map each stored record's id to its values with its name. `climate` is a Blend::Climate, or
      # the sentence saying why the Model's climate cannot be read for a blend. `unreadable` are ids of stored
      # records that cannot be read, which the caller reports itself.
      def call(zones:, outdoor_equipment:, outdoor_units:, indoor_units:, climate:, unreadable: [])
        exported, left_out = zones.sort_by(&:id).partition(&:exported)
        found = zone_findings(exported, indoor_units, unreadable) + unit_findings(exported, left_out, outdoor_units,
                                                                                  indoor_units)
        segments = segments(exported, outdoor_units, indoor_units)
        found.concat(parents_missing(exported, outdoor_equipment, outdoor_units, indoor_units, unreadable))
        found.concat(incomplete(segments, outdoor_equipment))
        if segments.empty?
          blends = []
        elsif climate.is_a?(String)
          found << Finding.new(:code => Codes::HP_CLIMATE_MISSING, :record_id => nil, :blocks => false,
                               :message => "#{climate} The blended heat pump is left out of the export.")
          blends = []
        else
          blends, more = blend_segments(segments, outdoor_equipment, outdoor_units, climate)
          found.concat(more)
        end
        Plan.new(:blends => blends, :pairs => blends.flat_map { |blend| pairs(blend) }, :findings => found)
      end

      # The Climate the blend reads, or why it cannot: twelve monthly mean air temperatures and both design
      # temperatures, all C. `monthly` is the climate's air temperature row, nil with no climate.
      def climate(monthly, heating_99_c, cooling_1_c)
        if monthly.nil? || monthly.length != 12 || !monthly.all?(Numeric)
          return "The Model's climate has no complete row of monthly mean air temperatures."
        end
        unless heating_99_c.is_a?(Numeric) && cooling_1_c.is_a?(Numeric)
          return "The Model's ASHRAE 99% heating and 1% cooling design temperatures are not both set."
        end

        HeatPumps::Blend::Climate.new(:monthly_air_c => monthly, :heating_99_c => heating_99_c,
                                      :cooling_1_c => cooling_1_c)
      end

      # ------------------------------------------------------------------ Segments

      # Each exported Building Segment with a served Zone, in name order: its name, its served Zones each with the
      # outdoor models its indoor units reach, the outdoor units those indoor units name, and their models.
      def segments(exported, outdoor_units, indoor_units)
        model_of = lambda do |indoor_id|
          unit = outdoor_units[indoor_units.fetch(indoor_id).fetch("outdoor_unit_id")]
          unit && unit.fetch("outdoor_equipment_id")
        end
        exported.group_by(&:segment).sort_by { |segment, _zones| segment.to_s }.filter_map do |segment, group|
          served = group.filter_map do |zone|
            units = zone.slot(SLOT).select { |id| indoor_units.key?(id) }
            units.empty? ? nil : [zone, units.filter_map { |id| model_of.call(id) }.uniq]
          end
          next if served.empty?

          outdoor = group.flat_map { |zone| zone.slot(SLOT).select { |id| indoor_units.key?(id) } }
                         .map { |id| indoor_units.fetch(id).fetch("outdoor_unit_id") }.uniq.select do |id|
            outdoor_units.key?(id)
          end
          { :segment => segment, :zones => served, :outdoor_unit_ids => outdoor.sort,
            :equipment_ids => served.flat_map { |_zone, models| models }.uniq }
        end
      end

      # Each Segment's blend from the complete outdoor models its outdoor units install, and the notes it gives.
      def blend_segments(segments, outdoor_equipment, outdoor_units, climate)
        notes = []
        blends = segments.filter_map do |entry|
          rows = rows(entry.fetch(:outdoor_unit_ids), outdoor_equipment, outdoor_units)
          next if rows.empty?

          result = HeatPumps::Blend.call(rows, climate)
          blend = blend_entry(entry, rows, result)
          heats = heating?(result)
          notes.concat(weightless(entry.fetch(:segment), result, heats))
          next unless heats

          notes << over_limit(blend) if over_limit?(result)
          blend
        end
        [blends, notes]
      end

      # One row per complete outdoor model the Segment's outdoor units install, its quantity their sum, in name
      # order.
      def rows(outdoor_unit_ids, outdoor_equipment, outdoor_units)
        outdoor_unit_ids.map { |id| outdoor_units.fetch(id) }.group_by { |unit| unit.fetch("outdoor_equipment_id") }
                        .filter_map do |equipment_id, units|
          equipment = outdoor_equipment[equipment_id]
          next unless equipment && HeatPumps::OutdoorEquipment.missing_inputs(equipment).empty?

          HeatPumps::Blend::Row.new(:id => equipment_id, :name => equipment.fetch("name"), :equipment => equipment,
                                    :quantity => units.sum { |unit| unit.fetch("quantity") })
        end.sort_by { |row| [row.name, row.id] }
      end

      def blend_entry(entry, rows, result)
        segment = entry.fetch(:segment)
        equipment = rows.map(&:id)
        zones = entry.fetch(:zones).select { |_zone, models| (models & equipment).any? }
        { "segment" => segment, "identifier" => identifier(segment), "display_name" => "Heat pumps: #{segment}",
          "zones" => zones.map { |zone, _units| { "zone_id" => zone.id, "name" => zone.label } },
          "outdoor_unit_ids" => entry.fetch(:outdoor_unit_ids), "result" => result }
      end

      # The Segment's blended heat pump's identifier: the same on every Room it is written to, and the same from one
      # export to the next while the Segment keeps its name.
      def identifier(segment)
        "ph_composer_heat_pump_#{Digest::SHA256.hexdigest(segment.to_s)[0, 12]}"
      end

      def heating?(result)
        export = result.fetch("export")
        export.fetch("cop_1").positive? && export.fetch("cop_2").positive?
      end

      def over_limit?(result)
        result.fetch("totals").fetch("cooling").fetch("capacity_kbtuh") > OVER_LIMIT_KBTUH
      end

      def pairs(blend)
        export = blend.fetch("result").fetch("export")
        blend.fetch("zones").map do |zone|
          { "id" => "#{blend.fetch('identifier')}_#{zone.fetch('zone_id')}", "zone_id" => zone.fetch("zone_id"),
            "segment" => blend.fetch("segment"), "system_identifier" => blend.fetch("identifier"),
            "display_name" => blend.fetch("display_name") }.merge(DeepCopy.call(export))
        end
      end

      # ------------------------------------------------------------------ findings

      # An exported Zone naming an indoor unit that is not stored: the export cannot say what serves it.
      def zone_findings(zones, indoor_units, unreadable)
        zones.flat_map do |zone|
          zone.slot(SLOT).reject { |id| indoor_units.key?(id) || unreadable.include?(id) }.map do |id|
            Finding.new(:code => Codes::ITEM_MISSING, :record_id => zone.id, :blocks => true,
                        :message => "#{SLOT} on #{zone.titled} names #{id}, which is not in the Model.")
          end
        end
      end

      # An indoor unit serving no Zone, or Zones the export leaves out; an outdoor unit whose indoor units serve no
      # exported Zone, or Zones in more than one Building Segment.
      def unit_findings(exported, left_out, outdoor_units, indoor_units)
        serving = ->(zones, id) { zones.select { |zone| zone.slot(SLOT).include?(id) } }
        indoor = indoor_units.keys.sort.flat_map do |id|
          name = indoor_units.fetch(id).fetch("name")
          served = serving.call(exported, id)
          gone = serving.call(left_out, id)
          next [unpaired(id, "#{name} serves no Zone, so the blend leaves it out.")] if served.empty? && gone.empty?

          gone.map { |zone| ExportZones.left_out(id, name, zone) }
        end
        outdoor = outdoor_units.keys.sort.flat_map do |id|
          name = outdoor_units.fetch(id).fetch("name")
          mine = indoor_units.select { |_indoor, unit| unit.fetch("outdoor_unit_id") == id }.keys
          served = exported.select { |zone| (zone.slot(SLOT) & mine).any? }
          next [unpaired(id, "#{name} has no indoor unit serving a Zone, so the blend leaves it out.")] if
            served.empty?

          ExportZones.across_segments(id, name, served, "outdoor unit")
        end
        indoor + outdoor
      end

      # A served indoor unit naming an outdoor unit that is not stored, or a served outdoor unit naming an outdoor
      # model that is not: the engine refuses both, so only a record written outside it can carry one. It blocks, as
      # a Zone naming a missing item does, since the export cannot say what serves those Zones.
      def parents_missing(exported, outdoor_equipment, outdoor_units, indoor_units, unreadable)
        served = exported.flat_map { |zone| zone.slot(SLOT) }.uniq.sort.select { |id| indoor_units.key?(id) }
        missing = ->(id) { !id.nil? && !unreadable.include?(id) }
        indoor = served.filter_map do |id|
          unit = indoor_units.fetch(id)
          parent = unit.fetch("outdoor_unit_id")
          next unless missing.call(parent) && !outdoor_units.key?(parent)

          broken(id, "#{unit.fetch('name')} names outdoor unit #{parent}, which is not in the Model.")
        end
        outdoor = served.map { |id| indoor_units.fetch(id).fetch("outdoor_unit_id") }.uniq.sort.filter_map do |id|
          unit = outdoor_units[id]
          parent = unit && unit.fetch("outdoor_equipment_id")
          next unless unit && missing.call(parent) && !outdoor_equipment.key?(parent)

          broken(id, "#{unit.fetch('name')} names outdoor equipment #{parent}, which is not in the Model.")
        end
        indoor + outdoor
      end

      def broken(id, message)
        Finding.new(:code => Codes::ITEM_MISSING, :record_id => id, :blocks => true,
                    :message => "#{message} Choose another, so the Zones it serves have a heat pump.")
      end

      def unpaired(id, message)
        Finding.new(:code => Codes::HP_UNIT_UNPAIRED, :record_id => id, :blocks => false, :message => message)
      end

      # Each outdoor model a served Segment installs that lacks a value the blend needs, once.
      def incomplete(segments, outdoor_equipment)
        ids = segments.flat_map { |entry| entry.fetch(:equipment_ids) }.uniq.sort
        ids.filter_map do |id|
          equipment = outdoor_equipment[id]
          missing = equipment && HeatPumps::OutdoorEquipment.missing_inputs(equipment)
          next if missing.nil? || missing.empty?

          Finding.new(:code => Codes::HP_EQUIPMENT_INCOMPLETE, :record_id => id, :blocks => false,
                      :message => "#{equipment.fetch('name')} has no #{missing.join(', ')}, so the blend leaves " \
                                  "its outdoor units out.")
        end
      end

      # Each model of a Segment's blend that adds heating capacity and no heating COP: an HSPF model with no share
      # of cooling, which the estimator weights its HSPF by. When the whole blend heats with no COP, it is left out.
      def weightless(segment, result, heats)
        result.fetch("weighted").select do |row|
          row.fetch("capacity_17f").positive? && row.fetch("cop_17f").zero?
        end.map do |row|
          outcome = heats ? "it adds no heating COP to the blend of Building Segment #{segment}" :
                            "Building Segment #{segment} blends to no heating COP and its heat pump is left out"
          Finding.new(:code => Codes::HP_EQUIPMENT_INCOMPLETE, :record_id => row.fetch("id"), :blocks => false,
                      :message => "#{row.fetch('name')} is rated by HSPF with no share of cooling, which the Phius " \
                                  "estimator weights an HSPF by, so #{outcome}. Enter its cooling rating, or its " \
                                  "COPs at 17 F and 47 F.")
        end
      end

      def over_limit(blend)
        kilowatts = blend.fetch("result").fetch("export").fetch("cooling").fetch("capacity_kw")
        Finding.new(:code => Codes::HP_COOLING_OVER_200KW, :record_id => nil, :blocks => false,
                    :message => "Building Segment #{blend.fetch('segment')} blends #{kilowatts.round} kW of " \
                                "cooling, over 200 kW (682 kBtu/h). PH-Composer exports it as one system; PHX " \
                                "splits it for WUFI-Passive, and METr takes it whole.")
      end
    end
  end
end
