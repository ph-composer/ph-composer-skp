# frozen_string_literal: true

# One feature owns Phius certification: the Phius certification section of the Building Segment settings, stored
# as its structured extension on each Segment, the read other features take it from, and its export to the
# honeybee-ph BldgSegment. It requires Zones, which owns the Segment, its settings dialog and Save; no Zones file
# names it (context/EXTENSIBILITY.md, "Building Segment settings").
#
#   segment.rb   the extension: its five fields, their values and defaults, and the read with defaults applied
#   export.rb    the export section: one record per exported Building Segment
#
# The panel half is html/features/certification/section.js.
module PhComposer
  module Certification
    FEATURE_ID = "ph_composer.certification"
  end
end

require_relative "segment"
require_relative "export"

module PhComposer
  module Certification
    # The namespace takes `ph_composer.certification.segment`, so the read is `.segment.get`.
    READ = "#{FEATURE_ID}.segment.get"
    SEGMENT_ID = SchemaShapes.id("bsg", "The Building Segment.").freeze
    VALUES = SchemaShapes.object(Segment::CHOICES.to_h do |field, values|
      [field, { "type" => "string", "enum" => values }]
    end).freeze
    READ_RESULT = SchemaShapes.object({
      "id" => SEGMENT_ID,
      "values" => SchemaShapes.described(VALUES, "The five settings: the stored payload when it is understood, " \
                                                 "else the defaults."),
      "stored" => { "type" => "boolean", "description" => "Whether the values are a stored payload." },
      "extension_status" => { "type" => %w[string null],
                              "description" => "The stored envelope's status, as a record read reports it; null " \
                                               "when the Segment has none." }
    }).freeze

    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1, :requires => ["ph_composer.zones"])
      feature.extension(Segment::EXTENSION)
      feature.query(READ, :description => "One Building Segment's Phius certification settings, with the defaults " \
                                          "where it has none.",
                          :params => SchemaShapes.object({ "id" => SEGMENT_ID }), :result => READ_RESULT,
                          :refuses => %w[target.not_found record.unreadable],
                          :examples => [{ "id" => "bsg_Ab12Cd34Ef56" }]) do |request|
        Segment.read(request, request.params.fetch("id"))
      end
      SegmentExport.install(feature)
    end
  end
end
