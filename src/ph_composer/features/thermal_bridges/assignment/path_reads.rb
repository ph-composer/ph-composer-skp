# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Assignment
      # Edges named by path rather than by the selection: explicit root-to-Edge paths, such as a schedule
      # run's `edge_paths`, and the Edges directly inside one container. Each row is the selection read's row
      # (Selection.row: the Zone holding the Edge, its complete reference, its values as stored and the
      # refusal a write meets) with the Edge's world endpoints, so assign, clear and a read back need no
      # selection and no `runs.locate`. A path that names no Edge is a row with its reason, never a refusal of
      # the read. Reads only, a bounded page at a time; nothing is selected or written.
      module PathReads
        AT = "#{FEATURE_ID}.edges.at".freeze
        CANDIDATES = "#{FEATURE_ID}.edges.candidates".freeze
        ASSIGNED = %w[any assigned unassigned].freeze
        UNITS = { "endpoints_m" => "m" }.freeze

        # An Edge a path names, its container's world transform, or why there is none.
        Found = Struct.new(:path, :edge, :transform, :reason, keyword_init: true)

        module_function

        # The paths in the order given, a bounded page at a time.
        def at(request)
          model = request.model
          paths = request.params.fetch("paths").map { |path| OccurrencePath.integer_path(path) }
          build = ->(indices) { rows(request, indices.map { |index| find(model, paths[index]) }) }
          page, next_cursor = Pages.bounded(request, AT, paths.each_index.to_a, :key => ->(index) { [index] },
                                                                                :prepare => build)
          { "edges" => page, "next_cursor" => next_cursor, "total" => paths.length, "units" => UNITS }
        end

        # The Edges directly inside one container, by persistent id, all of them or only those with or without
        # an assignment record. An unreadable record counts as one.
        def candidates(request)
          params = request.params
          container = OccurrencePath.resolve(request.model, params.fetch("path", []))
          wanted = params.fetch("assigned", "any")
          edges = container.entities.to_a.grep(Sketchup::Edge).select do |edge|
            wanted == "any" || STORE.marks?(edge) == (wanted == "assigned")
          end
          found = edges.sort_by(&:persistent_id).map do |edge|
            Found.new(:path => container.path + [edge.persistent_id], :edge => edge, :transform => container.transform)
          end
          page, next_cursor = Pages.bounded(request, CANDIDATES, found, :key => ->(item) { item.path },
                                                                        :prepare => ->(items) { rows(request, items) })
          { "container" => { "path" => container.path, "locked" => container.locked, "hidden" => container.hidden,
                             "shared" => container.shared },
            "edges" => page, "next_cursor" => next_cursor, "total" => found.length, "units" => UNITS }
        end

        def find(model, path)
          container = OccurrencePath.resolve(model, path[0...-1])
          matches = container.entities.to_a.select { |entity| entity.persistent_id == path.last }
          return Found.new(:path => path, :reason => "not_found") unless matches.length == 1
          return Found.new(:path => path, :reason => "not_an_edge") unless matches.first.is_a?(Sketchup::Edge)

          Found.new(:path => path, :edge => matches.first, :transform => container.transform)
        rescue CodedError
          Found.new(:path => path, :reason => "not_found")
        end

        # One row per found item, in order. Zones answers containment for the Edges in one read of the page.
        def rows(request, items)
          edges = items.select(&:edge)
          records = edges.map { |item| stored(item.edge) }
          copied = Selection.copied_ids(request.model, records.map(&:first))
          contained = Operations.contained(request, edges.map(&:path)).zip(records, edges)
          by_path = contained.to_h do |containment, (record, problem), item|
            row = Selection.row(containment, record, copied).merge("endpoints_m" => endpoints(item),
                                                                   "hidden" => OccurrencePath.hidden?(item.edge))
            [item.path, problem ? row.merge("record_problem" => problem) : row]
          end
          items.map { |item| by_path.fetch(item.path) { absent(item) } }
        end

        # The record as stored and, when it is not valid JSON or not an object, why: such an Edge reads with no
        # values, and a write to it refuses.
        def stored(edge)
          record = STORE.read(edge)
          return [record, nil] if record.nil? || record.is_a?(Hash)

          [nil, "The #{STORE.dictionary} record is not a JSON object."]
        rescue CodedError => error
          raise unless error.code == "record.unreadable"

          [nil, error.message]
        end

        def endpoints(item)
          ends = [item.edge.start, item.edge.end]
          ends.map { |vertex| FaceCapture.point_m(vertex.position.transform(item.transform)) }
        end

        def absent(item)
          { "path" => item.path, "reference" => nil, "zone" => nil, "reason" => item.reason, "values" => {},
            "copied" => false, "record_problem" => nil, "write_refusal" => nil, "endpoints_m" => nil,
            "hidden" => nil }
        end
        private_class_method :find, :rows, :stored, :endpoints, :absent
      end
    end
  end
end
