# frozen_string_literal: true

module PhComposer
  module Piping
    module Assignment
      # Assign, Clear and the rewrite a Pipe Type delete makes. Each resolves every target before proposing anything
      # and refuses the whole command if one is stale, outside a Piping group, in a Piping group a Zone holds or
      # behind a write refusal; the dispatcher owns the native operation.
      module Operations
        STRANDED_DETAIL = 20

        module_function

        # One record per Edge, all in one step: a fresh `ppe_` id on a first assignment, the Edge's own id and
        # metadata on a reassignment. The role's values are `role_values` over the Edge's own when it keeps its role,
        # else over the role's defaults; a value the role does not take refuses, and a new role drops the old one's.
        def assign(request, proposal, targets:, pipe_type_id:, role:, role_values:)
          extra = role_values.keys - ROLE_VALUES.fetch(role).keys
          unless extra.empty?
            raise CodedError.new("params.invalid", "A #{role} pipe does not take #{extra.join(', ')}.")
          end

          request.engine.find(PIPE_TYPE_KIND, pipe_type_id)
          allocate = Records::Identity.allocator(request, request.params)
          updates = resolve(request, targets).filter_map do |reference, before|
            if before && before["schema_version"] != 1
              raise CodedError.new("validation.failed", "An Edge's pipe assignment is schema version " \
                                                        "#{before['schema_version'].inspect}, which this version " \
                                                        "cannot rewrite.")
            end

            after = (before || {}).slice("id", "user_data", "extension_data")
            after["id"] = allocate.call("ppe") unless Assignment.identity(after)
            kept = before && before["role"] == role ? before.slice(*ROLE_VALUES.fetch(role).keys) : {}
            after = { "user_data" => {}, "extension_data" => {} }.merge(after).merge(
              "schema_version" => 1, "pipe_type_id" => pipe_type_id, "role" => role
            ).merge(ROLE_VALUES.fetch(role)).merge(kept).merge(role_values)
            next if after == before

            update(reference, before, Assignment.validate!(after))
          end
          propose(proposal, updates)
          { "edge_ids" => updates.map { |row| row.fetch("after").fetch("id") } }
        end

        # Removes each Edge's assignment. An Edge with none is left alone.
        def clear(request, proposal, targets:)
          updates = resolve(request, targets).filter_map do |reference, before|
            before && update(reference, before, nil)
          end
          check_removals!(request, proposal, updates)
          propose(proposal, updates)
          { "cleared" => updates.length }
        end

        # Delete a Pipe Type and, in the same proposal and Undo step, move every pipe naming it to `replacement_id`,
        # or null their type when it is nil. Without a replacement the engine refuses a type in use.
        def delete_type(request, proposal, id:, expected_values:, replacement_id:)
          keep = replacement_id.equal?(PipeType::Operations::KEEP)
          PipeType::Operations.check_replacement!(request, id, replacement_id) unless keep
          plan = replace_type(request, proposal, :from => id, :to => replacement_id) unless keep
          PipeType::Operations.delete(request, proposal, :id => id, :expected_values => expected_values,
                                                         :reference_plan => plan)
        end

        # The pipes naming type `from`, rewritten to `to` (nil nulls it), in this proposal; the plan the type's
        # delete hands the engine. A pipe the rewrite cannot reach, outside a Piping group or behind a locked or
        # shared step, refuses the whole delete.
        def replace_type(request, proposal, from:, to:)
          updates = []
          stranded = []
          index = request.locate_index(PIPE_KIND)
          Target.entries(request.model).each do |entry|
            next unless entry.record["pipe_type_id"] == from

            reference = { "group_path" => entry.key[0...-1], "entity_path" => entry.key,
                          "entity_id" => entry.record["id"] }
            begin
              # The scan found it; the rewrite starts from the record as stored, which must be valid.
              before = Assignment.validate!(STORE.read(request.locate(PIPE_KIND, reference, :index => index).entity))
              updates << update(reference, before, Assignment.validate!(before.merge("pipe_type_id" => to)))
            rescue CodedError => error
              stranded << { "path" => entry.key, "reason" => error.code }
            end
          end
          refuse_stranded(from, stranded) unless stranded.empty?

          propose(proposal, updates)
          plan(updates)
        end

        def refuse_stranded(from, stranded)
          message = "#{stranded.length} pipe(s) use Pipe Type #{from} where the delete cannot rewrite them " \
                    "(outside a Piping group, in a nested one, locked, shared or invalid); move, unlock, make " \
                    "them unique or clear them, then delete again."
          raise CodedError.new("reference.in_use", message, "target_kind" => PIPE_TYPE_KIND, "id" => from,
                                                            "edges" => stranded.first(STRANDED_DETAIL),
                                                            "stranded" => stranded.length)
        end

        # Each target resolved for writing, as `[reference, record]`, deduplicated by Edge and bounded before any
        # walk; the Piping groups they sit in are checked against the Zones once.
        def resolve(request, targets)
          unique = targets.group_by { |target| target.dig("reference", "entity_path") }
          if unique.values.any? { |group| group.uniq.length > 1 }
            raise CodedError.new("params.invalid", "Repeated Edge targets disagree on identity or expected values.")
          end

          Assignment.check_limit!(unique.length)
          index = request.locate_index(PIPE_KIND)
          resolved = unique.values.map do |(target)|
            edge = request.locate(PIPE_KIND, target.fetch("reference"), :index => index).entity
            before = STORE.read(edge)
            check_expected!(before, target.fetch("expected_values", {}))
            [target.fetch("reference"), before]
          end
          Group::Operations.outside_zones!(request, resolved.map { |reference, _before| reference["group_path"] })
          resolved
        end

        def check_expected!(before, expected)
          values = Assignment.values(before)
          changed = expected.keys.reject { |key| values[key] == expected[key] }
          return if changed.empty?

          raise CodedError.new("target.changed", "The Edge changed since it was read (#{changed.join(', ')}).")
        end

        def update(reference, before, after)
          change = if after.nil? then "removed"
                   elsif before then "updated"
                   else "created"
                   end
          { "reference" => reference.merge("entity_id" => Assignment.identity(before)), "before" => before,
            "after" => after, "change" => change }
        end

        # Refuses reference.in_use when a record still names an assignment id these updates remove and no other Edge
        # keeps (a copy keeps it alive). Each record is checked as the reference scan reads it (Group.scannable), so
        # one whose metadata map is malformed is still checked; one invalid otherwise can be no reference target.
        def check_removals!(request, proposal, updates)
          removed = updates.map { |row| row.merge("before" => Group.scannable(row.fetch("before"))) }
                           .select { |row| RECORD_KIND.problems(row.fetch("before")).empty? }
          return if removed.empty?

          gone = removed.map { |row| row.dig("reference", "entity_path") }
          kept = Target.entries(request.model).reject { |entry| gone.include?(entry.key) }
                       .map { |entry| entry.record["id"] }
          checked = plan(removed)
          (removed.map { |row| row.fetch("before").fetch("id") }.uniq - kept).each do |id|
            request.engine.check_identity_removal!(PIPE_KIND, id, :change_set => proposal.record_changes,
                                                                  :reference_plan => checked)
          end
        end

        def propose(proposal, updates)
          return if updates.empty?

          scopes = updates.map { |row| row.dig("reference", "group_path")[0...-1] }.uniq.map do |path|
            PhComposer::Operations::EntityScope.new(path)
          end
          proposal.add_step(LineGroups::EdgeWriteStep.new(:spec => LINE_GROUP, :updates => updates), :scopes => scopes)
        end

        def plan(updates)
          entries, removals = updates.partition { |row| row.fetch("after") }
          Records::ReferencePlan.new(
            :entries => entries.map do |row|
              Records::ReferenceEntry.new(:kind => PIPE_KIND, :key => row.dig("reference", "entity_path"),
                                          :record => row.fetch("after"))
            end,
            :removals => removals.map do |row|
              Records::ReferenceRemoval.new(:kind => PIPE_KIND, :key => row.dig("reference", "entity_path"),
                                            :before => row.fetch("before"))
            end
          )
        end
      end
    end
  end
end
