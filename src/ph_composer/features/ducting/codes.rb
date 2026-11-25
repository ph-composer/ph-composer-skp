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

      DESCRIPTIONS = {
        INSULATION_CONDUCTIVITY_MISSING => "A Duct Type has insulation and no insulation conductivity, so a duct " \
                                           "using it cannot export.",
        OUTSIDE_GROUP => "An Edge is not directly inside a Ducting group, so it cannot be a duct.",
        GROUP_IN_ZONE => "A Ducting group sits inside a Zone; ducts live outside Zones.",
        GROUP_NESTED => "A Ducting group sits inside another Ducting group."
      }.freeze

      module_function

      def install(feature)
        DESCRIPTIONS.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
