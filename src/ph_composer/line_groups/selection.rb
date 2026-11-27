# frozen_string_literal: true

module PhComposer
  module LineGroups
    # The native selection as Edge references, for the feature's assign and clear, and what Make <group> over it
    # meets. The caller passes its gesture `limit` and `contained`, which answers containment rows (`{ path, zone }`,
    # zone nil or named) for root-to-entity paths.
    module Selection
      # Selected entities that are not Edges are listed up to this many and counted in full.
      IGNORED_ROWS = 50

      module_function

      def all(spec, request, limit:, contained:)
        rows, others = rows(spec, request, :limit => limit, :contained => contained)
        { "edges" => rows, "make_refusal" => make_refusal(spec, request, others, contained) }.merge(ignored(others))
      end

      # The rows a bounded page at a time under `query`; a cursor is bound to the selection too.
      def page(spec, request, query, limit:, contained:)
        rows, others = rows(spec, request, :limit => limit, :contained => contained)
        binding = "#{request.revision}/#{CanonicalJson.digest(rows.map { |row| row.fetch('path') })}"
        page, cursor = Pages.bounded(request, query, rows, :key => ->(row) { row.fetch("path") },
                                                           :revision => binding)
        { "edges" => page, "next_cursor" => cursor, "total" => rows.length,
          "make_refusal" => make_refusal(spec, request, others, contained) }.merge(ignored(others))
      end

      # What Make <group> meets over the whole selection, or nil when it can run with every selected line's path. A
      # selected Face a selected line bounds, as a window selection over a filled loop takes, is not counted as a
      # stray entity: Make erases it when the lines close it, and otherwise refuses it with the repair it needs.
      def make_refusal(spec, request, others, contained)
        model = request.model
        edges = model.selection.to_a.grep(Sketchup::Edge)
        bounded = edges.flat_map(&:faces).map(&:persistent_id)
        counted = others.count { |entity| !(entity.is_a?(Sketchup::Face) && bounded.include?(entity.persistent_id)) }
        Make.refusal(spec, model, Array(model.active_path), edges, :others => counted, :contained => contained)
      end

      def ignored(others)
        { "ignored" => others.first(IGNORED_ROWS).map do |entity|
          { "persistent_id" => entity.persistent_id, "type" => entity.typename }
        end, "ignored_total" => others.length }
      end

      # Each selected Edge under the active path with the line group holding it, its assignment as stored and the
      # refusal a write to it meets. An Edge not directly in a line group has no reference; its reason says so.
      def rows(spec, request, limit:, contained:)
        model = request.model
        edges, others = model.selection.to_a.partition { |entity| entity.is_a?(Sketchup::Edge) }
        if edges.length > limit
          raise CodedError.new("gesture.too_large", "Select at most #{limit} Edges; #{edges.length} are selected.")
        end

        parent = Array(model.active_path)
        group_paths = parent.empty? ? [] : [parent.map(&:persistent_id)]
        zone = contained.call(group_paths).first
        reads = edges.map { |edge| LineGroups.read(edge, spec.edge_store) }
        ids = reads.filter_map { |record, _problem| record && record["id"] }
        counts = ids.empty? ? {} : EdgeTarget.entries(spec, model).map { |entry| entry.record["id"] }.tally
        found = edges.zip(reads).map do |edge, read|
          row(spec, parent, edge, read, :zone => zone && zone["zone"], :counts => counts)
        end
        [found.sort_by { |row| row.fetch("path") }, others]
      end

      def row(spec, parent, edge, (record, problem), zone:, counts:)
        path = (parent + [edge]).map(&:persistent_id)
        group = parent.last
        base = { "path" => path, "values" => spec.edge_values(record),
                 "copied" => counts.fetch(record && record["id"], 0) > 1,
                 "record_problem" => problem || (record && spec.edge_record_kind.problems(record).first) }
        unless group && spec.group?(group)
          return base.merge("reference" => nil, "group" => nil, "reason" => "outside_group", "write_refusal" => nil)
        end

        group_record, group_problem = LineGroups.read(group, spec.group_store)
        stored = unreadable(group_problem) || unreadable(problem) || newer(spec, record)
        invalid = group_record && spec.group_record_kind.problems(group_record).first
        stored ||= { "code" => "validation.failed", "message" => "The #{spec.label}'s #{invalid}" } if invalid
        group_record = nil if group_problem || invalid
        base.merge("reference" => { "group_path" => path[0...-1], "entity_path" => path,
                                    "entity_id" => spec.edge_identity(record) },
                   "group" => group_record && { "group_id" => group_record["id"], "group_path" => path[0...-1],
                                                spec.link_key => group_record[spec.link_key] },
                   "reason" => nil, "write_refusal" => refusal(spec, parent, zone, stored))
      end

      # What assign refuses on a record of another schema version, which this version cannot rewrite.
      def newer(spec, record)
        return nil unless record && record["schema_version"] != spec.edge_record_kind.schema_version

        { "code" => "validation.failed",
          "message" => "The Edge's #{spec.edge_noun} assignment is schema version " \
                       "#{record['schema_version'].inspect}." }
      end

      def unreadable(problem)
        problem && { "code" => "record.unreadable", "message" => problem }
      end

      # What a write to an Edge in the open line group meets: the group nested in another or held by a Zone, a
      # component, locked or shared step, or a stored record a write cannot take.
      def refusal(spec, parent, zone, stored)
        nested = GroupTarget.nested_refusal(spec, parent[0...-1])
        return nested if nested
        if zone
          return { "code" => spec.code(:group_in_zone),
                   "message" => "The #{spec.label} sits inside #{Records::Names.titled('Zone', zone.fetch('name'))}; " \
                                "move it out first." }
        end

        GroupTarget.write_refusal(spec, parent) || stored
      end

      def assignable?(row)
        !row["reference"].nil? && row["write_refusal"].nil?
      end
    end
  end
end
