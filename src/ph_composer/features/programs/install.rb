# frozen_string_literal: true

# One feature owns what a Zone's Program, occupancy and airtightness put in the energy model. Its first
# contribution is the Airtightness section of the Building Segment settings: a blower-door test result and a wind
# exposure stored as its structured extension on each Segment, the read other features take it from, and its
# export into each Room's Infiltration and the honeybee-ph BldgSegment. It requires Zones, which owns the Segment,
# its settings dialog and Save, Spaces, whose net volume an n50 result converts over, and Certification, which
# later Program stages read; no file of theirs names it (context/EXTENSIBILITY.md, "Building Segment settings").
#
#   airtightness.rb   the extension: its three fields, their values and defaults, and the read with defaults
#   conversion.rb     pure: a test result to the Infiltration flow PHX reads back as that result
#   export.rb         the export section: one record per exported Zone of a Segment with settings
#
# The panel half is html/features/programs/airtightness.js.
module PhComposer
  module Programs
    FEATURE_ID = "ph_composer.programs"
  end
end

require_relative "conversion"
require_relative "airtightness"
require_relative "export"

module PhComposer
  module Programs
    # The namespace takes `ph_composer.programs.airtightness`, so the read is `.airtightness.get`.
    READ = "#{FEATURE_ID}.airtightness.get"
    SEGMENT_ID = SchemaShapes.id("bsg", "The Building Segment.").freeze
    VALUES = SchemaShapes.object({
      "basis" => { "type" => "string", "enum" => Airtightness::BASES,
                   "description" => "n50 (air changes per hour) or q50 (m³/h per m² of envelope), at 50 Pa." },
      "value" => { "type" => %w[number null],
                   "description" => "The test result in the basis's unit; null when there is none." },
      "wind_exposure" => { "type" => "string", "enum" => Airtightness::WIND_EXPOSURES }
    }).freeze
    READ_RESULT = SchemaShapes.object({
      "id" => SEGMENT_ID,
      "values" => SchemaShapes.described(VALUES, "The three settings: the stored payload when it is understood, " \
                                                 "else the defaults."),
      "stored" => { "type" => "boolean", "description" => "Whether the values are a stored payload." },
      "extension_status" => { "type" => %w[string null],
                              "description" => "The stored envelope's status, as a record read reports it; null " \
                                               "when the Segment has none." }
    }).freeze
    CODES = {
      "airtightness.no_exposed_face" => "A Building Segment with an airtightness test result has no Outdoors or " \
                                        "Ground Face, so PHX would read no infiltration.",
      "airtightness.no_net_volume" => "A Building Segment with an n50 test result has no Space net volume to " \
                                      "convert it over."
    }.freeze

    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => ["ph_composer.zones", "ph_composer.spaces",
                                                           "ph_composer.certification"])
      CODES.each { |code, description| feature.code(code, :description => description) }
      feature.extension(Airtightness::EXTENSION)
      feature.query(READ, :description => "One Building Segment's airtightness settings, with the defaults where " \
                                          "it has none.",
                          :params => SchemaShapes.object({ "id" => SEGMENT_ID }), :result => READ_RESULT,
                          :refuses => %w[target.not_found record.unreadable],
                          :examples => [{ "id" => "bsg_Ab12Cd34Ef56" }]) do |request|
        Airtightness.read(request, request.params.fetch("id"))
      end
      AirtightnessExport.install(feature)
    end
  end
end
