# frozen_string_literal: true

# One feature owns thermal bridges: the Thermal Bridge Type catalog and, on Edges inside a Zone, the
# assignments that name a type. It requires Zones, and no Zones file names it.
#
#   type/           the Thermal Bridge Type kind, its operations and reads; names no Edge, Zone or run
#   assignment/     the record on an Edge, its reference target, assign, clear and the selection read
#   runs/           pure Ruby: chains of assigned Edges, the schedule and its findings, over detached facts
#   scan/           the live read: one walk for assigned Edges, Zones' answers for their paths, the schedule
#   run_locate.rb   runs.locate, which selects a run's Edges through the foundation's context.open
#   codes.rb        the codes under the thermal_bridge noun
#   declarations/   what thermal bridges register
require_relative "type/schema"
require_relative "type/operations"
require_relative "type/reads"
require_relative "assignment/schema"
require_relative "assignment/reference_target"
require_relative "assignment/steps"
require_relative "assignment/operations"
require_relative "assignment/selection"
require_relative "runs/chains"
require_relative "runs/findings"
require_relative "runs/schedule"
require_relative "scan/occurrences"
require_relative "run_locate"
require_relative "declarations/shapes"
require_relative "declarations/types"
require_relative "declarations/assignment"
require_relative "declarations/schedule"
require_relative "codes"

module PhComposer
  module ThermalBridges
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1, :requires => ["ph_composer.zones"])
      TypeRegistration.install(feature)
      AssignmentRegistration.install(feature)
      ScheduleRegistration.install(feature)
      Codes.install(feature)
    end
  end
end
