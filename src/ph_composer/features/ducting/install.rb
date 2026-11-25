# frozen_string_literal: true

# One feature owns ERV ducting, the two cold runs between each Ventilator and the outside: the Duct Type catalog, the
# Ducting groups that hold drawn ducts and the assignment on each duct, and later their runs and their export into
# the Ventilator's ventilation system. It requires Mechanical, which owns the Ventilator and its export, and Zones;
# no file of theirs, nor any other feature's, names it (context/EXTENSIBILITY.md, "Organization and dependencies").
#
#   type/           the Duct Type kind, its operations and reads; names no Edge, group or run
#   group/          the Ducting group record on a Group, its reference target, create, link and the occurrence rows
#   assignment/     the duct record on an Edge, its reference target, assign, clear, the type rewrite and the selection
#   line_group.rb   the spec the foundation's line_groups/ layer reads ducting by
#   codes.rb        the `ducting` noun's codes
#   declarations/   what the feature registers
module PhComposer
  module Ducting
    FEATURE_ID = "ph_composer.ducting"
  end
end

require_relative "codes"
require_relative "type/schema"
require_relative "type/operations"
require_relative "type/reads"
require_relative "group/schema"
require_relative "assignment/schema"
require_relative "line_group"
require_relative "group/reference_target"
require_relative "group/operations"
require_relative "assignment/reference_target"
require_relative "assignment/operations"
require_relative "assignment/selection"
require_relative "declarations/duct_types"
require_relative "declarations/groups"
require_relative "declarations/ducts"

module PhComposer
  module Ducting
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => %w[ph_composer.mechanical ph_composer.zones])
      DuctTypeRegistration.install(feature)
      GroupRegistration.install(feature)
      DuctRegistration.install(feature)
      Codes.install(feature)
    end
  end
end
