# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The codes the `mechanical` noun owns (context/CONTRACTS.md, "Outcomes and codes"): one refusal and the
    # findings the reads and the export report. Refusals Zones owns keep Zones' `target.*` codes, and a delete in
    # use keeps the foundation's reference.in_use.
    module Codes
      SLOT_FILLED = "mechanical.slot_filled"
      ZONE_UNVENTILATED = "mechanical.zone_unventilated"
      ITEM_UNSERVED = "mechanical.item_unserved"
      ITEM_MISSING = "mechanical.item_missing"
      ZONE_LEFT_OUT = "mechanical.zone_left_out"
      ITEM_ACROSS_SEGMENTS = "mechanical.item_across_segments"
      ZONE_NO_HOT_WATER = "mechanical.zone_no_hot_water"
      TANK_UNSLOTTED = "mechanical.tank_unslotted"
      HOT_WATER_POOLED = "mechanical.hot_water_pooled"
      METHOD_NOT_EXPORTED = "mechanical.method_not_exported"

      DESCRIPTIONS = {
        SLOT_FILLED => "The Zone's slot already names another item; assign with replace to use the new one.",
        ZONE_UNVENTILATED => "A Zone in a Building Segment has no Ventilator.",
        ITEM_UNSERVED => "An item serves no Zone, so nothing exports it.",
        ITEM_MISSING => "A Zone's slot names an item that is not in the Model; reassign or clear it.",
        ZONE_LEFT_OUT => "A served Zone is in no Building Segment, so the export leaves its Room out.",
        ITEM_ACROSS_SEGMENTS => "An item serves Zones in more than one Building Segment; each Segment's model " \
                                "carries the whole item.",
        ZONE_NO_HOT_WATER => "A Zone in a Building Segment has no Hot Water System.",
        TANK_UNSLOTTED => "A Hot Water Tank has no free slot of its role on its System, so the export leaves it out.",
        HOT_WATER_POOLED => "More than one Hot Water System serves one Building Segment; WUFI-Passive and METr pool " \
                            "their tanks and heaters and keep one tap point count.",
        METHOD_NOT_EXPORTED => "A Hot Water System's piping calculation method is set, and the pinned honeybee-ph " \
                               "has no field for it, so the export leaves it out."
      }.freeze

      module_function

      def install(feature)
        DESCRIPTIONS.each { |code, description| feature.code(code, :description => description) }
      end

      # A read row's finding: an error blocks the export, a warning or info does not.
      def finding(code, severity, message)
        { "code" => code, "severity" => severity, "message" => message, "blocks_export" => severity == "error" }
      end
    end
  end
end
