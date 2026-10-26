# frozen_string_literal: true

require_relative "remove_step"
require_relative "rehost_step"
require_relative "swap_step"
require_relative "reset_step"
require_relative "flip_step"
require_relative "restore_step"
require_relative "read_context"
require_relative "identity_step"

module PhComposer
  module Windows
    module Units
      module Repairs
        module_function

        def targets(model, references)
          unless references.map { |reference| reference.fetch("entity_path") }.uniq.length == references.length
            raise CodedError.new("params.invalid", "Choose each Window occurrence once.")
          end

          references.map { |reference| Occurrences.resolve(model, reference, :mutable => true) }
        end

        # New identities for the copies sharing each chosen Unit's identity, and nothing else; the
        # automatic repair every other Windows action makes is the same plan over every copy.
        def copied_identities(request, proposal, units:)
          items = targets(request.model, units)
          occurrences = Occurrences.all(request.model)
          counts = occurrences.map { |item| item.record.fetch("id") }.tally
          unless items.all? { |item| counts.fetch(item.record.fetch("id")) > 1 }
            raise CodedError.new("params.invalid", "Choose Windows whose identity is shared with a copy.")
          end

          updates = IdentityPlan.build(occurrences, :identity => Records::Identity.allocator(request, "units" => units),
                                                    :catalog => request.registry.catalog, :engine => request.engine,
                                                    :only => items.map { |item| item.record.fetch("id") })
          proposal.add_step(IdentityStep.new(updates), :scopes => [MutationScope.new])
          { "repairs" => updates.map do |update|
            { "entity_path" => update.reference.fetch("entity_path"), "old_unit_id" => update.before.fetch("id"),
              "new_unit_id" => update.after.fetch("id") }
          end }
        end

        def projected_records(request, proposal)
          Occurrences.all(request.model).to_h { |item| [item.path, Mutation.record(proposal, item)] }
        end

        # `pane_paths` are the orphaned panes the new Unit adopts on `host`.
        def restore(request, proposal, host:, type_id:, pane_paths:)
          seed = { "host" => host, "type_id" => type_id, "pane_paths" => pane_paths }
          identity = Records::Identity.allocator(request, seed)
          Mutation.prepare(request, proposal, :identity => identity)
          reads = ReadContext.new(request)
          host = reads.host_reference(host)
          type = request.engine.find(TYPE_KIND, type_id)
          record = { "id" => identity.call("wun"), "schema_version" => 1,
                     "window_type_id" => type.fetch("id"), "anchor" => Anchors::DEFAULT }
          step = RestoreStep.new(:model => request.model, :host => host, :type => type, :record => record,
                                 :pane_paths => pane_paths, :existing_polygons_m => reads.other_polygons)
          proposal.add_step(step, :scopes => step.scopes)
          { "unit_id" => record.fetch("id") }
        end

        # `name` defaults to "<source name> (flipped)".
        def new_flipped_type(request, proposal, unit:, name: nil)
          item = Occurrences.resolve(request.model, unit, :mutable => true)
          Mutation.prepare(request, proposal)
          expected = projected_records(request, proposal)
          reads = ReadContext.new(request)
          source = request.engine.find(TYPE_KIND, item.record.fetch("window_type_id"))
          target = flipped_type(request, proposal, source, :name => name, :seed => { "unit" => unit, "name" => name })
          step = FlipStep.new(:model => request.model, :source_type => source, :target_type => target,
                              :reference => item.reference, :expected_record => expected.fetch(item.path),
                              :expected_records => expected,
                              :host => reads.host(item),
                              :other_polygons_m => reads.other_polygons(:except => [item.path]))
          proposal.add_step(step, :scopes => [step.scope])
          step.findings.each { |finding| proposal.add_finding(finding) }
          { "unit_id" => expected.fetch(item.path).fetch("id"), "type_id" => target.fetch("id") }
        end

        def flipped_type(request, proposal, source, name:, seed:)
          identity = Records::Identity.allocator(request, seed)
          rows = Definitions.records(request, Types::KIND)
          name ||= Records::Names.copy_name("#{source.fetch('name')} (flipped)", rows)
          Records::Names.unique!(name, rows)
          mapping = request.engine.propose_duplicate(TYPE_KIND, [source.fetch("id")], proposal) do |values|
            values["name"] = name.strip
            values["source"] = { "kind" => "derived" }
            values["datasheet_links"] = []
            values["product_photos"] = []
            values.fetch("elements").each { |element| element["id"] = identity.call("wel") }
            GridOperations.flip(values)
          end
          proposal.find(TYPE_KIND, mapping.fetch(source.fetch("id"))).after
        end
        private_class_method :flipped_type

        def swap_type(request, proposal, units:, type_id:)
          items = targets(request.model, units)
          Mutation.prepare(request, proposal)
          expected = projected_records(request, proposal)
          reads = ReadContext.new(request)
          type = request.engine.find(TYPE_KIND, type_id)
          others = reads.other_polygons(:except => items.map(&:path))
          step = SwapStep.new(:model => request.model, :target_type => type, :expected_records => expected,
                              :items => items.map do |item|
                                          { :reference => item.reference, :expected_record => expected.fetch(item.path),
                                            :from_type => reads.type(item), :host => reads.host(item),
                                            :other_polygons_m => others }
                                        end)
          proposal.add_step(step, :scopes => [step.scope]) if step.needed?
          { "unit_ids" => items.map { |item| expected.fetch(item.path).fetch("id") } }
        end

        def reset_to_type(request, proposal, units:)
          items = targets(request.model, units)
          ids = items.map { |item| item.record.fetch("window_type_id") }.uniq
          unless ids.length == 1
            raise CodedError.new("params.invalid", "Reset one Window Type at a time.")
          end

          Mutation.prepare(request, proposal)
          expected = projected_records(request, proposal)
          reads = ReadContext.new(request)
          type = request.engine.find(TYPE_KIND, ids.first)
          rows = reads.occurrences.select { |item| item.record.fetch("window_type_id") == ids.first }
          hosts = rows.to_h { |item| [item.path, reads.host(item, :writable => false)] }
          outlines = reads.occurrences.to_h { |item| [item.path, reads.read_polygon(item)] }
          step = ResetStep.new(:model => request.model, :type => type, :expected_records => expected,
                               :items => items.map { |item|
                                           { :reference => item.reference,
                                             :expected_record => expected.fetch(item.path) }
                                         }, :hosts => hosts, :outline_inventory_m => outlines)
          proposal.add_step(step, :scopes => [step.scope]) if step.needed?
          step.findings.each { |finding| proposal.add_finding(finding) }
          { "unit_ids" => items.map { |item| expected.fetch(item.path).fetch("id") } }
        end

        def remove(request, proposal, units:)
          items = targets(request.model, units)
          Mutation.prepare(request, proposal)
          expected = projected_records(request, proposal)
          steps = items.map do |item|
            RemoveStep.new(:model => request.model, :reference => item.reference,
                           :expected_record => expected.fetch(item.path))
          end
          removed_paths = items.map(&:path)
          remaining = Occurrences.all(request.model).reject { |item| removed_paths.include?(item.path) }
          plan = Records::ReferencePlan.new(:entries => remaining.map do |item|
            Records::ReferenceEntry.new(:kind => REFERENCE_KIND, :key => item.path,
                                        :record => expected.fetch(item.path))
          end, :removals => steps.zip(items).map { |step, item| step.removal(:before_record => item.record) })
          steps.each do |step|
            id = step.affected.first.fetch("id")
            request.engine.check_identity_removal!(REFERENCE_KIND, id, :change_set => proposal.record_changes,
                                                                       :reference_plan => plan)
          end
          steps.each do |step|
            reference = step.affected.first.fetch("reference")
            proposal.add_step(step, :scopes => [
              MutationScope.new,
              PhComposer::Operations::EntityScope.new(reference.fetch("entity_path")[0...-1])
            ])
          end
          { "unit_ids" => steps.map { |step| step.affected.first.fetch("id") } }
        end

        def rehost(request, proposal, unit:, host:)
          item = Occurrences.resolve(request.model, unit, :mutable => true)
          Mutation.prepare(request, proposal)
          expected = projected_records(request, proposal)
          reads = ReadContext.new(request)
          host = reads.host_reference(host)
          type = request.engine.find(TYPE_KIND, item.record.fetch("window_type_id"))
          definition_ids = reads.occurrences.map { |row| row.entity.definition.persistent_id }
          scope = MutationScope.new(:definition_ids => definition_ids)
          guard = scope.capture(request.model, :expected_records => expected)
          step = RehostStep.new(:model => request.model, :reference => item.reference,
                                :expected_record => expected.fetch(item.path), :host => host, :type => type,
                                :existing_polygons_m => reads.other_polygons(:except => [item.path]),
                                :expected_scope => scope, :expected_state => guard)
          proposal.add_step(step, :scopes => [scope])
          { "unit_id" => expected.fetch(item.path).fetch("id") }
        end
      end
    end
  end
end
