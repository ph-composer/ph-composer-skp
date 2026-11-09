# frozen_string_literal: true

# One feature owns Spaces: the rooms of a Zone, their Volumes and the Floor Segment Faces marked
# in them. It requires Zones and nothing else, and no Zones file names it.
#
#   schema.rb       the three entity-owned records and their stores
#   scan/           the walk, pure metrics (projected area, the any-set airflow rule, Zone sums) and findings
#   reads.rb        the list and panel reads
#   authoring.rb    the operations' handlers; steps.rb their native steps; scan/resolve.rb strict targets
#   create_faces.rb which Faces Create Space takes, from the open edit context
#   context/        Volume protection, the reconciler and the edit-context commands
#   identity/       Make independent: the pure plan and its step
#   copy_watch.rb   makes a native Space copy independent in the copy's own Undo step
#   zone_copy.rb    Spaces' part of a copied Zone becoming independent
#   settings.rb     the Model's last-entered height
#   colour_modes.rb the Spaces view's Colour-by modes
#   mark_tool.rb    the Mark floor viewport tool; declarations/mark_tool.rb its state and commands
#   set_height_tool.rb, prism_pick.rb  the Set Height viewport tool and its pure pointer maths
#   edit_floor_surface_menu.rb  the native route into a Volume's floor surface
#   declarations/   what Spaces registers
require_relative "schema"
require_relative "scan/occurrences"
require_relative "scan/membership"
require_relative "scan/metrics"
require_relative "prism"
require_relative "scan/findings"
require_relative "scan/extents"
require_relative "scan/floor_overlap"
require_relative "scan/zone_inference"
require_relative "scan/resolve"
require_relative "reads"
require_relative "summaries"
require_relative "eligibility"
require_relative "scoped_reads"
require_relative "steps"
require_relative "context/protection"
require_relative "context/navigation"
require_relative "context/reconciler"
require_relative "identity/plan"
require_relative "identity/step"
require_relative "copy_watch"
require_relative "zone_copy"
require_relative "create_faces"
require_relative "authoring"
require_relative "declarations/shapes"
require_relative "settings"
require_relative "declarations/spaces"
require_relative "declarations/operations"
require_relative "declarations/context"
require_relative "codes"
require_relative "colour_modes"
require_relative "readouts"
require_relative "export"
require_relative "mark_placement"
require_relative "mark_tool"
require_relative "declarations/mark_tool"
require_relative "create_route"
require_relative "height_from_solid"
require_relative "declarations/height_from_solid"
require_relative "height_from_solid_menu"
require_relative "prism_pick"
require_relative "set_height_tool"
require_relative "edit_floor_surface_menu"
require_relative "declarations/create_route"

module PhComposer
  module Spaces
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1, :requires => ["ph_composer.zones"])
      Registration.install(feature)
      OperationRegistration.install(feature)
      ContextRegistration.install(feature)
      CopyWatch.install(feature)
      ZoneCopy.install(feature)
      Settings.install(feature)
      Codes.install(feature)
      ColourModes.install(feature)
      Readouts.install(feature)
      ExportProjection.install(feature)
      MarkToolRegistration.install(feature)
      CreateRouteRegistration.install(feature)
      HeightFromSolidRegistration.install(feature)
      HeightFromSolidMenu.install(feature)
      SetHeightTool.install(feature)
      EditFloorSurfaceMenu.install(feature)
    end
  end
end
