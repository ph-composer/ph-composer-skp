# frozen_string_literal: true

# One feature owns the mechanical equipment a Zone's Room carries in the energy model: the equipment families'
# catalogs, which Zones each item serves, and their export. It requires Zones and Spaces, and Programs, whose Zone
# flow the airflow balance counts for a By Program Zone; no file of theirs, nor any other feature's, names it
# (context/EXTENSIBILITY.md, "Organization and dependencies").
#
# Each family is a folder of definitions that names no Zone, Space, Program or assignment, so a family reads
# and validates on its own. Serves sits above the families and names them:
#
#   ventilators/    the Ventilator kind, its operations and its reads
#   hot_water/      the Hot Water System, Heater and Tank kinds, their operations and reads, and the pure tank slotting
#   serves/         what serves each Zone: a payload on the Zone record that Zones stages, Assign and Clear, the
#                   Zone half of an item's delete, the reads with their findings and the airflow balance
#   codes.rb        the `mechanical` noun's codes
#   declarations/   what the feature registers: the shapes every family shares, Serves, then one file per family
#   export_zones.rb      the Zones every export plan works over, each with its slots, and the item findings they share
#   ventilation_plan.rb  the Ventilator export worked out in pure Ruby: its pairs and findings
#   export.rb            the Ventilator export section, which claims the Serves payload for the feature, and its report
#   hot_water_plan.rb    the hot water export worked out in pure Ruby: its pairs, tank slots and findings
#   hot_water_export.rb  the hot water export section
#   locate.rb            the Locate view command, which opens the Mechanical tab on an item's table or the Zones tab
#   preflight.rb         the one preflight query, each family's rows from its own plan
#   colour_modes.rb      By ventilator: each served Zone in its item's colour
require_relative "ventilators/schema"
require_relative "ventilators/operations"
require_relative "ventilators/reads"
require_relative "hot_water/systems"
require_relative "hot_water/heaters"
require_relative "hot_water/tanks"
require_relative "hot_water/slotting"
require_relative "hot_water/operations"
require_relative "hot_water/reads"
require_relative "codes"
require_relative "serves/payload"
require_relative "serves/state"
require_relative "serves/operations"
require_relative "serves/balance"
require_relative "serves/reads"
require_relative "declarations/shapes"
require_relative "declarations/serves"
require_relative "declarations/ventilators"
require_relative "declarations/hot_water"
require_relative "export_zones"
require_relative "ventilation_plan"
require_relative "export"
require_relative "hot_water_plan"
require_relative "hot_water_export"
require_relative "locate"
require_relative "preflight"
require_relative "colour_modes"

module PhComposer
  module Mechanical
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => %w[ph_composer.zones ph_composer.spaces
                                                             ph_composer.programs])
      ServesRegistration.install(feature)
      VentilatorRegistration.install(feature)
      HotWaterRegistration.install(feature)
      VentilationExport.install(feature)
      HotWaterExport.install(feature)
      Locate.install(feature)
      Preflight.install(feature)
      ColourModes.install(feature)
    end
  end
end
