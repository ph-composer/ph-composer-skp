# frozen_string_literal: true

module PhComposer
  module Ducting
    module Assignment
      # Assign, Clear and the rewrite a Duct Type delete makes. Each resolves every target before proposing anything
      # and refuses the whole command if one is stale, outside a Ducting group, in a Ducting group a Zone holds or
      # behind a write refusal; the dispatcher owns the native operation.
      module Operations
        STRANDED_DETAIL = 20
        # What a first assignment must be given; a reassign keeps what it is not given.
        FIRST_NEEDS = %w[duct_type_id direction].freeze

        module_function

        # One record per Edge, all in one step: a fresh `dce_` id and quantity 1 on a first assignment, the Edge's own
        # id, metadata and values on a reassignment, with `values` (any of duct_type_id, direction and quantity)
        # written over them.
        def assign(request, proposal, targets:, values:)
          request.engine.find(DUCT_TYPE_KIND, values["duct_type_id"]) if values.key?("duct_type_id")
          allocate = Records::Identity.allocator(request, request.params)
          updates = resolve(request, targets).filter_map do |reference, before|
            check_rewritable!(before, values)
            after = { "user_data" => {}, "extension_data" => {}, "quantity" => 1 }
                    .merge((before || {}).slice("id", "user_data", "extension_data", *VALUE_SCHEMAS.keys))
                    .merge("schema_version" => 1).merge(values)
            after["id"] = allocate.call(RECORD_KIND.id_prefix) unless LINE_GROUP.edge_identity(after)
            next if after == before

            update(reference, before, Assignment.validate!(after))
          end
          propose(proposal, updates)
          { "edge_ids" => updates.map { |row| row.fetch("after").fetch("id") } }
        end

        # A record of another schema version, which this version cannot rewrite, refuses; an Edge with none needs a
        # Duct Type and a direction, since a duct with no direction cannot be written.
        def check_rewritable!(before, values)
          if before && before["schema_version"] != 1
            raise CodedError.new("validation.failed", "An Edge's duct assignment is schema version " \
                                                      "#{before['schema_version'].inspect}, which this version " \
                                                      "cannot rewrite.")
          end
          missing = before ? [] : FIRST_NEEDS - values.keys
          return if missing.empty?

          raise CodedError.new("params.invalid", "An Edge with no duct assignment needs #{missing.join(' and ')}.")
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

        # Delete a Duct Type and, in the same proposal and Undo step, move every duct naming it to `replacement_id`,
        # or null their type when it is nil. Without a replacement the engine refuses a type in use.
        # A stale `expected_values` refuses as target.changed before any duct is planned, so a duct the rewrite cannot
        # reach never hides it.
        def delete_type(request, proposal, id:, expected_values:, replacement_id:)
          keep = replacement_id.equal?(DuctType::Operations::KEEP)
          type = request.engine.find(DUCT_TYPE_KIND, id)
          changed = expected_values.keys.reject { |key| type[key] == expected_values[key] }
          unless changed.empty?
            raise CodedError.new("target.changed", "The Duct Type changed since it was read (#{changed.join(', ')}).")
          end

          DuctType::Operations.check_replacement!(request, id, replacement_id) unless keep
          plan = replace_type(request, proposal, :from => id, :to => replacement_id) unless keep
          DuctType::Operations.delete(request, proposal, :id => id, :expected_values => expected_values,
                                                         :reference_plan => plan)
        end

        # The ducts naming type `from`, rewritten to `to` (nil nulls it), in this proposal; the plan the type's delete
        # hands the engine. A duct the rewrite cannot reach, outside a Ducting group or behind a locked or shared step,
        # refuses the whole delete.
        def replace_type(request, proposal, from:, to:)
          updates = []
          stranded = []
          index = request.locate_index(DUCT_KIND)
          LineGroups::EdgeTarget.entries(LINE_GROUP, request.model).each do |entry|
            next unless entry.record["duct_type_id"] == from

            reference = { "group_path" => entry.key[0...-1], "entity_path" => entry.key,
                          "entity_id" => entry.record["id"] }
            begin
              # The scan found it; the rewrite starts from the record as stored, which must be valid.
              before = Assignment.validate!(STORE.read(request.locate(DUCT_KIND, reference, :index => index).entity))
              updates << update(reference, before, Assignment.validate!(before.merge("duct_type_id" => to)))
            rescue CodedError => error
              stranded << { "path" => entry.key, "reason" => error.code }
            end
          end
          refuse_stranded(from, stranded) unless stranded.empty?

          propose(proposal, updates)
          plan(updates)
        end

        def refuse_stranded(from, stranded)
          message = "#{stranded.length} duct(s) use Duct Type #{from} where the delete cannot rewrite them " \
                    "(outside a Ducting group, in a nested one, locked, shared or invalid); move, unlock, make " \
                    "them unique or clear them, then delete again."
          raise CodedError.new("reference.in_use", message, "target_kind" => DUCT_TYPE_KIND, "id" => from,
                                                            "edges" => stranded.first(STRANDED_DETAIL),
                                                            "stranded" => stranded.length)
        end

        # Each target resolved for writing, as `[reference, record]`, deduplicated by Edge and bounded before any
        # walk; the Ducting groups they sit in are checked against the Zones once.
        def resolve(request, targets)
          unique = targets.group_by { |target| target.dig("reference", "entity_path") }
          if unique.values.any? { |group| group.uniq.length > 1 }
            raise CodedError.new("params.invalid", "Repeated Edge targets disagree on identity or expected values.")
          end

          Assignment.check_limit!(unique.length)
          index = request.locate_index(DUCT_KIND)
          resolved = unique.values.map do |(target)|
            edge = request.locate(DUCT_KIND, target.fetch("reference"), :index => index).entity
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
          { "reference" => reference.merge("entity_id" => LINE_GROUP.edge_identity(before)), "before" => before,
            "after" => after, "change" => change }
        end

        # Refuses reference.in_use when a record still names an assignment id these updates remove and no Edge the
        # command leaves keeps (a copy keeps it alive). Every removed record with a `dce_` id is checked, whatever else
        # is wrong with it, since a referrer can name it; the plan the check projects holds the valid ones, read as
        # the reference scan reads them (LineGroups.scannable), since the engine refuses an invalid planned record.
        def check_removals!(request, proposal, updates)
          return if updates.empty?

          removed = updates.map { |row| row.merge("before" => LineGroups.scannable(row.fetch("before"))) }
          gone = removed.map { |row| row.dig("reference", "entity_path") }
          kept = LineGroups::EdgeTarget.entries(LINE_GROUP, request.model).reject { |entry| gone.include?(entry.key) }
                                       .map { |entry| entry.record["id"] }
          checked = plan(removed.select { |row| RECORD_KIND.problems(row.fetch("before")).empty? })
          (removed.filter_map { |row| LINE_GROUP.edge_identity(row.fetch("before")) }.uniq - kept).each do |id|
            request.engine.check_identity_removal!(DUCT_KIND, id, :change_set => proposal.record_changes,
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
              Records::ReferenceEntry.new(:kind => DUCT_KIND, :key => row.dig("reference", "entity_path"),
                                          :record => row.fetch("after"))
            end,
            :removals => removals.map do |row|
              Records::ReferenceRemoval.new(:kind => DUCT_KIND, :key => row.dig("reference", "entity_path"),
                                            :before => row.fetch("before"))
            end
          )
        end
      end
    end
  end
end
