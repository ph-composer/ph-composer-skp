# frozen_string_literal: true

module PhComposer
  module Spaces
    # The children and findings `list` answers as counts, each paged within the reply budget: one Space's
    # Volumes, one Space's or one Volume's Floor Segments, and the findings of the Model or one Space.
    # They read the same scan and metrics `all` does (Reads.assemble), so no read disagrees with another.
    # A scope reference resolves as a write's would, by path then id, and never by name.
    module ScopedReads
      VOLUMES = "#{FEATURE_ID}.volumes.list"
      FLOOR_SEGMENTS = "#{FEATURE_ID}.floor_segments.list"
      FINDINGS = "#{FEATURE_ID}.findings.list"
      CANDIDATE_FACES = "#{FEATURE_ID}.candidate_faces.list"
      CANDIDATE_FIELDS = %w[plan_area_m2 normal horizontal loops_m].freeze
      OPEN_SPACE = "The Space open for editing (ph_composer.spaces.context.open)."
      PATH = ->(row) { row.dig("reference", "entity_path") }

      module_function

      def volumes(request)
        rows, = Reads.assemble(request)
        space = located(rows, request.params.fetch("space"), "space_id", "Space")
        volumes = space.fetch("volumes").map { |volume| Summaries.volume(volume, request.params["fields"]) }
        page(request, VOLUMES, "volumes", volumes)
      end

      def floor_segments(request)
        rows, = Reads.assemble(request)
        params = request.params
        unless params.key?("space") ^ params.key?("volume")
          raise CodedError.new("params.invalid", "Name one Space or one Volume whose Floor Segments to read.")
        end

        volumes = if params.key?("space")
                    located(rows, params["space"], "space_id", "Space").fetch("volumes")
                  else
                    [located(scope_volumes(request, rows, params["volume"]), params["volume"], "volume_id", "Volume")]
                  end
        segments = volumes.flat_map { |volume| volume.fetch("floor_segments") }.sort_by(&PATH)
        segments = with_loops(request.model, segments) if Array(params["fields"]).include?("loops_m")
        page(request, FLOOR_SEGMENTS, "floor_segments",
             segments.map { |segment| Summaries.segment(segment, params["fields"]) })
      end

      # Each Floor Segment's loops in metres, read again from its Face only when `fields` asks for them.
      def with_loops(model, segments)
        faces = Occurrences.scan(model).segments.to_h { |segment| [segment.path, segment] }
        segments.map do |row|
          face = faces.fetch(PATH.call(row))
          row.merge("loops_m" => FaceCapture.call(face.entity, face.transform).loops_m)
        end
      end

      # Every Space's Volumes, and the Volume outside every Space the reference names when it is one.
      def scope_volumes(request, rows, reference)
        volumes = rows.flat_map { |row| row.fetch("volumes") }
        path = Resolve.integer_path(reference.fetch("entity_path"))
        volumes.any? { |volume| PATH.call(volume) == path } ? volumes : volumes + Reads.orphan_rows(request, path)
      end

      # Faces that have no record yet: directly inside a Volume, ready to mark as Floor Segments, or loose at
      # a Space's root, ready to group into a new Volume; each with the operation it is for and the
      # refusal that operation would give now. Reading stamps nothing and repairs nothing.
      def candidate_faces(request)
        scan = Occurrences.scan(request.model)
        params = request.params
        unless params.key?("space") ^ params.key?("volume")
          raise CodedError.new("params.invalid", "Name one Space or one Volume whose candidate Faces to read.")
        end

        faces = if params.key?("space")
                  space = Resolve.occurrence(scan, params["space"], :mutable => false)
                  scan.unmarked_faces.select { |face| face.space.equal?(space) || space.volumes.include?(face.volume) }
                else
                  volume = Resolve.occurrence(scan, params["volume"], :mutable => false)
                  scan.unmarked_faces.select { |face| face.volume.equal?(volume) }
                end
        rows = faces.sort_by(&:path).map { |face| candidate_row(scan, face, params["fields"]) }
        page, next_cursor = Pages.bounded(request, CANDIDATE_FACES, rows, :key => ->(row) { row["entity_path"] })
        { "candidate_faces" => page, "next_cursor" => next_cursor, "total" => rows.length }
      end

      def candidate_row(scan, face, fields)
        geometry = FaceCapture.call(face.entity, face.transform)
        operation, refusal = Eligibility.of(scan, face)
        row = { "entity_path" => face.path.dup, "candidate" => face.volume ? "floor" : "volume",
                "space" => face.space&.reference, "volume" => face.volume&.reference,
                "operation" => operation, "refusal" => refusal,
                "requires" => face.volume ? nil : OPEN_SPACE,
                "plan_area_m2" => Metrics.projected_area_m2(geometry.loops_m), "normal" => geometry.normal,
                "horizontal" => Metrics.horizontal?(geometry.normal), "loops_m" => geometry.loops_m }
        fixed = %w[entity_path candidate space volume operation refusal requires]
        row.slice(*(fixed + (fields || (CANDIDATE_FIELDS - ["loops_m"]))))
      end

      # Each finding with the reference of what it is about: a Space, Volume or Floor Segment, or a
      # record outside the hierarchy that should hold it. Ordered by that reference's path, then code.
      def findings(request)
        rows, _zones, strays = Reads.assemble(request)
        params = request.params
        if params.key?("space")
          space = located(rows, params["space"], "space_id", "Space")
          found = row_findings(space) + Summaries.inside(strays, PATH.call(space))
        else
          # An orphan Volume's stray finding is already among the strays; its own findings join it once.
          orphans = Reads.orphan_findings(request).reject { |finding| strays.include?(finding) }
          found = rows.flat_map { |row| row_findings(row) } + strays + orphans
        end
        found = found.select { |finding| params["codes"].include?(finding.fetch("code")) } if params.key?("codes")
        keyed = found.each_with_index.map { |finding, index| [finding_key(finding, index), finding] }.sort_by(&:first)
        page, next_cursor = Pages.bounded(request, FINDINGS, keyed, :key => ->(pair) { pair.first })
        { "findings" => page.map(&:last), "next_cursor" => next_cursor, "total" => found.length }
      end

      def row_findings(row)
        own = with_reference(row.fetch("findings"), row.fetch("reference"))
        own + row.fetch("volumes").flat_map do |volume|
          with_reference(volume.fetch("findings"), volume.fetch("reference")) +
            volume.fetch("floor_segments").flat_map do |segment|
              with_reference(segment.fetch("findings"), segment.fetch("reference"))
            end
        end
      end

      def with_reference(findings, reference)
        findings.map { |finding| finding.merge("reference" => reference) }
      end

      # The reference's path, zero-padded so it sorts as the paths do, then the code, then the order the
      # findings were found in, which keeps two equal findings distinct.
      def finding_key(finding, index)
        reference = finding.fetch("reference")
        path = reference["entity_path"] || []
        [path.map { |id| format("%012d", id) }.join("/"), finding.fetch("code"), format("%06d", index)].join("|")
      end

      def page(request, query, key, rows)
        page, next_cursor = Pages.bounded(request, query, rows, :key => PATH)
        { key => page, "next_cursor" => next_cursor, "total" => rows.length, "units" => Reads::UNITS }
      end

      # The row a scope reference names: the occurrence at its path, which must still carry its id.
      def located(rows, reference, id_key, label)
        path = Resolve.integer_path(reference.fetch("entity_path"))
        found = rows.find { |row| PATH.call(row) == path }
        raise CodedError.new("target.not_found", "That #{label} occurrence no longer exists.") unless found
        return found if found.fetch("id") == reference.fetch(id_key)

        raise CodedError.new("target.changed", "The #{label} identity has changed.")
      end
    end
  end
end
