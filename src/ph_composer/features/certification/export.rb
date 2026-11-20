# frozen_string_literal: true

module PhComposer
  module Certification
    # The Phius certification export section: one record per exported Building Segment, for the Python section
    # that sets its honeybee-ph BldgSegment's `phius_certification` (python/ph_composer_translation/
    # certification_sections.py). The settings are this feature's extension on Zones' Segment records, so the
    # section claims them on the Segment kind (`entity_projections`); Zones' section reads each Segment and
    # hands over the claimed fields of the ones an exported Zone names. Its own projection names the exported
    # Segments and the export identifier each becomes in the HBJSON. A Segment with no settings exports the
    # defaults, written out rather than left to honeybee-ph's.
    module SegmentExport
      SECTION = "#{FEATURE_ID}.export.segments"
      ZONES = Zones::ExportProjection::SECTION
      CLAIM = { "namespace" => Segment::NAMESPACE, "target_kind" => Segment::SEGMENT_KIND,
                "source_section" => ZONES, "fields" => Segment::FIELDS }.freeze
      # What the Python section reports for conformance: each Segment's values as it set them.
      RESULT = { "building_segments" => [PhComposer::Export::Privacy.fields(%w[export_identifier] +
                                                                              Segment::FIELDS)] }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :requires => [ZONES], :result => RESULT,
                                            :entity_projections => [CLAIM]) { |reader| records(reader) }
      end

      # One record per exported Building Segment record, in id order. A legacy Zone names no Segment record, so
      # its BldgSegment keeps honeybee-ph's defaults, which are the same values.
      def records(reader)
        stored = reader.entity_projection(Segment::NAMESPACE, Segment::SEGMENT_KIND).to_h do |row|
          [row.fetch("id"), row.fetch("payload")]
        end
        exported = reader.section(ZONES).select { |row| row.fetch("exported") && row.fetch("building_segment_id") }
        exported.map { |row| row.values_at("building_segment_id", "building_segment_export_identifier") }
                .uniq.sort.map do |id, export_identifier|
          { "id" => id, "export_identifier" => export_identifier }.merge(Segment.values(stored[id]))
        end
      end
    end
  end
end
