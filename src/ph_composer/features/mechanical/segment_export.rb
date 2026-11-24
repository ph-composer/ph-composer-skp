# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The Building Segment mechanical settings export: one record per exported Building Segment, for the Python
    # section that sets its honeybee-ph BldgSegment's mechanical cooling, mechanical room temperature and summer
    # ventilation (python/ph_composer_translation/mechanical_segment_sections.py). The settings are this feature's
    # extension on Zones' Segment records, so the section claims them on the Segment kind (`entity_projections`);
    # Zones' section reads each Segment and hands over the claimed fields of the ones an exported Zone names. A
    # Segment with no settings exports the defaults, written out rather than left to honeybee-ph's (context/
    # EXTENSIBILITY.md, "Building Segment settings").
    #
    # It also compares each Segment's switch with its blended heat pump (SegmentSettings::Cooling) and notes where
    # they disagree; the preflight gives the same rows over the live Model (`preflight_rows`).
    module SegmentExport
      SECTION = "#{FEATURE_ID}.export.segments"
      ZONES = Zones::ExportProjection::SECTION
      CLAIM = { "namespace" => SegmentSettings::NAMESPACE, "target_kind" => SegmentSettings::SEGMENT_KIND,
                "source_section" => ZONES, "fields" => SegmentSettings::FIELDS }.freeze
      # What the Python section reports for conformance: each Segment's values as it set them.
      RESULT = { "building_segments" => [PhComposer::Export::Privacy.fields(%w[export_identifier] +
                                                                              SegmentSettings::FIELDS)] }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :requires => [ZONES, HeatPumpExport::SECTION],
                                            :result => RESULT, :entity_projections => [CLAIM],
                                            :projection => method(:segments)) do |reader|
          records(reader)
        end
      end

      # One record per exported Building Segment record, in export identifier order (which follows from its name, so
      # the order holds from one Model to the next), with the mismatch notes. A legacy Zone names
      # no Segment record, so its BldgSegment keeps honeybee-ph's defaults, which are the same values.
      def records(reader)
        rows = segments(reader)
        cooling = reader.section(HeatPumpExport::SECTION).to_h { |row| row.values_at("segment", "cooling") }
        SegmentSettings::Cooling.findings(rows, cooling).each do |found|
          reader.note(found.code, found.record_id, found.message)
        end
        rows
      end

      # Each exported Segment's id, export identifier, name and six values: the records without the notes, and the
      # section's projection, so a feature that requires this one reads each Segment's settings as exported.
      def segments(reader)
        stored = reader.entity_projection(SegmentSettings::NAMESPACE, SegmentSettings::SEGMENT_KIND).to_h do |row|
          [row.fetch("id"), row.fetch("payload")]
        end
        exported = reader.section(ZONES).select { |row| row.fetch("exported") && row.fetch("building_segment_id") }
        keys = %w[building_segment_id building_segment_export_identifier building_segment]
        exported.map { |row| row.values_at(*keys) }.uniq.sort_by { |id, identifier, _name| [identifier, id] }
                .map do |id, export_identifier, name|
          { "id" => id, "export_identifier" => export_identifier, "name" => name }
            .merge(SegmentSettings.values(stored[id]))
        end
      end

      # The preflight's rows: each exported Segment's switch against the live heat pump plan's blends, with the code
      # and object the export notes. `zones` are the live ExportZones; `references` is the family signature's and
      # names Zones, not Segments, so these rows carry no locate. A Segment whose payload this version does not
      # understand is left out: the metadata check blocks the export on it, and its stored switch is unknown. A read
      # that refuses (a Segment record, the heat pumps) gives no rows here, since its owner's check reports it.
      def preflight_rows(request, zones, _references)
        segments = zones.select(&:exported).filter_map { |zone| zone.segment_id && [zone.segment_id, zone.segment] }
        rows = segments.uniq.sort.filter_map do |id, name|
          payload, status = SegmentSettings.stored(request, request.engine.find(SegmentSettings::SEGMENT_KIND, id))
          next unless status.nil? || payload

          { "id" => id, "name" => name }.merge(SegmentSettings.values(payload))
        end
        SegmentSettings::Cooling.findings(rows, live_cooling(request, zones)).map do |found|
          Preflight.row(found.code, SECTION, found.record_id, found.message, found.blocks)
        end
      rescue CodedError
        []
      end

      # Each live blend's Segment name and whether it cools.
      def live_cooling(request, zones)
        HeatPumpExport.live_plan(request, zones).blends.to_h do |blend|
          [blend.fetch("segment"), blend.fetch("result").fetch("export").fetch("cooling").fetch("used")]
        end
      end
    end
  end
end
