# frozen_string_literal: true

# One feature owns Zones, their Faces and the adjacency between them: Zone containment, Face identity,
# stamps, Surface endpoints and safe split and copy transitions are one authoring lifecycle.
#
#   zone/          Zone schema, occurrences, index, Make and Edit steps, repairs
#   faces/         Face and Attached-zone schema, Classify and Reverse steps, suggestions, the Classify
#                  tool and menu, Locate, the Face reference inventory
#   adjacency/     pure overlap and pair rules, Face splitting, the native split and pair steps
#   declarations/  what each part registers: descriptors, schemas, queries, actions, participants
#   export.rb      the Zone projection; faces/export.rb is the Face projection
#
# Pure geometry and pair validation stay apart from the SketchUp write steps.
require_relative "zone/schema"
require_relative "options/definitions"
require_relative "zone/names"
require_relative "zone/occurrences"
require_relative "zone/index"
require_relative "zone/steps"
require_relative "faces/schema"
require_relative "faces/settings"
require_relative "faces/reference_targets"
require_relative "faces/geometry"
require_relative "faces/attached_zone"
require_relative "faces/steps"
require_relative "faces/export"
require_relative "faces/colour_modes"
require_relative "faces/classify_tool"
require_relative "faces/classify_menu"
require_relative "faces/locate_highlight"
require_relative "faces/locate"
require_relative "faces/operations"
require_relative "faces/attached_zone_operations"
require_relative "faces/assembly_assignment"
require_relative "faces/classify_guidance"
require_relative "adjacency/overlap"
require_relative "adjacency/adjacency"
require_relative "adjacency/face_split"
require_relative "adjacency/adjacency_steps"
require_relative "adjacency/operations"
require_relative "zone/repair"
require_relative "zone/split_identity_repair"
require_relative "zone/split_identity_menu"
require_relative "zone/independence_menu"
require_relative "zone/copied_groups"
require_relative "zone/copy_watch"
require_relative "zone/operations"
require_relative "zone/menu"
require_relative "zone/selection"
require_relative "faces/selection"
require_relative "export"
require_relative "colour_modes"
require_relative "refuses"
require_relative "declarations/shapes"
require_relative "declarations/zone"
require_relative "declarations/assembly_assignment"
require_relative "declarations/faces"
require_relative "declarations/adjacency"
require_relative "declarations/repair"
require_relative "declarations/selection"
require_relative "options/inventory"
require_relative "options/adoption"
require_relative "options/operations"
require_relative "options/registration"
require_relative "options/commands"
require_relative "codes"
require_relative "refuses"

module PhComposer
  module Zones
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => Declarations::CONTRACT_VERSION,
                                             :requires => ["ph_composer.assemblies"])
      Options::Registration.install(feature)
      Options::CommandRegistration.install(feature)
      ZoneRegistration.install(feature)
      Names.install(feature)
      CopyWatch.install(feature)
      ZoneMenu.install(feature)
      SelectionRegistration.install(feature)
      Faces::Registration.install(feature)
      Faces::AssemblyRegistration.install(feature)
      Faces::Settings.install(feature)
      AdjacencyRegistration.install(feature)
      ExportProjection.install(feature)
      RepairRegistration.install(feature)
      Codes.install(feature)
    end
  end
end
