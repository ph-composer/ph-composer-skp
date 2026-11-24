# frozen_string_literal: true

module PhComposer
  module Piping
    # The codes the `piping` noun owns (context/CONTRACTS.md, "Outcomes and codes"), published in
    # docs/API_REFERENCE.md.
    module Codes
      INSULATION_CONDUCTIVITY_MISSING = "piping.insulation_conductivity_missing"
      OUTSIDE_GROUP = "piping.outside_group"
      GROUP_IN_ZONE = "piping.group_in_zone"
      GROUP_NESTED = "piping.group_nested"

      DESCRIPTIONS = {
        INSULATION_CONDUCTIVITY_MISSING => "A Pipe Type has insulation and no insulation conductivity, so a pipe " \
                                           "using it cannot export.",
        OUTSIDE_GROUP => "An Edge is not directly inside a Piping group, so it cannot be a pipe.",
        GROUP_IN_ZONE => "A Piping group sits inside a Zone; pipes live outside Zones.",
        GROUP_NESTED => "A Piping group sits inside another Piping group."
      }.freeze

      module_function

      def install(feature)
        DESCRIPTIONS.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
