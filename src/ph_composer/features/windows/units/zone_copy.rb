# frozen_string_literal: true

require_relative "identity_plan"

module PhComposer
  module Windows
    module Units
      # Windows' part of a Zone occurrence becoming independent (Zones::TRANSITION). Every Unit inside
      # the occurrence whose id another occurrence also holds gets a new id in the Zone's own proposal,
      # so the copy and its Units are independent in one Undo step. Units elsewhere are untouched; the
      # repair on the next Windows mutation stays the fallback for every other copy route.
      module ZoneCopy
        NAME = "#{FEATURE_ID}.units.follow_zone_copy"

        module_function

        REFUSES = %w[copy.rule_missing extension.invalid identity.conflict reference.invalid target.changed
                     target.locked target.shared_definition validation.failed].freeze

        def install(feature)
          feature.transition_contributor(NAME, :transition => Zones::TRANSITION, :refuses => REFUSES) do |*args|
            contribute(*args)
          end
        end

        def contribute(request, proposal, description)
          zone_path = description.fetch("zone_path")
          inside = Occurrences.under(request.model, zone_path).sort_by(&:path)
          updates = updates(request, inside, Occurrences.held_ids(request.model, :except => zone_path), description)
          return [] if updates.empty?

          step = ZoneCopyStep.new(:zone_path => zone_path, :inside => inside, :updates => updates)
          proposal.add_step(step, :scopes => [])
          step.affected
        end

        # Every Unit inside the occurrence whose id is also held elsewhere gets a new id; every Unit
        # inside whose payloads name a reidentified Unit, the Zone or its Faces is remapped too. Only
        # the changed Units are returned.
        def updates(request, inside, held, description)
          allocator = Records::Identity.allocator(request, "transition" => Zones::TRANSITION,
                                                           "zone_id" => description.fetch("new_zone_id"))
          ids = held + inside.map { |item| item.record.fetch("id") }
          updates = inside.map do |item|
            after = DeepCopy.call(item.record)
            if held.include?(item.record.fetch("id"))
              after["id"] = allocator.call("wun")
              if ids.include?(after["id"])
                raise CodedError.new("identity.conflict", "The allocated Window identity already exists.")
              end

              ids << after["id"]
            end
            IdentityPlan::Update.new(:reference => item.reference, :before => DeepCopy.call(item.record),
                                     :after => after)
          end
          copy_extensions(request, updates, description)
          inside.zip(updates).reject { |_item, update| update.after == update.before }.map do |item, update|
            if item.locked
              raise CodedError.new("target.locked", "Unlock the copied Window before making its Zone independent.")
            end

            Units.validate!(update.after)
            update
          end
        end

        # Structured payloads are remapped across the whole copied collection, typed by the plan: to
        # the Zone's and Faces' new ids and to sibling Units' new ids; anything else, such as a Type,
        # keeps its id. An id two copied Units share maps each to its own new id, never a sibling's, and
        # a payload naming such an id on another Unit cannot say which copy it meant, so it refuses.
        def copy_extensions(request, updates, description)
          counts = updates.map { |update| update.before.fetch("id") }.tally
          shared = description.fetch("mapping").merge(updates.each_with_object({}) do |update, mapping|
            old_id = update.before.fetch("id")
            mapping[old_id] = update.after.fetch("id") if counts[old_id] == 1
          end)
          parent = description.fetch("references").map do |row|
            Records::ReferenceEntry.new(:kind => row.fetch("kind"), :key => row.fetch("key"),
                                        :record => row.fetch("record"))
          end
          plan = Records::ReferencePlan.new(:entries => parent + updates.map do |update|
            Records::ReferenceEntry.new(:kind => REFERENCE_KIND, :key => update.reference.fetch("entity_path"),
                                        :record => update.after)
          end)
          updates.each do |update|
            data = update.before.fetch("extension_data", {})
            next if data.empty?

            old_id = update.before.fetch("id")
            Records::Extension.check_copy_rules!(data, request.registry.catalog, "Window unit", old_id)
            refuse_ambiguous!(data, counts, old_id)
            mapping = shared.merge(old_id => update.after.fetch("id"))
            update.after["extension_data"] = Records::Extension.copy_data(data, request.registry.catalog, "Window unit",
                                                                          old_id, mapping, :engine => request.engine,
                                                                                           :reference_plan => plan)
          end
        end

        def refuse_ambiguous!(data, counts, own_id)
          named = data.each_value.flat_map do |envelope|
            Records::Extension.referenced_ids(envelope.fetch("payload"), envelope.fetch("references", []))
          end
          return unless named.any? { |kind, id| kind == REFERENCE_KIND && id != own_id && counts.fetch(id, 0) > 1 }

          raise CodedError.new("reference.invalid", "A copied Window's payload names an identity several copied " \
                                                    "Windows share, so its target is ambiguous.")
        end
        private_class_method :updates, :copy_extensions, :refuse_ambiguous!
      end

      # Make Unique replaces every entity inside the copy, so the step binds logically: each Unit by its
      # record id and its ordinal among the occurrence's Units with that id in path order. At apply it
      # re-enumerates the isolated occurrence and requires the same Units with the same records; two
      # Units sharing an id have equal pre-images, so the ordinal is only a tiebreak.
      class ZoneCopyStep
        attr_reader :affected

        def initialize(zone_path:, inside:, updates:)
          @zone_path = DeepCopy.call(zone_path).freeze
          @counts = inside.group_by { |item| item.record.fetch("id") }.transform_values(&:length).freeze
          ordinals = Hash.new(-1)
          positions = inside.sort_by(&:path).to_h { |item| [item.path, ordinals[item.record.fetch("id")] += 1] }
          @bindings = updates.map do |update|
            { "ordinal" => positions.fetch(update.reference.fetch("entity_path")),
              "before" => DeepCopy.call(update.before), "after" => DeepCopy.call(update.after) }
          end.freeze
          @affected = @bindings.map do |row|
            renamed = row.fetch("after").fetch("id") != row.fetch("before").fetch("id")
            { "kind" => REFERENCE_KIND, "id" => row.fetch("after").fetch("id"),
              "change" => renamed ? "identity_repaired" : "updated" }
          end
          @captured = nil
        end

        def descriptor
          { "name" => "follow_zone_copy", "zone_path" => @zone_path, "bindings" => DeepCopy.call(@bindings) }
        end

        def temporary_ids
          @bindings.map { |row| row.fetch("after").fetch("id") }.reject do |id|
            @bindings.any? { |row| row.fetch("before").fetch("id") == id }
          end
        end

        def apply(model, _slots)
          inside = Occurrences.under(model, @zone_path)
          groups = inside.group_by { |item| item.record.fetch("id") }.transform_values { |rows| rows.sort_by(&:path) }
          unless groups.transform_values(&:length) == @counts
            raise CodedError.new("target.changed", "The copied Zone's Windows changed after it was previewed.")
          end

          resolved = @bindings.map do |row|
            item = groups.fetch(row.fetch("before").fetch("id")).fetch(row.fetch("ordinal"))
            unless item.record == row.fetch("before")
              raise CodedError.new("target.changed", "A copied Window record changed after it was previewed.")
            end

            Occurrences.mutable!(item)
            [item.entity, row.fetch("after")]
          end
          @captured = resolved.map { |entity, _record| [entity, Units.read(entity)] }
          resolved.each { |entity, record| Units.write(entity, record) }
        end

        # Writes back the records apply replaced; nothing when apply did not reach its writes.
        def restore
          Units.restore_all(@captured)
        end
      end
    end
  end
end
