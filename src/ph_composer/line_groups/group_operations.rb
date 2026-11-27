# frozen_string_literal: true

module PhComposer
  module LineGroups
    # Make, link and unlink a feature's line groups, the retarget its linked record's delete asks for, and the
    # occurrence rows the reads return. A write resolves every Group before proposing anything and refuses the whole
    # command if one is stale, unwritable or misplaced; the dispatcher owns the native operation.
    module GroupOperations
      # One link or unlink names at most this many Groups.
      TARGET_LIMIT = 250
      STRANDED_DETAIL = 20

      module_function

      # A new group, where the lines `edge_paths` name are drawn, wrapping them, with a new record naming `link_id`
      # (Make). It takes the first free "<label> N" among its kind's groups, and the Faces the lines close
      # (Make.closed_faces) are erased in the same operation. The edit path stays where it is. `limit` is the
      # feature's Edge gesture limit.
      def make(spec, request, proposal, edge_paths, link_id, limit:)
        paths = edge_paths.uniq
        if paths.length > limit
          raise CodedError.new("gesture.too_large", "Make a #{spec.label} from at most #{limit} lines; " \
                                                    "#{paths.length} are named.")
        end

        request.engine.find(spec.link_kind, link_id)
        containers, edges = Make.resolve!(spec, request.model, paths)
        refusal = Make.refusal(spec, request.model, containers, edges,
                               :contained => ->(rows) { contained(spec, request, rows) })
        GroupTarget.raise_refusal(refusal)
        id = Records::Identity.allocator(request, request.params).call(spec.group_record_kind.id_prefix)
        record = spec.validate_group!(spec.new_group(id, link_id))
        parent_path = containers.map(&:persistent_id)
        name = free_name(spec, request.model)
        faces = Make.closed_faces(edges)
        proposal.add_step(MakeStep.new(:spec => spec, :record => record, :name => name, :parent_path => parent_path,
                                       :edge_ids => edges.map(&:persistent_id),
                                       :face_ids => faces.map(&:persistent_id)),
                          :scopes => [PhComposer::Operations::EntityScope.new(parent_path)])
        { "group_id" => id, "name" => name, "removed_faces" => faces.length }
      end

      # The first free "<label> N" among the names of the feature's groups, wherever they sit.
      def free_name(spec, model)
        names = []
        GroupTarget.each_group(spec, model) { |group, _path, _along| names << group.name.to_s }
        Records::Names.numbered(spec.label, names)
      end

      # Sets each Group's linked record, or clears it with nil. A Group already naming it is left alone.
      def link(spec, request, proposal, targets, link_id)
        request.engine.find(spec.link_kind, link_id) if link_id
        by_path = targets.group_by { |target| target.dig("reference", "group_path") }
        if by_path.values.any? { |repeats| repeats.uniq.length > 1 }
          raise CodedError.new("params.invalid", "Repeated #{spec.label} targets disagree on identity or values.")
        end

        unique = by_path.values.map(&:first)
        if unique.length > TARGET_LIMIT
          raise CodedError.new("gesture.too_large", "One command names at most #{TARGET_LIMIT} #{spec.label}s.")
        end

        located = unique.map do |target|
          group = request.locate(spec.group_kind, target.fetch("reference")).entity
          before = spec.group_store.read(group)
          check_expected!(spec, before, target.fetch("expected_values", {}))
          [target.fetch("reference"), before]
        end
        outside_zones!(spec, request, located.map { |reference, _before| reference.fetch("group_path") })
        updates = located.filter_map do |reference, before|
          after = spec.validate_group!(before.merge(spec.link_key => link_id))
          { "reference" => reference, "before" => before, "after" => after } unless after == before
        end
        propose(spec, proposal, updates)
        { "group_ids" => updates.map { |update| update.fetch("after").fetch("id") } }
      end

      # The retargeter the linked record's delete runs: every group naming `from` names `to`, or none with nil, in the
      # delete's proposal. A group the rewrite cannot reach refuses the delete.
      def retarget(spec, request, proposal, from:, to:)
        updates = []
        stranded = []
        GroupTarget.each_group(spec, request.model) do |group, path, _along|
          record, = LineGroups.read(group, spec.group_store)
          next unless record && record[spec.link_key] == from

          reference = { "group_id" => record["id"], "group_path" => path }
          begin
            request.locate(spec.group_kind, reference)
            updates << { "reference" => reference, "before" => record,
                         "after" => spec.validate_group!(record.merge(spec.link_key => to)) }
          rescue CodedError => error
            stranded << { "group_path" => path, "reason" => error.code }
          end
        end
        refuse_stranded(spec, from, stranded) unless stranded.empty?

        propose(spec, proposal, updates)
        Records::ReferencePlan.new(:entries => updates.map do |update|
          Records::ReferenceEntry.new(:kind => spec.group_kind, :key => update.dig("reference", "group_path"),
                                      :record => update.fetch("after"))
        end)
      end

      # The repair said follows each group's reason: a record failing its schema is repaired, a placement is changed.
      def refuse_stranded(spec, from, stranded)
        invalid = stranded.count { |row| row["reason"] == "validation.failed" }
        repairs = []
        repairs << "repair #{invalid == stranded.length ? 'their records' : 'each record that fails its schema'}" \
          if invalid.positive?
        repairs << "unlock, make unique or move #{invalid.positive? ? 'the rest' : 'them'}" if invalid < stranded.length
        message = "#{stranded.length} #{spec.label}(s) name #{spec.link_label} #{from} where the delete cannot " \
                  "rewrite them (locked, shared, nested or invalid); #{repairs.join(' and ')}, then delete again."
        raise CodedError.new("reference.in_use", message, "target_kind" => spec.link_kind, "id" => from,
                                                          "groups" => stranded.first(STRANDED_DETAIL),
                                                          "stranded" => stranded.length)
      end

      # Refuses the feature's group_in_zone code when a Zone holds any of these root-to-Group paths.
      def outside_zones!(spec, request, paths)
        held = contained(spec, request, paths.uniq).find { |row| row["zone"] }
        return unless held

        # The message names no persistent id; the group's path is in the detail.
        raise CodedError.new(spec.code(:group_in_zone), "A #{spec.label} sits inside " \
                                                        "#{Records::Names.titled('Zone', held.dig('zone', 'name'))}; " \
                                                        "move it out of the Zone first.",
                             "group_path" => held.fetch("path"))
      end

      # The groups naming one linked record, by name, as its delete lists them: `unlinkable`, the readable groups its
      # retarget moves or clears, and `blocking`, the groups whose record fails its schema but still names it, over
      # which the retarget refuses every delete until they are repaired.
      LinkedNames = Struct.new(:unlinkable, :blocking, keyword_init: true)

      # Each linked record's id with its LinkedNames, each list sorted, from one Scan.walk: a group's own name, or for
      # an unnamed one its label and path, as the panel labels it. A group's links are the ids the engine's reference
      # scan reads from its record, so one an invalid record names in a malformed value or in a readable extension
      # envelope still blocks; a valid group lists only its own link, the one the retarget moves.
      def names_by_link(spec, walked)
        groups, _unreadable, invalid = walked
        found = Hash.new { |names, link| names[link] = LinkedNames.new(:unlinkable => [], :blocking => []) }
        [[groups, :unlinkable], [invalid, :blocking]].each do |found_groups, list|
          found_groups.each do |group|
            name = group.name.empty? ? "#{spec.label} #{group.path.join('/')}" : group.name
            linked_ids(spec, group.record, :envelopes => list == :blocking).each { |link| found[link][list] << name }
          end
        end
        found.transform_values do |names|
          LinkedNames.new(:unlinkable => sorted_names(names.unlinkable), :blocking => sorted_names(names.blocking))
        end
      end

      # The ids of `spec.link_kind` a group record's core references name, and with `envelopes` its readable extension
      # envelopes too, as the engine's incoming-reference scan reads them.
      def linked_ids(spec, record, envelopes:)
        record = LineGroups.scannable(record)
        targets = spec.group_record_kind.referenced_targets(record)
        targets += Records::Extension.envelope_targets(record) if envelopes
        targets.filter_map { |kind, id| id if kind == spec.link_kind }.uniq
      end

      def sorted_names(names)
        names.sort_by { |name| [name.sub(/\d+\z/, ""), name[/\d+\z/].to_i, name] }
      end

      # The containment rows (`{ path, zone }`, zone nil or named) for root-to-Group paths, a page at a time.
      def contained(spec, request, paths)
        paths.each_slice(Pages::MAXIMUM_LIMIT).flat_map do |slice|
          request.query(spec.containment, "paths" => slice).fetch("paths")
        end
      end

      def check_expected!(spec, before, expected)
        values = spec.group_values(before)
        changed = expected.keys.reject { |key| values[key] == expected[key] }
        return if changed.empty?

        raise CodedError.new("target.changed", "The #{spec.label} changed since it was read (#{changed.join(', ')}).")
      end

      def propose(spec, proposal, updates)
        return if updates.empty?

        scopes = updates.map { |update| update.dig("reference", "group_path")[0...-1] }.uniq.map do |path|
          PhComposer::Operations::EntityScope.new(path)
        end
        proposal.add_step(GroupWriteStep.new(:spec => spec, :updates => updates), :scopes => scopes)
      end

      # Every group occurrence in root-path order, with its linked record, its assigned-Edge count, whether its id is
      # copied, its placement findings and the refusal a write to it meets.
      def rows(spec, request)
        found = []
        GroupTarget.each_group(spec, request.model) { |group, path, along| found << [group, path, along] }
        reads = found.map { |group, _path, _along| LineGroups.read(group, spec.group_store) }
        counts = reads.filter_map { |record, _problem| record && record["id"] }.tally
        zones = contained(spec, request, found.map { |_group, path, _along| path })
        found.zip(reads, zones).map do |(group, path, along), (record, problem), zone|
          row(spec, group, path, along, [record, problem], :copied => counts.fetch(record && record["id"], 0) > 1,
                                                           :zone => zone["zone"])
        end.sort_by { |row| row.fetch("path") }
      end

      # The refusal a write to the group meets, in the order link and unlink meet them: nested, the path's own (a
      # component, a locked or shared step), then in a Zone.
      def row(spec, group, path, along, (record, problem), copied:, zone:)
        id = spec.group_identity(record)
        nested = GroupTarget.nested_refusal(spec, along[0...-1])
        in_zone = zone && { "code" => spec.code(:group_in_zone),
                            "message" => "The #{spec.label} sits inside " \
                                         "#{Records::Names.titled('Zone', zone.fetch('name'))}; move it out first." }
        findings = []
        findings << spec.code(:group_in_zone) if zone
        findings << spec.code(:group_nested) if nested
        { "path" => path, "reference" => id && { "group_id" => id, "group_path" => path }, "name" => group.name.to_s,
          "values" => spec.group_values(record),
          "#{spec.edge_noun}_count" => group.entities.count { |entity| spec.edge?(entity) }, "copied" => copied,
          "findings" => findings,
          "record_problem" => problem || (record && spec.group_record_kind.problems(record).first),
          "write_refusal" => nested || GroupTarget.write_refusal(spec, along) || in_zone }
      end
    end
  end
end
