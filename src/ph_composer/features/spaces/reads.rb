# frozen_string_literal: true

module PhComposer
  module Spaces
    # The Spaces reads: every Space with its Volumes and Floor Segments, each with its reference,
    # values, SI metrics, state and findings, and each Zone's sums. Reads never repair or allocate.
    module Reads
      ZONES_READ = "ph_composer.zones.all"
      UNITS = { "area" => "m2", "height" => "m", "volume" => "m3", "airflow" => "m3/h" }.freeze
      # A stray Volume's own findings that its stray finding already covers or that do not apply to it.
      ORPHAN_ASIDE = %w[space.duplicate_identity space.volume_nested].freeze

      module_function

      # Every Space occurrence, whole: the panel's projection. Scripts page `list` instead.
      def all(request)
        rows, zones, findings = assemble(request)
        totals(rows, zones).merge("spaces" => rows, "findings" => findings, "units" => UNITS)
      end

      # One bounded page of Space summaries in path order, optionally only some ids. The sums are taken
      # over every Space before any filter, so a page never changes them: the Model's, and those of the
      # Zones and Building-Segments the page's Spaces belong to. Children and findings have reads of their
      # own (ScopedReads).
      def list(request)
        rows, zones, strays = assemble(request)
        sums = totals(rows, zones)
        params = request.params
        chosen = params.key?("ids") ? rows.select { |row| params["ids"].include?(row.fetch("id")) } : rows
        whole = chosen.map { |row| Summaries.space(row, zones, nil, strays) }
        aggregates = PageAggregates.new(sums, whole)
        summaries = chosen.map { |row| Summaries.space(row, zones, params["fields"], strays) }
        page, next_cursor = Pages.bounded(request, "#{FEATURE_ID}.list", summaries,
                                          :key => PageAggregates::PATH, :size => aggregates.method(:size))
        { "spaces" => page, "model" => sums.fetch("model"), **aggregates.of(page),
          "stray_finding_count" => strays.length, "units" => UNITS, "next_cursor" => next_cursor,
          "total" => chosen.length }
      end

      # The Zone and Building-Segment sums a page names, chosen by each Space's membership whatever
      # `fields` projects away, and counted in the page's byte budget the first time a page names them.
      class PageAggregates
        PATH = ->(row) { row.dig("reference", "entity_path") }

        def initialize(sums, whole)
          @zones = sums.fetch("zones").to_h { |zone| [zone.fetch("zone_path"), Summaries.zone(zone)] }
          @segments = sums.fetch("building_segments").to_h { |row| [row.fetch("key"), row] }
          @membership = whole.to_h do |row|
            [PATH.call(row), [@zones[row.dig("zone", "zone_path")], @segments[row["building_segment"]]]]
          end
          @counted = {}
        end

        # A row's serialized size plus that of each aggregate it brings onto the page first.
        def size(row)
          fresh = @membership.fetch(PATH.call(row)).compact.reject { |aggregate| @counted[aggregate.object_id] }
          fresh.each { |aggregate| @counted[aggregate.object_id] = true }
          ([row] + fresh).sum { |item| JSON.generate(item).bytesize + 1 }
        end

        def of(page)
          zones, segments = page.map { |row| @membership.fetch(PATH.call(row)) }.transpose
          { "zones" => Array(zones).compact.uniq(&:object_id),
            "building_segments" => Array(segments).compact.uniq(&:object_id) }
        end
      end

      # The Building-Segment a Zone belongs to: the key its sums group by and the name they show.
      BuildingSegment = Struct.new(:key, :name, keyword_init: true)

      # Every Space row in path order, each Zone's row with its sums, and the findings of records outside
      # the hierarchy that should hold them. One scan and one metric calculation every Spaces read shares.
      def assemble(request)
        scan = Occurrences.scan(request.model)
        catalog = request.registry.catalog
        zones = request.query(ZONES_READ).fetch("zones").map do |zone|
          values = zone.fetch("values")
          { "zone_id" => zone.dig("reference", "zone_id"), "zone_path" => zone.dig("reference", "zone_path"),
            "name" => values["name"],
            :building_segment => BuildingSegment.new(
              :key => values["building_segment_id"] || values["building_segment"],
              :name => zone.dig("display", "building_segment") || values["building_segment"]
            ) }
        end
        ids = scan.spaces.map { |space| space.record.fetch("id") }.tally
        counts = occurrence_counts(scan)
        rows = scan.spaces.sort_by(&:path).map do |space|
          space_row(space, zones, ids, catalog, request.model, counts)
        end
        flag_duplicate_numbers(rows)
        [rows, zone_rows(zones, rows), stray_findings(scan, counts)]
      end

      # The row of the Volume outside every Space at `path`, if there is one, so its Floor Segments read by
      # reference. Built only when asked: `all` reports such a Volume as a stray finding and never
      # measures it.
      def orphan_rows(request, path)
        scan = Occurrences.scan(request.model)
        counts = occurrence_counts(scan)
        scan.orphan_volumes.select { |volume| volume.path == path }.map do |volume|
          volume_row(volume, request.registry.catalog, request.model, counts, false)
        end
      end

      # The findings of every Volume outside every Space and of its Floor Segments, each with its reference, for
      # the model-wide findings read. `all` reports such a Volume by its stray finding alone and never measures
      # it; a Volume that cannot be measured is left to that stray finding here too, never refusing the read.
      def orphan_findings(request)
        scan = Occurrences.scan(request.model)
        counts = occurrence_counts(scan)
        scan.orphan_volumes.sort_by(&:path).flat_map do |volume|
          row = volume_row(volume, request.registry.catalog, request.model, counts, false)
          # The stray finding already says when the Volume's identity is duplicated, in its own words, and a
          # Volume outside every Space is not nested in one, whatever the scan's `nested` flag says.
          own = referenced(row).reject { |finding| ORPHAN_ASIDE.include?(finding.fetch("code")) }
          own + row.fetch("floor_segments").flat_map { |segment| referenced(segment) }
        rescue CodedError
          []
        end
      end

      def referenced(row)
        row.fetch("findings").map { |finding| finding.merge("reference" => row.fetch("reference")) }
      end

      def occurrence_counts(scan)
        Resolve::TARGETS.transform_values do |target|
          target.occurrences_in(scan).map { |occurrence| occurrence.record.fetch("id") }.tally
        end
      end

      def space_row(space, zones, ids, catalog, model, counts)
        zone = Membership.zone_row(space.record, zones)
        repeated = space.shared_above
        volumes = space.volumes.sort_by(&:path).map { |volume| volume_row(volume, catalog, model, counts, repeated) }
        record = space.record
        row = Spaces.view(record).merge(
          "extension_status" => Records::Metadata.status_map(record, catalog), "reference" => space.reference,
          "zone" => zone && { "zone_id" => zone.fetch("zone_id"), "zone_path" => zone.fetch("zone_path") },
          "state" => state(space, ids), "nested" => !space.outer.nil?,
          "metrics" => Metrics.space(volumes.map do |volume|
            [volume.fetch("metrics"), volume.dig("values", "avg_ceiling_height_m")]
          end),
          "airflow_mode" => Metrics.airflow_mode(record), "airflows" => Metrics.airflows(record),
          "volumes" => volumes
        )
        row.merge("findings" => Findings.space(row, :duplicate => false) +
                                 duplicate(counts, SPACE_KIND, record, repeated))
      end

      def volume_row(volume, catalog, model, counts, repeated)
        segments = volume.segments.sort_by(&:path).map do |segment|
          segment_row(segment, catalog, counts, repeated, :copied_volume => !repeated && !volume.shared_above &&
                                                                          segment.shared_above)
        end
        row = Spaces.view(volume.record).merge(
          "extension_status" => Records::Metadata.status_map(volume.record, catalog),
          "reference" => volume.reference, "nested" => volume.nested,
          "open" => EditContext.current_ids(model)[0, volume.path.length] == volume.path,
          "protected" => volume.entity.locked?,
          "moved" => Navigation.moved?(model, volume),
          "metrics" => Metrics.volume(volume.record, segments.map { |segment| segment.fetch("metrics") }),
          "floor_segments" => segments
        )
        row.merge("findings" => Findings.volume(row) + duplicate(counts, VOLUME_KIND, volume.record, repeated,
                                                                 :ancestor => volume.shared_above && "Space"))
      end

      # `copied_volume` says the Face is shared because its Volume was copied: the Volume is the repair.
      def segment_row(segment, catalog, counts, repeated, copied_volume: false)
        geometry = FaceCapture.call(segment.entity, segment.transform)
        row = Spaces.view(segment.record).merge(
          "extension_status" => Records::Metadata.status_map(segment.record, catalog),
          "reference" => segment.reference,
          "metrics" => Metrics.segment(geometry.loops_m, geometry.normal, segment.record),
          "weighting_band" => ColourModes.band(segment.record.fetch("weighting_factor"))
        )
        row.merge("findings" => Findings.segment(row) +
                                 duplicate(counts, FLOOR_SEGMENT_KIND, segment.record, repeated,
                                           :ancestor => segment_owner(segment, copied_volume)))
      end

      # Where a copied Floor Segment is repaired: its Volume when that was copied, else its Space when the Face
      # is shared above it, else the Face itself.
      def segment_owner(segment, copied_volume)
        return "Volume" if copied_volume
        return "Space" if segment.shared_above

        nil
      end

      # A copy, or storage shared above the Space such as a single component placement: either way the
      # record has no identity of its own to export. `ancestor` names the container whose Make independent
      # repairs it ("Space" or "Volume"), when this record's storage is shared above it.
      def duplicate(counts, kind, record, repeated, ancestor: nil)
        return [] unless repeated || counts.fetch(kind).fetch(record.fetch("id")) > 1

        [Findings.duplicate(Resolve::TARGETS.fetch(kind).label, :repeated => repeated, :ancestor => ancestor)]
      end

      def state(space, ids)
        return "ambiguous" if ids.fetch(space.record.fetch("id")) > 1
        return "shared_definition" if space.shared

        "found"
      end

      # A number another Space in the same Zone carries is a warning on each of them.
      def flag_duplicate_numbers(rows)
        rows.group_by { |row| [row["zone"], row.dig("values", "number")] }.each do |(zone, number), group|
          next if zone.nil? || number.to_s.empty? || group.length < 2

          group.each do |row|
            row["findings"] = Findings.space(row, :duplicate => true) +
                              (row["findings"] - Findings.space(row, :duplicate => false))
          end
        end
      end

      def zone_rows(zones, rows)
        zones.map do |zone|
          spaces = rows.select { |row| row["zone"] && row.dig("zone", "zone_path") == zone.fetch("zone_path") }
          sums = Metrics.zone(spaces)
          zone.merge("space_count" => spaces.length).merge(sums)
        end
      end

      # The Zone rows, and the sums per Building-Segment and for the Model, over every Space whatever
      # page a list returns. A Space outside every Zone counts toward the Model only. The Symbol key marks
      # the Zone rows' BuildingSegment as internal: it groups the sums here and is left out of the read.
      def totals(rows, zones)
        segments = zones.group_by { |zone| zone.fetch(:building_segment).key }.map do |key, members|
          { "key" => key.to_s, "name" => members.first.fetch(:building_segment).name,
            "zone_count" => members.length }
            .merge(Metrics.sums(members, Metrics::TOTALS))
        end
        { "zones" => zones.map { |zone| zone.reject { |key, _value| key == :building_segment } },
          "building_segments" => segments,
          "model" => Metrics.sums(rows.map { |row| row.fetch("metrics") }, Metrics::TOTALS) }
      end

      def stray_findings(scan, counts)
        strays = scan.orphan_volumes.map { |volume| [VOLUME_KIND, volume, Findings.orphan_volume] } +
                 scan.misplaced_segments.map { |segment| [FLOOR_SEGMENT_KIND, segment, Findings.misplaced_segment] }
        strays.flat_map do |kind, occurrence, finding|
          ([finding] + duplicate(counts, kind, occurrence.record, occurrence.shared_above)).map do |item|
            item.merge("reference" => occurrence.reference)
          end
        end
      end
    end
  end
end
