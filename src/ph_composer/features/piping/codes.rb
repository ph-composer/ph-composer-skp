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
      TYPE_MISSING = "piping.type_missing"
      GROUP_UNLINKED = "piping.group_unlinked"
      BRANCH_UNCONNECTED = "piping.branch_unconnected"
      TWIG_UNCONNECTED = "piping.twig_unconnected"
      TRUNK_WITHOUT_BRANCHES = "piping.trunk_without_branches"
      PARENT_AMBIGUOUS = "piping.parent_ambiguous"
      SHARED_DEFINITION = "piping.shared_definition"
      HIDDEN = "piping.hidden"
      SYSTEM_UNEXPORTED = "piping.system_unexported"

      DESCRIPTIONS = {
        INSULATION_CONDUCTIVITY_MISSING => "A Pipe Type has insulation and no insulation conductivity, so a pipe " \
                                           "using it cannot export.",
        OUTSIDE_GROUP => "An Edge is not directly inside a Piping group, so it cannot be a pipe.",
        GROUP_IN_ZONE => "A Piping group sits inside a Zone; pipes live outside Zones.",
        GROUP_NESTED => "A Piping group sits inside another Piping group.",
        TYPE_MISSING => "A pipe has no Pipe Type, or names one that no longer exists, so it cannot export.",
        GROUP_UNLINKED => "A Piping group is linked to no Hot Water System, or to one that no longer exists, so its " \
                          "pipes cannot export.",
        BRANCH_UNCONNECTED => "A branch run shares no vertex with a trunk run in its Piping group, so it cannot " \
                              "export.",
        TWIG_UNCONNECTED => "A twig run shares no vertex with a branch run in its Piping group, so it cannot export.",
        TRUNK_WITHOUT_BRANCHES => "A trunk run no branch touches.",
        PARENT_AMBIGUOUS => "A branch or twig touches two possible parents and hangs from the one whose identifier " \
                            "sorts first.",
        SHARED_DEFINITION => "Pipes are reached through two placements of one Piping group's storage, and both count.",
        HIDDEN => "A pipe to locate, or a Group holding it, is hidden or on a hidden tag.",
        SYSTEM_UNEXPORTED => "A Hot Water System with pipes serves no exported Zone, so its pipes are not exported."
      }.freeze

      module_function

      def install(feature)
        DESCRIPTIONS.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
