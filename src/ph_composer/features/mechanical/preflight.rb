# frozen_string_literal: true

module PhComposer
  module Mechanical
    # `ph_composer.mechanical.preflight`: every mechanical export section's checks over the live Model, one query the
    # Ventilator export names for the whole feature (the export pane runs each contributor's named preflight once). It
    # reads the Zones once through Serves and gives each family's rows (VentilationExport, HotWaterExport,
    # HeatPumpExport, ElectricHeaterExport, PumpExport, FanExport, SegmentExport), each with
    # the section, code and object its export notes, so a run lists a finding once. An exported Zone whose Serves
    # payload this version does not understand comes first, since the claim stops the export on it. A read that
    # refuses answers one blocking row, since the export would stop on the same cause.
    module Preflight
      NAME = "#{FEATURE_ID}.preflight"
      FAMILIES = [VentilationExport, HotWaterExport, HeatPumpExport, ElectricHeaterExport, PumpExport, FanExport,
                  SegmentExport].freeze

      module_function

      def install(feature)
        feature.query(NAME, :description => "Mechanical export checks: a Zone naming an item that is not in the " \
                                            "Model (blocking), a Zone with no Ventilator or no Hot Water System, an " \
                                            "item serving no Zone, a served Zone in no Building Segment, an item " \
                                            "serving Zones in two Building Segments, a Tank with no free slot, " \
                                            "Hot Water Systems pooled in one Building Segment, and the heat pump " \
                                            "blend's: a climate it cannot read, an unpaired unit, an incomplete " \
                                            "outdoor model and cooling over 200 kW; a Pump, a Fan or an Electric " \
                                            "Heater serving a Zone with no Spaces; and a Building Segment whose " \
                                            "mechanical cooling switch disagrees with its blended heat pump.",
                            :refuses => [], :params => Shapes::NONE,
                            :result => PhComposer::Export::PREFLIGHT_RESULT, :examples => [{}]) do |request|
          call(request)
        end
      end

      def call(request)
        serves = Serves::State.zones(request).sort_by { |zone| zone.reference.fetch("zone_path") }.uniq(&:id)
        references = serves.to_h { |zone| [zone.id, zone.reference] }
        zones = ExportZones.live(serves)
        rows = serves.filter_map { |zone| payload_row(zone) }
        FAMILIES.each { |family| rows.concat(family_rows(request, family, zones, references)) }
        { "findings" => rows, "repairs" => [] }
      rescue CodedError => error
        { "findings" => [row(error.code, VentilationExport::SECTION, nil, error.message, true)], "repairs" => [] }
      end

      # One family's rows; a read of its own that refuses is one blocking row under its section, and the other
      # families' rows stand.
      def family_rows(request, family, zones, references)
        family.preflight_rows(request, zones, references)
      rescue CodedError => error
        [row(error.code, family::SECTION, nil, error.message, true)]
      end

      # The claim refuses an exported Zone's payload this version does not understand, with the code the metadata
      # check gives it (Export::MetadataCheck.payload_problem).
      def payload_row(zone)
        return nil if zone.left_out || zone.status.nil? || zone.status == "understood"

        code = { "unavailable" => "extension.unavailable", "invalid" => "extension.invalid" }
               .fetch(zone.status, "extension.schema_unsupported")
        named = Records::Names.titled("Zone", zone.name, zone.id)
        row(code, VentilationExport::SECTION, zone.id, "What serves #{named} is #{zone.status}, so the Model cannot " \
                                                       "be exported.", true,
            Locate.row_locate(zone.id, zone.id => zone.reference))
      end

      def row(code, section, object_id, message, blocks, locate = nil)
        found = { "code" => code, "section" => section, "object_id" => object_id, "message" => message,
                  "blocks_export" => blocks }
        locate ? found.merge("locate" => locate) : found
      end
    end
  end
end
