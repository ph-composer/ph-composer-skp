# frozen_string_literal: true

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
      def page(request)
        Pages.limit(request.params)
        Pages.position(request, LIST)
        whole = schedule(request)
        runs = whole.fetch("runs")
        beside = whole.merge("runs" => [], "edge_findings" => whole.fetch("edge_findings").first(DETAIL_ROWS),
                             "unreadable" => whole.fetch("unreadable").first(DETAIL_ROWS))
        # A cursor holds a String or an Array, so a run's place in the schedule is carried as a one-item Array.
        order = runs.each_with_index.to_h { |row, index| [row.fetch("identifier"), [index]] }
        page, cursor = Pages.bounded(request, LIST, runs, :key => ->(row) { order.fetch(row.fetch("identifier")) },
                                                          :max_bytes => budget(beside))
        beside.merge("runs" => page, "next_cursor" => cursor, "total" => runs.length)
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
                         :type_id => edge.record.fetch("thermal_bridge_type_id"),
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
