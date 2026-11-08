# frozen_string_literal: true

module PhComposer
  module Spaces
    # The bounded rows the paged Spaces reads answer with, cut from the whole rows `Reads.assemble`
    # builds, so every read shares one scan and one metric calculation. A summary carries its children
    # and findings as counts; the scoped reads (ScopedReads) answer the children themselves.
    #
    # `fields` names what a row carries beyond its identity (`id`, `schema_version`, `reference`); absent,
    # a row carries the default fields and never the metadata (`user_data`, `extension_data`,
    # `extension_status`) or a Floor Segment's loops, which can be large.
    module Summaries
      METADATA = %w[user_data extension_data extension_status].freeze
      SPACE_FIELDS = (%w[values metrics zone building_segment state nested airflow_mode airflows volume_count
                         floor_segment_count finding_counts] + METADATA).freeze
      VOLUME_FIELDS = (%w[values metrics nested open protected moved floor_segment_count findings] + METADATA).freeze
      LOOPS = %w[loops_m].freeze
      SEGMENT_FIELDS = (%w[values metrics weighting_band findings] + LOOPS + METADATA).freeze
      IDENTITY = %w[id schema_version reference].freeze

      module_function

      # `strays` are the findings of records outside the hierarchy; those inside this Space count here, as
      # its scoped findings read returns them.
      def space(row, zones, fields, strays)
        volumes = row.fetch("volumes")
        segments = volumes.flat_map { |volume| volume.fetch("floor_segments") }
        findings = row.fetch("findings") + volumes.flat_map { |volume| volume.fetch("findings") } +
                   segments.flat_map { |segment| segment.fetch("findings") } +
                   inside(strays, row.dig("reference", "entity_path"))
        zone = row["zone"] && zones.find { |candidate| candidate.fetch("zone_path") == row.dig("zone", "zone_path") }
        whole = row.reject { |key, _value| %w[volumes findings].include?(key) }.merge(
          "building_segment" => zone && zone.fetch(:building_segment).key.to_s,
          "volume_count" => volumes.length, "floor_segment_count" => segments.length,
          "finding_counts" => findings.map { |finding| finding.fetch("code") }.tally
        )
        project(whole, fields, SPACE_FIELDS)
      end

      # The findings whose reference lies under the occurrence at `path`.
      def inside(findings, path)
        findings.select { |finding| finding.dig("reference", "entity_path")&.first(path.length) == path }
      end

      def volume(row, fields)
        whole = row.reject { |key, _value| key == "floor_segments" }
                   .merge("floor_segment_count" => row.fetch("floor_segments").length)
        project(whole, fields, VOLUME_FIELDS)
      end

      def segment(row, fields)
        project(row, fields, SEGMENT_FIELDS)
      end

      # A Zone's sums without its airflow detail, which `all` keeps for the panel.
      def zone(row)
        row.slice("zone_id", "zone_path", "name", "space_count", "floor_area_m2", "weighted_area_m2",
                  "net_volume_m3")
      end

      def project(row, fields, allowed)
        row.slice(*(IDENTITY + (fields || (allowed - METADATA - LOOPS))))
      end
    end
  end
end
