# frozen_string_literal: true

module PhComposer
  module Mechanical
    # `ph_composer.mechanical.preflight`: every mechanical export section's checks over the live Model, one query the
    # Ventilator export names for the whole feature (the export pane runs each contributor's named preflight once). It
    # reads the Zones once through Serves and gives each family's rows (VentilationExport, HotWaterExport), each with
    # the section, code and object its export notes, so a run lists a finding once. An exported Zone whose Serves
    # payload this version does not understand comes first, since the claim stops the export on it. A read that
    # refuses answers one blocking row, since the export would stop on the same cause.
    module Preflight
      NAME = "#{FEATURE_ID}.preflight"
      FAMILIES = [VentilationExport, HotWaterExport].freeze

      module_function

      def install(feature)
        feature.query(NAME, :description => "Mechanical export checks: a Zone naming an item that is not in the " \
                                            "Model (blocking), a Zone with no Ventilator or no Hot Water System, an " \
                                            "item serving no Zone, a served Zone in no Building Segment, an item " \
                                            "serving Zones in two Building Segments, a Tank with no free slot and " \
                                            "Hot Water Systems pooled in one Building Segment.",
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
        row(code, VentilationExport::SECTION, zone.id, "What serves Zone #{zone.name || zone.id} is #{zone.status}, " \
                                                       "so the Model cannot be exported.", true,
            zone_locate(zone.id, zone.id => zone.reference))
      end

      # A Zone's finding opens the Zones tab with it checked; any other object has no Locate here.
      def zone_locate(object_id, references)
        reference = references[object_id]
        reference && { "name" => VentilationExport::LOCATE,
                       "params" => { "zones" => [reference.slice("zone_id", "zone_path")] } }
      end

      def row(code, section, object_id, message, blocks, locate = nil)
        found = { "code" => code, "section" => section, "object_id" => object_id, "message" => message,
                  "blocks_export" => blocks }
        locate ? found.merge("locate" => locate) : found
      end
    end
  end
end
