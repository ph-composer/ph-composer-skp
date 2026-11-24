# frozen_string_literal: true

# One feature owns the mechanical equipment a Zone's Room carries in the energy model: the equipment families'
# catalogs, and later which Zones each item serves and their export. It requires Zones and Spaces; no file of
# theirs, nor any other feature's, names it (context/EXTENSIBILITY.md, "Organization and dependencies").
#
# Each family is a folder of definitions that names no Zone, Space, Program or assignment, so a family reads
# and validates on its own:
#
#   ventilators/    the Ventilator kind, its operations and its reads
#   declarations/   what the feature registers: the shapes every family shares, then one file per family
#
# A family's refusals are the foundation's until it raises one of its own; the `mechanical` noun's codes are
# declared with the first of them.
require_relative "ventilators/schema"
require_relative "ventilators/operations"
require_relative "ventilators/reads"
require_relative "declarations/shapes"
require_relative "declarations/ventilators"

module PhComposer
  module Mechanical
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => ["ph_composer.zones", "ph_composer.spaces"])
      VentilatorRegistration.install(feature)
    end
  end
end
