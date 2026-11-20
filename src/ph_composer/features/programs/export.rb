# frozen_string_literal: true

module PhComposer
  module Programs
    # The airtightness export section: one record per exported Zone whose Building Segment stores airtightness
    # settings, for the Python section that sets the Zone's Room Infiltration and its Segment's wind exposure
    # (python/ph_composer_translation/airtightness_sections.py). Ruby converts the test result
    # (`Conversion`); the translation takes the flow as given and computes nothing. A Segment with no test result
    # writes its wind exposure and leaves each Room's Infiltration to its Program, or to PHX's default; a Segment
    # with no settings writes no record, and its BldgSegment keeps honeybee-ph's defaults.
    #
    # The settings are this feature's extension on Zones' Segment records, so the section claims them on the
    # Segment kind (`entity_projections`), as the certification section does.
    module AirtightnessExport
      SECTION = "#{FEATURE_ID}.export.airtightness"
      ZONES = Zones::ExportProjection::SECTION
      FACES = Zones::Faces::ExportProjection::SECTION
      SPACES = Spaces::ExportProjection::SECTION
      CLAIM = { "namespace" => Airtightness::NAMESPACE, "target_kind" => Airtightness::SEGMENT_KIND,
                "source_section" => ZONES, "fields" => Airtightness::FIELDS }.freeze
      # PHX's exposed Faces, whose area weights each Room's flow in its merge of a Segment's Rooms.
      EXPOSED = %w[Outdoors Ground].freeze
      RESULT = { "airtightness" => [PhComposer::Export::Privacy.fields(
        %w[zone_id export_identifier wind_exposure flow_per_exterior_area]
      )] }.freeze

      # What PHX's merged Room of one Building Segment is bounded by: the gross area of every Face it keeps
      # (`gross_area_m2`, which n50 divides by), the part of it facing outdoors or the ground (`exposed_area_m2`)
      # and the net volume of its Spaces.
      Envelope = Struct.new(:gross_area_m2, :exposed_area_m2, :net_volume_m3, :keyword_init => true)

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :requires => [ZONES, FACES, SPACES],
                                            :result => RESULT, :entity_projections => [CLAIM]) do |reader|
          records(reader)
        end
      end

      # One record per exported Zone of a Building Segment with stored settings, in Zone id order.
      def records(reader)
        stored = reader.entity_projection(Airtightness::NAMESPACE, Airtightness::SEGMENT_KIND).to_h do |row|
          [row.fetch("id"), Airtightness.values(row.fetch("payload"))]
        end
        zones = reader.section(ZONES).select do |row|
          row.fetch("exported") && stored.key?(row.fetch("building_segment_id"))
        end
        flows = zones.map { |row| row.fetch("building_segment_id") }.uniq.sort.to_h do |id|
          [id, flow(reader, id, stored.fetch(id), zones)]
        end
        zones.map do |row|
          id = row.fetch("building_segment_id")
          values = stored.fetch(id)
          { "id" => row.fetch("zone_id"), "building_segment_id" => id,
            "export_identifier" => row.fetch("building_segment_export_identifier"),
            "basis" => values.fetch("basis"), "value" => values.fetch("value"),
            "wind_exposure" => values.fetch("wind_exposure"), "flow_per_exterior_area" => flows.fetch(id) }
        end.sort_by { |record| record.fetch("id") }
      end

      # The Segment's Infiltration flow per exterior area, or nil with no test result. Refuses when PHX could not
      # read the result back: a Segment with no Outdoors or Ground Face merges to no flow, and n50 needs an
      # envelope and a net volume.
      def flow(reader, id, values, zones)
        value = values.fetch("value")
        return nil if value.nil?

        members = zones.select { |row| row.fetch("building_segment_id") == id }
        envelope = envelope(reader, id, members)
        name = members.first.fetch("building_segment")
        unless envelope.exposed_area_m2.positive?
          raise Export::Blocked.new("airtightness.no_exposed_face",
                                    "Building Segment #{name} has an airtightness test result but no Outdoors or " \
                                    "Ground Face, so PHX would read no infiltration.")
        end
        if values.fetch("basis") == "n50" && !envelope.net_volume_m3.positive?
          raise Export::Blocked.new("airtightness.no_net_volume",
                                    "Building Segment #{name} has an n50 test result but no Space net volume to " \
                                    "convert it over. Add Spaces, or enter q50.")
        end

        q50 = Conversion.q50(values.fetch("basis"), value, :envelope_area_m2 => envelope.gross_area_m2,
                                                           :net_volume_m3 => envelope.net_volume_m3)
        Conversion.flow_per_exterior_area(q50)
      end

      # The Segment's envelope as PHX merges its Rooms (`Zones::Faces::ExportProjection.segment_envelope`) and the
      # net volume of its Zones' Spaces.
      def envelope(reader, id, members)
        volumes = reader.section(SPACES).to_h { |row| [row.fetch("zone_id"), row.fetch("net_volume_m3")] }
        zones = members.map { |row| Zones::ExportProjection.zone_entry(reader, row.fetch("zone_id")).first }
        faces = Zones::Faces::ExportProjection.segment_envelope(reader, zones, id)
        Envelope.new(:gross_area_m2 => faces.sum(0.0, &:area_m2),
                     :exposed_area_m2 => faces.select { |face| EXPOSED.include?(face.boundary_condition) }
                                              .sum(0.0, &:area_m2),
                     :net_volume_m3 => members.sum(0.0) { |row| volumes.fetch(row.fetch("zone_id"), 0.0) })
      end
    end
  end
end
