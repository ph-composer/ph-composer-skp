# frozen_string_literal: true

module PhComposer
  module Mechanical
    module SegmentSettings
      # Whether a Building Segment's mechanical cooling switch agrees with its blended heat pump, worked out over plain
      # values so the preflight and the export give the same rows. The switch is entered, not derived
      # (context/CONTRACTS.md, "Building Segment mechanical settings"), so a disagreement is a warning that never
      # blocks: the switch on with no cooling in the Segment's exported blend, or no blend at all, and off with a blend
      # that cools.
      module Cooling
        module_function

        # `segments` are the settings rows of the exported Segments, each with its `id`, `name` and
        # `mechanical_cooling`. `cooling` maps each Segment name whose blend exports to whether that blend cools;
        # blends key by name, as HeatPumpPlan does. Gives ExportZones::Finding values, one per Segment that disagrees.
        def findings(segments, cooling)
          segments.sort_by { |row| [row.fetch("name").to_s, row.fetch("id")] }.filter_map do |row|
            switch = row.fetch("mechanical_cooling")
            cools = cooling.fetch(row.fetch("name"), false)
            next if switch == cools

            ExportZones::Finding.new(:code => Codes::SEGMENT_COOLING_MISMATCH, :record_id => row.fetch("id"),
                                     :blocks => false, :message => message(row.fetch("name"), switch))
          end
        end

        def message(name, switch)
          if switch
            "Building Segment #{name} has mechanical cooling switched on, and its export carries no heat pump " \
              "cooling. Switch it off in the Segment's settings, or serve its Zones with a heat pump that cools."
          else
            "Building Segment #{name} has mechanical cooling switched off, and its blended heat pump cools. " \
              "Switch it on in the Segment's settings if the building is cooled."
          end
        end
      end
    end
  end
end
