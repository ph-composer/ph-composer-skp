# frozen_string_literal: true

require "set"

module PhComposer
  module ThermalBridges
    # The live read behind the schedule. It walks the Model once for assigned Edges and asks Zones, through
    # its published reads, which Zone holds each one and how each Edge's Faces are classified. It opens no
    # operation and writes nothing.
    module Scan
      CONTAINMENT = "ph_composer.zones.containment"
      HOST_CONTEXT = "ph_composer.zones.faces.host_context"
      # One assigned Edge as the walk finds it, before Zones has answered for its path. `edge` and `transform`,
      # which maps its container's contents to world, stay live for a reader that draws or selects it.
      Tagged = Struct.new(:path, :record, :points_m, :vertex_ids, :face_ids, :shared, :edge, :transform,
                          keyword_init: true)

      # Edge findings and unreadable assignments a bounded page lists, beside a count of every one.
      DETAIL_ROWS = 50
      LIST = "#{FEATURE_ID}.schedule.list".freeze
      MEMBERS = "#{FEATURE_ID}.runs.members.list".freeze
      EDGE_FINDINGS = "#{FEATURE_ID}.schedule.edge_findings.list".freeze
      UNREADABLE = "#{FEATURE_ID}.schedule.unreadable.list".freeze
      BY_TYPE = "#{FEATURE_ID}.schedule.by_type.list".freeze
      # An unreadable assignment's message can quote stored text of any length; a page row is cut here.
      MAX_MESSAGE = RecordQueries::MAX_MESSAGE
      UNITS = { "length_m" => "m", "psi_w_mk" => "W/mK", "heat_loss_w_k" => "W/K" }.freeze

      module_function

      # The whole schedule: every run, its findings, the totals, every Edge finding and unreadable assignment.
      def schedule(request)
        facts, unreadable = call(request)
        result = Runs::Schedule.call(facts, :types => types(request.engine))
        result.merge("edge_finding_total" => result.fetch("edge_findings").length, "unreadable" => unreadable,
                     "unreadable_total" => unreadable.length, "units" => UNITS)
      end

      # One bounded page of runs in schedule order, with the totals over every run and the first
      # DETAIL_ROWS Edge findings and unreadable assignments. The runs share the page's byte budget with
      # what is beside them. A bad limit or cursor refuses before the Model is walked.
      # With `compact`, each run leaves out its points and Edge paths and each finding its Edges, counting
      # them, and the Edge findings and unreadable assignments are left to their own pages, counted.
      def page(request)
        whole = paged_schedule(request, LIST)
        compact = request.params["compact"]
        runs = whole.fetch("runs")
        runs = runs.each_with_index.map { |run, index| compact_run(run, index) } if compact
        beside = if compact
                   whole.reject { |key, _value| %w[edge_findings unreadable].include?(key) }
                        .merge("runs" => [], "totals" => compact_totals(whole.fetch("totals")))
                 else
                   whole.merge("runs" => [], "edge_findings" => whole.fetch("edge_findings").first(DETAIL_ROWS),
                               "unreadable" => whole.fetch("unreadable").first(DETAIL_ROWS).map { |row| cut(row) })
                 end
        # A cursor holds a String or an Array, so a run's place in the schedule is carried as a one-item Array:
        # its index, since two runs may share an identifier.
        indexed = runs.each_with_index.map { |row, index| [[index], row] }
        page, cursor = Pages.bounded(request, LIST, indexed, :key => :first.to_proc, :max_bytes => budget(beside))
        beside.merge("runs" => page.map(&:last), "next_cursor" => cursor, "total" => runs.length)
      end

      # One page of one run's member Edges in run order, each with its root-to-Edge path and world end points,
      # or of only the Edges one of its findings names. The run is named by its derived identifier, which
      # changes with the geometry, so a run that changed refuses target.not_found as well as by cursor.
      # Two runs may share an identifier; `index`, the run's place in the schedule a compact row gives, then
      # names one, and without it such an identifier refuses target.ambiguous.
      def members(request)
        whole = paged_schedule(request, MEMBERS)
        run = named_run(whole.fetch("runs"), request.params.fetch("identifier"), request.params["index"])
        identifier = run.fetch("identifier")

        paths = run.fetch("edge_paths")
        points = run.fetch("points_m")
        named = named_paths(run, request.params["finding"])&.to_set
        rows = paths.each_with_index.filter_map do |path, index|
          next if named && !named.include?(path)

          { "index" => index, "path" => path, "points_m" => [points[index], points[index + 1]] }
        end
        page, next_cursor = Pages.bounded(request, MEMBERS, rows, :key => ->(row) { [row.fetch("index")] })
        { "identifier" => identifier, "members" => page, "next_cursor" => next_cursor, "total" => rows.length }
      end

      def named_run(runs, identifier, index)
        found = index.nil? ? runs : [runs[index]].compact
        found = found.select { |row| row.fetch("identifier") == identifier }
        raise CodedError.new("target.not_found", "No thermal-bridge run is #{identifier} now.") if found.empty?
        if found.length > 1
          raise CodedError.new("target.ambiguous", "#{found.length} runs are #{identifier}; name one by its index.")
        end

        found.first
      end

      # One page of the schedule's totals by Thermal Bridge Type, over every run, in the schedule's type order,
      # each name cut as every name in a bounded row is.
      def by_type(request)
        rows = paged_schedule(request, BY_TYPE).dig("totals", "by_type").each_with_index.map do |row, index|
          [[index], row.merge(OccurrencePath.bounded_names(row.slice("type_name")))]
        end
        page, next_cursor = Pages.bounded(request, BY_TYPE, rows, :key => :first.to_proc)
        { "by_type" => page.map(&:last), "next_cursor" => next_cursor, "total" => rows.length }
      end

      # One page of the assigned Edges no Zone holds, or of the assignments that cannot be read, by path.
      def edge_findings(request)
        listed(request, EDGE_FINDINGS, "edge_findings")
      end

      def unreadable(request)
        listed(request, UNREADABLE, "unreadable") { |row| cut(row) }
      end

      def cut(row)
        row.merge("message" => row.fetch("message")[0, MAX_MESSAGE])
      end

      def listed(request, query, key)
        rows = paged_schedule(request, query).fetch(key).sort_by { |row| row.fetch("path") }
        rows = rows.map { |row| yield row } if block_given?
        page, next_cursor = Pages.bounded(request, query, rows, :key => ->(row) { row.fetch("path") })
        { key => page, "next_cursor" => next_cursor, "total" => rows.length }
      end

      # The whole schedule for one page of `query`; a bad limit or cursor refuses before the Model is walked.
      def paged_schedule(request, query)
        Pages.limit(request.params)
        Pages.position(request, query)
        schedule(request)
      end

      def named_paths(run, finding)
        return nil if finding.nil?

        found = run.fetch("findings")[finding]
        raise CodedError.new("target.not_found", "The run has no finding #{finding}.") unless found

        found.dig("locate", "edge_paths")
      end

      # A run row without what grows with its length: its points, its Edge paths and each finding's Edges, and
      # with its labels cut as every name in a bounded row is.
      def compact_run(run, index)
        zone = run.fetch("zone")
        bounded = OccurrencePath.bounded_names(zone.slice("name", "building_segment"))
        labels = OccurrencePath.bounded_names(run.slice("display_name", "type_name"))
        truncated = Array(bounded.delete("truncated")).map { |key| "zone.#{key}" } + Array(labels.delete("truncated"))
        compact = run.reject { |key, _value| %w[points_m edge_paths].include?(key) }.merge(labels).merge(
          "zone" => zone.merge(bounded), "index" => index, "edge_count" => run.fetch("edge_paths").length,
          "point_count" => run.fetch("points_m").length,
          "findings" => run.fetch("findings").each_with_index.map do |finding, place|
            message = finding.fetch("message")
            truncated << "findings.#{place}.message" if message.length > MAX_MESSAGE
            finding.reject { |key, _value| key == "locate" }
                   .merge("message" => message[0, MAX_MESSAGE],
                          "edge_count" => finding.dig("locate", "edge_paths").length)
          end
        )
        truncated.empty? ? compact : compact.merge("truncated" => truncated)
      end

      # The totals without the per-type rows, which grow with the number of types: by_group, the run count and
      # the heat loss stay, and BY_TYPE pages the rest.
      def compact_totals(totals)
        totals.reject { |key, _value| key == "by_type" }.merge("type_count" => totals.fetch("by_type").length)
      end

      # What the page's runs may take: the page budget less what travels beside them, never below one row,
      # which Pages.bounded always sends.
      def budget(beside)
        [Pages::MAX_PAGE_BYTES - JSON.generate(beside).bytesize, 0].max
      end

      # Every Thermal Bridge Type's record by id. A type that cannot be read refuses the read, as it would
      # refuse its own.
      def types(engine)
        engine.ids(TYPE_KIND).to_h { |id| [id, engine.find(TYPE_KIND, id)] }
      end

      # Every assigned Edge occurrence as a Runs::Fact, and the assignments that cannot be read, each as
      # `{ path, code, message }`. A record that is not valid JSON or fails its schema is reported, never
      # repaired and never counted.
      def call(request)
        tagged, unreadable = walk(request.model)
        rows = paged(request, CONTAINMENT, "paths", tagged.map(&:path))
        faces = faces(request, tagged.zip(rows))
        facts = tagged.zip(rows).map do |edge, row|
          Runs::Fact.new(:path => edge.path, :zone => zone(row), :reason => row.fetch("reason"),
                         :record_id => edge.record.fetch("id"), :type_id => edge.record.fetch("thermal_bridge_type_id"),
                         :quantity => edge.record.fetch("quantity"), :points_m => edge.points_m,
                         :vertex_ids => edge.vertex_ids, :shared => edge.shared,
                         :faces => edge.face_ids.filter_map { |id| faces[edge.path[0...-1] + [id]] })
        end
        [facts, unreadable]
      end

      # Every Edge carrying an assignment, inside every Group and ComponentInstance, one per occurrence,
      # with its world endpoints. Transforms compose from the root, which gives world positions whether or
      # not a context is open (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts").
      def walk(model)
        tagged = []
        unreadable = []
        pending = [[model.entities, [], Geom::Transformation.new, false]]
        until pending.empty?
          entities, path, transform, shared = pending.shift
          entities.each do |entity|
            current = path + [entity.persistent_id]
            if entity.is_a?(Sketchup::Edge)
              read(entity, current, transform, shared, tagged, unreadable)
            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
              contents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
              pending << [contents, current, transform * entity.transformation, shared || shared?(entity)]
            end
          end
        end
        [tagged, unreadable]
      end

      def read(edge, path, transform, shared, tagged, unreadable)
        record = Assignment::STORE.read(edge)
        return unless record

        problem = Assignment::RECORD_KIND.problems(record).first
        if problem
          unreadable << { "path" => path, "code" => "validation.failed", "message" => problem }
        else
          points = [edge.start, edge.end].map { |vertex| FaceCapture.point_m(vertex.position.transform(transform)) }
          tagged << Tagged.new(:path => path, :record => record, :points_m => points,
                               :vertex_ids => [edge.start, edge.end].map(&:persistent_id),
                               :face_ids => edge.faces.map(&:persistent_id), :shared => shared,
                               :edge => edge, :transform => transform)
        end
      rescue CodedError => error
        raise unless error.code == "record.unreadable"

        unreadable << { "path" => path, "code" => error.code, "message" => error.message }
      end

      # Component storage, or a Group whose definition another Group shares: geometry every placement of
      # it shows, counted per placement.
      def shared?(entity)
        return true if entity.is_a?(Sketchup::ComponentInstance)

        definition = entity.respond_to?(:definition) ? entity.definition : nil
        definition.respond_to?(:instances) && definition.instances.length > 1
      end

      # The recorded values of each Zone-held Edge's Faces, keyed by root-to-Face path.
      def faces(request, pairs)
        paths = pairs.select { |_edge, row| row.fetch("zone") }.flat_map do |edge, _row|
          edge.face_ids.map { |id| edge.path[0...-1] + [id] }
        end
        paged(request, HOST_CONTEXT, "faces", paths.uniq).to_h { |row| [row.fetch("path"), row.fetch("values")] }
      end

      # The `key` rows of one of Zones' path reads over any number of paths, in the pages its bound admits.
      def paged(request, name, key, paths)
        paths.each_slice(Pages::MAXIMUM_LIMIT).flat_map { |slice| request.query(name, "paths" => slice).fetch(key) }
      end

      def zone(row)
        zone = row.fetch("zone")
        zone&.slice("zone_id", "zone_path", "name", "building_segment")
      end
    end
  end
end
