# frozen_string_literal: true

module PhComposer
  module Ducting
    # The codes the `ducting` noun owns (context/CONTRACTS.md, "Outcomes and codes"), published in
    # docs/API_REFERENCE.md.
    module Codes
      INSULATION_CONDUCTIVITY_MISSING = "ducting.insulation_conductivity_missing"
      OUTSIDE_GROUP = "ducting.outside_group"
      GROUP_IN_ZONE = "ducting.group_in_zone"
      GROUP_NESTED = "ducting.group_nested"
      TYPE_MISSING = "ducting.type_missing"
      GROUP_UNLINKED = "ducting.group_unlinked"
      RUN_MISSING = "ducting.run_missing"
      SHARED_DEFINITION = "ducting.shared_definition"
      HIDDEN = "ducting.hidden"

      DESCRIPTIONS = {
        INSULATION_CONDUCTIVITY_MISSING => "A Duct Type has insulation and no insulation conductivity, so a duct " \
                                           "using it cannot export.",
        OUTSIDE_GROUP => "An Edge is not directly inside a Ducting group, so it cannot be a duct.",
        GROUP_IN_ZONE => "A Ducting group sits inside a Zone; ducts live outside Zones.",
        GROUP_NESTED => "A Ducting group sits inside another Ducting group.",
        TYPE_MISSING => "A duct has no Duct Type, or names one that no longer exists, so it cannot export.",
        GROUP_UNLINKED => "A Ducting group is linked to no Ventilator, or to one that no longer exists, so its ducts " \
                          "cannot export.",
        RUN_MISSING => "A Ventilator serving a Zone has no Outdoor air run or no Exhaust air run; METr assumes none.",
        SHARED_DEFINITION => "Ducts are reached through two placements of one Ducting group's storage, and both count.",
        HIDDEN => "A duct to locate, or a Group holding it, is hidden or on a hidden tag."
      }.freeze

      module_function

      def install(feature)
        DESCRIPTIONS.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
