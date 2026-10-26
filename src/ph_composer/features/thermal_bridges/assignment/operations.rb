# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Assignment
      # Assign, Clear and the rewrite a Thermal Bridge Type delete makes. Each resolves every target before
      # proposing anything and refuses the whole command if one target is stale or unwritable; the
      # dispatcher owns the native operation.
      module Operations
        CONTAINMENT = "ph_composer.zones.containment"
        # What the user can do about an assigned Edge a type delete cannot rewrite where it sits.
        STRANDED_ROUTES = {
          "outside_zone" => "move it into a Zone, or erase it",
          "target.shared_definition" => "open its shared Group with Edit Group and close it, or explode its component",
          "target.locked" => "unlock its Group or Zone",
          "nested_container" => "move it out of the nested container, or erase it",
          "cutting_instance" => "erase it from the cutting component",
          "target.wrong_hierarchy" => "move it out of the nested Zone or container, or erase it"
        }.freeze
        # A refusal names this many stranded Edges in its detail and counts the rest.
        STRANDED_DETAIL = 20

        module_function

        # One record per Edge, all in one step: a fresh `tbe_` id on a first assignment, the Edge's own id on
        # a reassignment, `user_data` kept. An Edge already holding these values is left alone.
        def assign(request, proposal, targets:, thermal_bridge_type_id:, quantity:)
          request.engine.find(TYPE_KIND, thermal_bridge_type_id)
          allocate = Records::Identity.allocator(request, request.params)
          updates = resolve(request, targets).filter_map do |located, before|
            after = before ? DeepCopy.call(before) : new_record(allocate)
            after.merge!("thermal_bridge_type_id" => thermal_bridge_type_id, "quantity" => quantity)
            next if after == before

            update(located, before, Assignment.validate!(after))
          end
          propose(proposal, updates)
          { "edge_ids" => updates.map { |row| row.fetch("after").fetch("id") } }
        end

        # Removes each Edge's assignment, which is what clearing a required reference means. An Edge with
        # no assignment is left alone.
        def clear(request, proposal, targets:)
          updates = resolve(request, targets).filter_map { |located, before| before && update(located, before, nil) }
          check_removals!(request, proposal, updates)
          propose(proposal, updates)
          { "cleared" => updates.length }
        end

        # Delete a Thermal Bridge Type and, in the same proposal and Undo step, move every Edge naming it to
        # `replacement_id`, or clear them when it is nil.
        def delete_type(request, proposal, id:, replacement_id:, expected_values: {})
          raise CodedError.new("params.invalid", "Choose a different replacement type.") if replacement_id == id

          request.engine.find(TYPE_KIND, replacement_id) if replacement_id
          plan = replace_type(request, proposal, :from => id, :to => replacement_id)
          Type::Operations.delete(request, proposal, :id => id, :expected_values => expected_values,
                                                     :reference_plan => plan)
        end

        # The Edges naming type `from`, rewritten to `to`, or cleared when `to` is nil, in this proposal. The
        # returned plan is what the type's delete hands the engine, so its reference check reads the Edges
        # as they will stand. An assigned Edge the rewrite cannot reach refuses the whole delete.
        def replace_type(request, proposal, from:, to:)
          entries = Target.entries(request.model).select { |entry| entry.record["thermal_bridge_type_id"] == from }
          entries.each { |entry| Assignment.validate!(entry.record) }
          rows = contained(request, entries.map(&:key))
          index = request.locate_index(EDGE_KIND)
          updates = []
          stranded = []
          entries.zip(rows).each do |entry, row|
            located, reason = reachable(request, row, entry.record, index)
            if located
              updates << replacement(located, entry.record, to)
            else
              stranded << { "id" => entry.record.fetch("id"), "path" => entry.key, "reason" => reason }
            end
          end
          refuse_stranded(from, stranded) unless stranded.empty?
          check_removals!(request, proposal, updates)
          propose(proposal, updates)
          plan(updates)
        end

        # Each target resolved for writing, as `[located, record]`. Targets are deduplicated by occurrence
        # and bounded before anything is resolved, so an over-limit command refuses without a walk.
        def resolve(request, targets)
          unique = targets.group_by { |target| target.fetch("reference").values_at("zone_path", "entity_path") }
          if unique.values.any? { |group| group.uniq.length > 1 }
            raise CodedError.new("params.invalid", "Repeated Edge targets disagree on identity or expected values.")
          end

          Assignment.check_limit!(unique.length)
          index = request.locate_index(EDGE_KIND)
          unique.values.map do |group|
            target = group.first
            located = request.locate(EDGE_KIND, target.fetch("reference"), :index => index)
            before = STORE.read(located.entity)
            check_expected!(before, target.fetch("expected_values", {}))
            [located, before]
          end
        end

        # The root-to-Edge path, as the records provider keys an entry.
        def key(reference)
          reference.fetch("zone_path") + reference.fetch("entity_path")
        end

        def new_record(allocate)
          { "id" => allocate.call("tbe"), "schema_version" => 1, "user_data" => {}, "extension_data" => {} }
        end

        def update(located, before, after)
          change = if after.nil? then "removed"
                   elsif before then "updated"
                   else "created"
                   end
          { "reference" => located.reference.merge("entity_id" => before&.fetch("id")), "before" => before,
            "after" => after, "change" => change }
        end

        def replacement(located, before, to)
          update(located, before, to && Assignment.validate!(before.merge("thermal_bridge_type_id" => to)))
        end

        # The Edge a stored entry names, located for writing, as `[located, nil]`, or `[nil, reason]` when its
        # containment or its resolution refuses.
        def reachable(request, row, record, index)
          reason = row.fetch("reason") || row.dig("write_refusal", "code")
          return [nil, reason] if reason

          [request.locate(EDGE_KIND, reference(row, record), :index => index), nil]
        rescue CodedError => error
          [nil, error.code]
        end

        # Refuses `reference.in_use` when a record, a readable unavailable extension's included, still names an
        # assignment id these updates remove (context/EXTENSIBILITY.md, "Entity-owned reference targets"). An
        # id a copied Edge outside the updates keeps survives, so only ids no other Edge holds are checked. An
        # invalid record is no resolvable target, so it cannot be referenced and is not checked.
        def check_removals!(request, proposal, updates)
          removed = updates.reject { |row| row.fetch("after") }
                           .select { |row| RECORD_KIND.problems(row.fetch("before")).empty? }
          return if removed.empty?

          gone = removed.map { |row| key(row.fetch("reference")) }
          kept = Target.entries(request.model).reject { |entry| gone.include?(entry.key) }
                       .map { |entry| entry.record["id"] }
          checked = plan(removed)
          (removed.map { |row| row.fetch("before").fetch("id") }.uniq - kept).each do |id|
            request.engine.check_identity_removal!(EDGE_KIND, id, :change_set => proposal.record_changes,
                                                                  :reference_plan => checked)
          end
        end

        def check_expected!(before, expected)
          values = Assignment.values(before)
          changed = expected.keys.reject { |key| values[key] == expected[key] }
          return if changed.empty?

          raise CodedError.new("target.changed", "The Edge changed since it was read (#{changed.join(', ')}).")
        end

        # Zones' containment of each root-to-Edge path, read in pages its bound admits.
        def contained(request, paths)
          paths.each_slice(Pages::MAXIMUM_LIMIT).flat_map do |slice|
            request.query(CONTAINMENT, "paths" => slice).fetch("paths")
          end
        end

        def reference(row, record)
          { "zone_id" => row.dig("zone", "zone_id"), "zone_path" => row.dig("zone", "zone_path"),
            "entity_path" => row.fetch("entity_path"), "entity_id" => record.fetch("id") }
        end

        def propose(proposal, updates)
          return if updates.empty?

          scopes = updates.map { |row| row.fetch("reference").fetch("zone_path")[0...-1] }.uniq.map do |path|
            PhComposer::Operations::EntityScope.new(path)
          end
          proposal.add_step(WriteStep.new(:updates => updates), :scopes => scopes)
        end

        def plan(updates)
          entries, removals = updates.partition { |row| row.fetch("after") }
          Records::ReferencePlan.new(
            :entries => entries.map do |row|
              Records::ReferenceEntry.new(:kind => EDGE_KIND, :key => key(row.fetch("reference")),
                                          :record => row.fetch("after"))
            end,
            :removals => removals.map do |row|
              Records::ReferenceRemoval.new(:kind => EDGE_KIND, :key => key(row.fetch("reference")),
                                            :before => row.fetch("before"))
            end
          )
        end

        def refuse_stranded(id, rows)
          routes = rows.map { |row| STRANDED_ROUTES.fetch(row.fetch("reason"), "resolve #{row.fetch('reason')}") }
          raise CodedError.new("reference.in_use",
                               "#{rows.length} Edge(s) still use Thermal Bridge Type #{id} where the replacement " \
                               "cannot reach them. For each, #{routes.uniq.join('; or ')}, then delete again.",
                               "target_kind" => TYPE_KIND, "id" => id, "edges" => rows.first(STRANDED_DETAIL),
                               "stranded" => rows.length)
        end
      end
    end
  end
end
