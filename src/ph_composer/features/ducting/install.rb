# frozen_string_literal: true

# One feature owns ERV ducting, the two cold runs between each Ventilator and the outside: the Duct Type catalog, the
# Ducting groups that hold drawn ducts and the assignment on each duct, their runs and their export into
# the Ventilator's ventilation system. It requires Mechanical, which owns the Ventilator and its export, and Zones;
# no file of theirs, nor any other feature's, names it (context/EXTENSIBILITY.md, "Organization and dependencies").
#
#   type/           the Duct Type kind, its operations and reads; names no Edge, group or run
#   group/          the Ducting group record on a Group and its reference target
#   assignment/     the duct record on an Edge, its reference target, assign and the selection
#   line_group.rb   the spec the foundation's line_groups/ layer reads ducting by; create, link, clear, the type
#                   rewrite, the occurrence rows, the walk, schedule paging and Locate are that layer's
#   runs.rb         pure Ruby: runs by occurrence, direction, Duct Type and quantity, with no chain rule
#   findings.rb     pure Ruby: a run's findings and the Ventilators missing a run
#   schedule.rb     pure Ruby: the schedule's rows and totals, and its pages
#   scan.rb         the live read: the walk's ducts as facts, the schedule, the Ventilators' lengths and used length
#   extraction.rb   pure Ruby: the export's findings and its records, one per Ventilator with ducts
#   export.rb       the export contributor over the snapshot and its preflight over the live Model
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
require_relative "assignment/reference_target"
require_relative "assignment/operations"
require_relative "assignment/selection"
require_relative "runs"
require_relative "findings"
require_relative "schedule"
require_relative "scan"
require_relative "extraction"
require_relative "export"
require_relative "declarations/duct_types"
require_relative "declarations/groups"
require_relative "declarations/ducts"
require_relative "declarations/schedule"

module PhComposer
  module Ducting
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => %w[ph_composer.mechanical ph_composer.zones])
      DuctTypeRegistration.install(feature)
      GroupRegistration.install(feature)
      DuctRegistration.install(feature)
      ScheduleRegistration.install(feature)
      ExportProjection.install(feature)
      Codes.install(feature)
    end
  end
end
