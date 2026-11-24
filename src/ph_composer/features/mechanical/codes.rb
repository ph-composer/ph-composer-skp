# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The codes the `mechanical` noun owns (context/CONTRACTS.md, "Outcomes and codes"): one refusal and the
    # findings the reads report. Refusals Zones owns keep Zones' `target.*` codes, and a delete in use keeps the
    # foundation's reference.in_use.
    module Codes
      SLOT_FILLED = "mechanical.slot_filled"
      ZONE_UNVENTILATED = "mechanical.zone_unventilated"
      ITEM_UNSERVED = "mechanical.item_unserved"
      ITEM_MISSING = "mechanical.item_missing"
      ZONE_LEFT_OUT = "mechanical.zone_left_out"

      DESCRIPTIONS = {
        SLOT_FILLED => "The Zone's slot already names another item; assign with replace to use the new one.",
        ZONE_UNVENTILATED => "A Zone in a Building Segment has no Ventilator.",
        ITEM_UNSERVED => "An item serves no Zone, so nothing exports it.",
        ITEM_MISSING => "A Zone's slot names an item that is not in the Model; reassign or clear it.",
        ZONE_LEFT_OUT => "A served Zone is in no Building Segment, so the export leaves its Room out."
      }.freeze

      module_function

      def install(feature)
        DESCRIPTIONS.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
