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
      DETAIL = "#{FEATURE_ID}.detail"
      SCOPES = { "space" => %w[space_id Space], "volume" => %w[volume_id Volume],
                 "floor_segment" => ["floor_segment_id", "Floor Segment"] }.freeze
      CANDIDATE_FIELDS = %w[plan_area_m2 normal horizontal loops_m].freeze
      OPEN_SPACE = "The Space open for editing (ph_composer.spaces.context.open)."
      OPEN_CONTEXT = "This context open for editing (ph_composer.context.open with its path): Create Space takes " \
                     "Faces loose in the open edit context."
      CREATE = "#{FEATURE_ID}.create".freeze
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

      # One part of one Space's, Volume's or Floor Segment's row as `all` builds it, exactly, in fragments
      # (shell/fragments.rb): what a page cannot hold, such as a Floor Segment's loops_m over hundreds of holes
      # or large user_data. The reference resolves as the scoped reads resolve it.
      def detail(request)
        params = request.params
        named = SCOPES.keys.select { |key| params.key?(key) }
        raise CodedError.new("params.invalid", "Name one Space, Volume or Floor Segment.") unless named.length == 1

        rows, = Reads.assemble(request)
        scope = named.first
        reference = params.fetch(scope)
        id_key, label = SCOPES.fetch(scope)
        row = case scope
              when "space" then located(rows, reference, id_key, label)
              when "volume" then located(scope_volumes(request, rows, reference), reference, id_key, label)
              else segment_row(request, rows, reference, id_key, label)
              end
        Fragments.detail(request, DETAIL, row, params.fetch("path"), :parts => row.keys - Summaries::IDENTITY)
      end

      # A Floor Segment's row with its loops, from the Volume its path names.
      def segment_row(request, rows, reference, id_key, label)
        volume = { "entity_path" => Resolve.integer_path(reference.fetch("entity_path"))[0...-1] }
        segments = scope_volumes(request, rows, volume).flat_map { |row| row.fetch("floor_segments") }
        with_loops(request.model, [located(segments, reference, id_key, label)]).first
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
        params = request.params
        unless %w[space volume context].count { |key| params.key?(key) } == 1
          raise CodedError.new("params.invalid", "Name one Space, one Volume or one context whose candidate Faces " \
                                                 "to read.")
        end
        return context_candidates(request) if params.key?("context")

        scan = Occurrences.scan(request.model)

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

      # The Faces loose in one edit context, the root or a plain Group or a Zone's own context, for a first
      # Space: each with the refusal Create Space gives it named alone with that context open (CreateFaces.read,
      # the action's own rule), and what to open first when it is not. Only the page's Faces are judged.
      def context_candidates(request)
        model = request.model
        container = OccurrencePath.resolve(model, request.params.fetch("context"))
        faces = container.entities.to_a.grep(Sketchup::Face).map { |face| container.path + [face.persistent_id] }.sort
        open = Array(model.active_path).map(&:persistent_id) == container.path
        blocked = ContextCommands.open_refusal(model, container.path) unless open
        build = lambda do |paths|
          next [] if paths.empty?

          found = CreateFaces.read(request, paths, :context => container.instances, :alone => true)
          refusals = found.left_out.to_h { |row| [row.fetch("path"), row] }
          paths.map do |path|
            left_out = blocked ? { "reason" => blocked.code, "message" => blocked.message } : refusals[path]
            context_row(Occurrences.entity_at(model, path), path, left_out, container.transform, open,
                        request.params["fields"])
          end
        end
        page, next_cursor = Pages.bounded(request, CANDIDATE_FACES, faces, :key => ->(path) { path },
                                                                           :prepare => build)
        { "candidate_faces" => page, "next_cursor" => next_cursor, "total" => faces.length }
      end

      def context_row(face, path, left_out, transform, open, fields)
        geometry = FaceCapture.call(face, transform)
        row = { "entity_path" => path, "candidate" => "space", "space" => nil, "volume" => nil,
                "operation" => CREATE, "refusal" => left_out && { "code" => left_out.fetch("reason"),
                                                                  "message" => left_out.fetch("message") },
                "requires" => open ? nil : OPEN_CONTEXT, "hidden" => OccurrencePath.hidden?(face),
                "plan_area_m2" => Metrics.projected_area_m2(geometry.loops_m), "normal" => geometry.normal,
                "horizontal" => Metrics.horizontal?(geometry.normal), "loops_m" => geometry.loops_m }
        fixed = %w[entity_path candidate space volume operation refusal requires hidden]
        row.slice(*(fixed + (fields || (CANDIDATE_FIELDS - ["loops_m"]))))
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
