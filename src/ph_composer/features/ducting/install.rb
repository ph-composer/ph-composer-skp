# frozen_string_literal: true

# One feature owns ERV ducting, the two cold runs between each Ventilator and the outside: the Duct Type catalog now,
# and later the Ducting groups that hold drawn ducts, the assignment on each duct, their runs and their export into
# the Ventilator's ventilation system. It requires Mechanical, which owns the Ventilator and its export, and Zones;
# no file of theirs, nor any other feature's, names it (context/EXTENSIBILITY.md, "Organization and dependencies").
#
#   type/           the Duct Type kind, its operations and reads; names no Edge, group or run
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
require_relative "declarations/duct_types"

module PhComposer
  module Ducting
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => %w[ph_composer.mechanical ph_composer.zones])
      DuctTypeRegistration.install(feature)
      Codes.install(feature)
    end
  end
end
