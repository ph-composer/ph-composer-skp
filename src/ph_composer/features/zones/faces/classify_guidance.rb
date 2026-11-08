# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      # What the Classify tool's palette holds, in the words a user reads: the glossary's labels for
      # honeybee's face types and boundary conditions, and a record's name where the palette holds its
      # id. The status bar is on screen, so a record id never reaches it.
      module ClassifyGuidance
        NOUNS = { "face_type" => "face type", "boundary_condition" => "boundary",
                  "attached_zone_id" => "Attached zone", "assembly_id" => "Assembly" }.freeze
        LABELS = { "face_type" => ColourModes::FACE_TYPE_LABELS,
                   "boundary_condition" => ColourModes::BOUNDARY_LABELS }.freeze
        READS = { "assembly_id" => AssemblyAssignment::READ,
                  "attached_zone_id" => "#{PREFIX}.attached_zone.list" }.freeze
        UNKNOWN = "not found"

        module_function

        # One phrase per chosen field, in the palette's order: "face type Wall", "Assembly Roof R-40".
        def describe(context, palette)
          palette.map do |field, operation|
            "#{NOUNS.fetch(field) { field.tr('_', ' ') }} #{word(context, field, operation.fetch('value'))}"
          end
        end

        def word(context, field, value)
          return LABELS.fetch(field).fetch(value, value) if LABELS.key?(field)
          return value unless READS.key?(field)

          outcome = API.query(:context => context, :name => READS.fetch(field), :params => {})
          rows = outcome["status"] == "completed" ? Array(outcome.dig("value", "records")) : []
          row = rows.find { |candidate| candidate["id"] == value }
          (row && row.dig("values", "name")) || UNKNOWN
        end
      end
    end
  end
end
