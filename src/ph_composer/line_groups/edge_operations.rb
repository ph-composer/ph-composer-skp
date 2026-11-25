# frozen_string_literal: true

module PhComposer
  module LineGroups
    # Clear, the rewrite a type delete makes, and the resolve, update and step a feature's own assign builds on. Each
    # resolves every target before proposing anything and refuses the whole command if one is stale, outside a line
    # group, in a group a Zone holds or behind a write refusal; the dispatcher owns the native operation.
    module EdgeOperations
      STRANDED_DETAIL = 20

      module_function

      # Removes each Edge's assignment. An Edge with none is left alone.
      def clear(spec, request, proposal, targets, limit:)
        updates = resolve(spec, request, targets, :limit => limit).filter_map do |reference, before|
          before && update(spec, reference, before, nil)
        end
        check_removals!(spec, request, proposal, updates)
        propose(spec, proposal, updates)
        { "cleared" => updates.length }
      end

      # Delete a type and, in the same proposal and Undo step, move every Edge naming it to `replacement_id`, or null
      # their type when it is nil. Without a replacement the engine refuses a type in use. `types` is the feature's
      # type operations (`KEEP`, `check_replacement!` and `delete`). A stale `expected_values` refuses as
      # target.changed before any Edge is planned, so an Edge the rewrite cannot reach never hides it.
      def delete_type(spec, request, proposal, types:, id:, expected_values:, replacement_id:)
        keep = replacement_id.equal?(types::KEEP)
        type = request.engine.find(spec.type_kind, id)
        changed = expected_values.keys.reject { |key| type[key] == expected_values[key] }
        unless changed.empty?
          raise CodedError.new("target.changed", "#{spec.type_label} #{id} has changed since it was read " \
                                                 "(#{changed.join(', ')}).", "fields" => changed)
        end

        types.check_replacement!(request, id, replacement_id) unless keep
        plan = replace_type(spec, request, proposal, :from => id, :to => replacement_id) unless keep
        types.delete(request, proposal, :id => id, :expected_values => expected_values, :reference_plan => plan)
      end

      # The Edges naming type `from`, rewritten to `to` (nil nulls it), in this proposal; the plan the type's delete
      # hands the engine. An Edge the rewrite cannot reach, outside a line group or behind a locked or shared step,
      # refuses the whole delete.
      def replace_type(spec, request, proposal, from:, to:)
        updates = []
        stranded = []
        index = request.locate_index(spec.edge_kind)
        EdgeTarget.entries(spec, request.model).each do |entry|
          next unless entry.record[spec.type_key] == from

          reference = { "group_path" => entry.key[0...-1], "entity_path" => entry.key,
                        "entity_id" => entry.record["id"] }
          begin
            # The scan found it; the rewrite starts from the record as stored, which must be valid.
            edge = request.locate(spec.edge_kind, reference, :index => index).entity
            before = spec.validate_edge!(spec.edge_store.read(edge))
            updates << update(spec, reference, before, spec.validate_edge!(before.merge(spec.type_key => to)))
          rescue CodedError => error
            stranded << { "path" => entry.key, "reason" => error.code }
          end
        end
        refuse_stranded(spec, from, stranded) unless stranded.empty?

        propose(spec, proposal, updates)
        plan(spec, updates)
      end

      def refuse_stranded(spec, from, stranded)
        message = "#{stranded.length} #{spec.edge_noun}(s) use #{spec.type_label} #{from} where the delete cannot " \
                  "rewrite them (outside a #{spec.label}, in a nested one, locked, shared or invalid); move, " \
                  "unlock, make them unique or clear them, then delete again."
        raise CodedError.new("reference.in_use", message, "target_kind" => spec.type_kind, "id" => from,
                                                          "edges" => stranded.first(STRANDED_DETAIL),
                                                          "stranded" => stranded.length)
      end

      # Each target resolved for writing, as `[reference, record]`, deduplicated by Edge and bounded by `limit` before
      # any walk; the groups they sit in are checked against the Zones once.
      def resolve(spec, request, targets, limit:)
        unique = targets.group_by { |target| target.dig("reference", "entity_path") }
        if unique.values.any? { |group| group.uniq.length > 1 }
          raise CodedError.new("params.invalid", "Repeated Edge targets disagree on identity or expected values.")
        end
        if unique.length > limit
          raise CodedError.new("gesture.too_large",
                               "One command changes at most #{limit} Edges; this one has #{unique.length}.")
        end

        index = request.locate_index(spec.edge_kind)
        resolved = unique.values.map do |(target)|
          edge = request.locate(spec.edge_kind, target.fetch("reference"), :index => index).entity
          before = spec.edge_store.read(edge)
          check_expected!(spec, before, target.fetch("expected_values", {}))
          [target.fetch("reference"), before]
        end
        GroupOperations.outside_zones!(spec, request, resolved.map { |reference, _before| reference["group_path"] })
        resolved
      end

      def check_expected!(spec, before, expected)
        values = spec.edge_values(before)
        changed = expected.keys.reject { |key| values[key] == expected[key] }
        return if changed.empty?

        raise CodedError.new("target.changed", "The Edge changed since it was read (#{changed.join(', ')}).")
      end

      def update(spec, reference, before, after)
        change = if after.nil? then "removed"
                 elsif before then "updated"
                 else "created"
                 end
        { "reference" => reference.merge("entity_id" => spec.edge_identity(before)), "before" => before,
          "after" => after, "change" => change }
      end

      # Refuses reference.in_use when a record still names an assignment id these updates remove and no Edge the
      # command leaves keeps (a copy keeps it alive). Every removed record with a valid id is checked, whatever else is
      # wrong with it, since a referrer can name it; the plan the check projects holds the valid ones, read as the
      # reference scan reads them (LineGroups.scannable), since the engine refuses an invalid planned record.
      def check_removals!(spec, request, proposal, updates)
        return if updates.empty?

        removed = updates.map { |row| row.merge("before" => LineGroups.scannable(row.fetch("before"))) }
        gone = removed.map { |row| row.dig("reference", "entity_path") }
        kept = EdgeTarget.entries(spec, request.model).reject { |entry| gone.include?(entry.key) }
                         .map { |entry| entry.record["id"] }
        checked = plan(spec, removed.select { |row| spec.edge_record_kind.problems(row.fetch("before")).empty? })
        (removed.filter_map { |row| spec.edge_identity(row.fetch("before")) }.uniq - kept).each do |id|
          request.engine.check_identity_removal!(spec.edge_kind, id, :change_set => proposal.record_changes,
                                                                     :reference_plan => checked)
        end
      end

      def propose(spec, proposal, updates)
        return if updates.empty?

        scopes = updates.map { |row| row.dig("reference", "group_path")[0...-1] }.uniq.map do |path|
          PhComposer::Operations::EntityScope.new(path)
        end
        proposal.add_step(EdgeWriteStep.new(:spec => spec, :updates => updates), :scopes => scopes)
      end

      def plan(spec, updates)
        entries, removals = updates.partition { |row| row.fetch("after") }
        Records::ReferencePlan.new(
          :entries => entries.map do |row|
            Records::ReferenceEntry.new(:kind => spec.edge_kind, :key => row.dig("reference", "entity_path"),
                                        :record => row.fetch("after"))
          end,
          :removals => removals.map do |row|
            Records::ReferenceRemoval.new(:kind => spec.edge_kind, :key => row.dig("reference", "entity_path"),
                                          :before => row.fetch("before"))
          end
        )
      end
    end
  end
end
