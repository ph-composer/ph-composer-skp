# frozen_string_literal: true

# A definitions feature: pure schemas and calculations, commands over detached records, then
# registered handlers. Persistence and native transactions belong to the supplied engine/dispatcher.
require_relative "../../core/records/authoring_fields"

module PhComposer
  module Assemblies
    FEATURE_ID = "ph_composer.assemblies"
    MATERIAL_KIND = "#{FEATURE_ID}.material"
    ASSEMBLY_KIND = "#{FEATURE_ID}.assembly"
    Fields = Records::AuthoringFields
  end
end

require_relative "materials/schema"
require_relative "assembly/schema"
require_relative "thermal"
require_relative "message_parts"
require_relative "validation"
require_relative "commands/change"
require_relative "commands/assembly"
require_relative "commands/material"
require_relative "commands/layers"
require_relative "snapshot"
require_relative "definitions"
require_relative "materials/operations"
require_relative "assembly/operations"
require_relative "export"
require_relative "source_report"
require_relative "declarations/shapes"
require_relative "declarations/inventories"
require_relative "declarations/records"
require_relative "declarations/layers"
require_relative "declarations/segments"
require_relative "declarations/parts"
require_relative "library_kind"
require_relative "codes"
require_relative "refuses"

module PhComposer
  module Assemblies
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => Declarations::CONTRACT_VERSION)
      feature.record_kind(Materials::Schema::KIND)
      feature.record_kind(Assembly::Schema::KIND)
      InventoryRegistration.install(feature)
      RecordRegistration.install(feature)
      LayerRegistration.install(feature)
      SegmentRegistration.install(feature)
      PartRegistration.install(feature)
      MaterialsLibrary.install(feature)
      ExportProjection.install(feature)
      SourceReport.install(feature)
      Codes.install(feature)
    end
  end
end
