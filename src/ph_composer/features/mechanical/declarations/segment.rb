# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What the Building Segment mechanical settings register: the extension on Zones' Segment record and the read of
    # one Segment's values with the defaults applied. Zones owns the settings dialog and its Save; the panel section
    # is html/features/mechanical/segment_settings.js and the export SegmentExport.
    module SegmentRegistration
      READ = "#{SegmentSettings::NAMESPACE}.get"
      SEGMENT_ID = SchemaShapes.id("bsg", "The Building Segment.").freeze
      VALUES = SchemaShapes.object({
        "mechanical_cooling" => { "type" => "boolean", "description" => "Whether the Segment has mechanical cooling." },
        "mech_room_temp_c" => { "type" => "number", "description" => "The mechanical room temperature, in C." },
        "summer_bypass_mode" => { "type" => "string", "enum" => SegmentSettings::BYPASS_MODES,
                                  "description" => "The ventilation heat exchanger's summer bypass." },
        "ventilation_system_ach" => { "type" => %w[number null], "minimum" => 0,
                                      "description" => "The ventilation system's summer air changes per hour; null " \
                                                       "for none entered." },
        "daytime_window_ach" => { "type" => "number", "minimum" => 0,
                                  "description" => "Daytime window ventilation air changes per hour." },
        "nighttime_window_ach" => { "type" => "number", "minimum" => 0,
                                    "description" => "Nighttime window ventilation air changes per hour." }
      }).freeze
      READ_RESULT = SchemaShapes.object({
        "id" => SEGMENT_ID,
        "values" => SchemaShapes.described(VALUES, "The six settings: the stored payload when it is understood, " \
                                                   "else the defaults."),
        "stored" => { "type" => "boolean", "description" => "Whether the values are a stored payload." },
        "extension_status" => { "type" => %w[string null],
                                "description" => "The stored envelope's status, as a record read reports it; null " \
                                                 "when the Segment has none." }
      }).freeze

      module_function

      def install(feature)
        feature.extension(SegmentSettings::EXTENSION)
        feature.query(READ, :description => "One Building Segment's mechanical settings (mechanical cooling, the " \
                                            "mechanical room temperature and summer ventilation), with the " \
                                            "defaults where it has none.",
                            :params => SchemaShapes.object({ "id" => SEGMENT_ID }), :result => READ_RESULT,
                            :refuses => %w[target.not_found record.unreadable],
                            :examples => [{ "id" => "bsg_Ab12Cd34Ef56" }]) do |request|
          SegmentSettings.read(request, request.params.fetch("id"))
        end
      end
    end
  end
end
