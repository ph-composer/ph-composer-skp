# frozen_string_literal: true

# One feature owns the mechanical equipment a Zone's Room carries in the energy model: the equipment families'
# catalogs, which Zones each item serves, and their export. It requires Zones and Spaces, Programs, whose Zone flow
# the airflow balance counts for a By Program Zone, and Climate, whose climate the blended heat pump reads; no file of
# theirs, nor any other feature's, names it
# (context/EXTENSIBILITY.md, "Organization and dependencies").
#
# Each family is a folder of definitions that names no Zone, Space, Program or assignment, so a family reads
# and validates on its own. Serves sits above the families and names them:
#
#   ventilators/    the Ventilator kind, its operations and its reads
#   catalog_operations.rb  create, update, duplicate and delete, which every flat catalog shares
#   hot_water/      the Hot Water System, Heater and Tank kinds, their operations and reads, and the pure tank slotting
#   heat_pumps/     the outdoor and indoor models and units, their operations and reads, and the pure blend
#   electric_heaters/  the Electric Heater kind and its reads (its operations are the shared catalog's)
#   pumps/          the Pump kind, the usage profile its type gives, and its reads (its operations are the shared
#                   catalog's)
#   serves/         what serves each Zone: a payload on the Zone record that Zones stages, Assign and Clear, the
#                   Zone half of an item's delete, the reads with their findings and the airflow balance
#   codes.rb        the `mechanical` noun's codes
#   declarations/   what the feature registers: the shapes every family shares, Serves, then one file per family
#   export_zones.rb      the Zones every export plan works over, each with its slots, and the item findings they share
#   ventilation_plan.rb  the Ventilator export worked out in pure Ruby: its pairs and findings
#   export.rb            the Ventilator export section, which claims the Serves payload for the feature, and its report
#   hot_water_plan.rb    the hot water export worked out in pure Ruby: its pairs, tank slots and findings
#   hot_water_export.rb  the hot water export section
#   heat_pump_plan.rb    the blended heat pump per Building Segment worked out in pure Ruby: its pairs and findings
#   heat_pump_reads.rb   the heat pump tables' Zones, counts and findings, and the Blended result
#   heat_pump_export.rb  the heat pump export section
#   electric_heater_plan.rb    the Electric Heater export worked out in pure Ruby: its pairs and findings
#   electric_heater_export.rb  the Electric Heater export section
#   pump_plan.rb         the Pump export worked out in pure Ruby: its pairs and findings
#   pump_export.rb       the Pump export section
#   segment/             a Building Segment's mechanical settings: the extension on the Segment record, its
#                        defaults and read, and whether its cooling switch agrees with its blended heat pump
#   segment_export.rb    the Segment settings export section, and its findings
#   locate.rb            the Locate view command, which opens the Mechanical tab on an item's table or the Zones tab
#   preflight.rb         the one preflight query, each family's rows from its own plan
#   colour_modes.rb      By ventilator: each served Zone in its item's colour
require_relative "ventilators/schema"
require_relative "ventilators/operations"
require_relative "ventilators/reads"
require_relative "catalog_operations"
require_relative "hot_water/systems"
require_relative "hot_water/heaters"
require_relative "hot_water/tanks"
require_relative "hot_water/slotting"
require_relative "hot_water/operations"
require_relative "hot_water/reads"
require_relative "heat_pumps/outdoor_equipment"
require_relative "heat_pumps/units"
require_relative "heat_pumps/blend"
require_relative "heat_pumps/operations"
require_relative "electric_heaters/schema"
require_relative "electric_heaters/reads"
require_relative "pumps/schema"
require_relative "pumps/reads"
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
require_relative "heat_pump_plan"
require_relative "heat_pumps/reads"
require_relative "heat_pump_reads"
require_relative "declarations/heat_pumps"
require_relative "heat_pump_export"
require_relative "declarations/electric_heaters"
require_relative "electric_heater_plan"
require_relative "electric_heater_export"
require_relative "declarations/pumps"
require_relative "pump_plan"
require_relative "pump_export"
require_relative "segment/settings"
require_relative "segment/cooling"
require_relative "declarations/segment"
require_relative "segment_export"
require_relative "locate"
require_relative "preflight"
require_relative "colour_modes"

module PhComposer
  module Mechanical
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => %w[ph_composer.zones ph_composer.spaces
                                                             ph_composer.programs ph_composer.climate])
      ServesRegistration.install(feature)
      VentilatorRegistration.install(feature)
      HotWaterRegistration.install(feature)
      VentilationExport.install(feature)
      HotWaterExport.install(feature)
      HeatPumpRegistration.install(feature)
      HeatPumpExport.install(feature)
      ElectricHeaterRegistration.install(feature)
      ElectricHeaterExport.install(feature)
      PumpRegistration.install(feature)
      PumpExport.install(feature)
      SegmentRegistration.install(feature)
      SegmentExport.install(feature)
      Locate.install(feature)
      Preflight.install(feature)
      ColourModes.install(feature)
    end
  end
end
