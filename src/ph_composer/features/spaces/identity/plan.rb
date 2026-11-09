# frozen_string_literal: true

module PhComposer
  module Spaces
    # Make independent, planned: the one occurrence the caller named, a copy of a Space, Volume or Floor
    # Segment, takes a new id, whichever of the copies it is; nothing chooses for the caller. Every other
    # record inside it takes a new id too, except that an id no occurrence outside the target holds keeps
    # one holder inside it, the first in path order that is not the target. So no identity disappears from
    # the Model and nothing outside the copy loses its target. The named Space takes `number`, a renamed
    # Volume a new Space Floor (`floor_id`). `user_data` stays as copied; extension payloads inside the copy
    # follow their declared copy rules, each remapped to its own record's new id and to renamed records no
    # other record in the copy shares an id with. Pure but for the allocator.
    module IdentityPlan
      # One record to rewrite, bound logically: its kind, its id and its ordinal among the target's records
      # of that kind and id in path order, because isolating storage replaces every entity inside.
      Row = Struct.new(:kind, :ordinal, :before, :after, keyword_init: true)
      # `counts` is every record inside the target per [kind, id], what the step finds again at apply.
      Plan = Struct.new(:rows, :counts, keyword_init: true)
      # While planning: the occurrence a Row rewrites, which extension copying needs for its references.
      Planned = Struct.new(:occurrence, :row, keyword_init: true)

      module_function

      # `scope` is the path whose records are rewritten: the named target's own, or a copied Zone's. With
      # no target (a Zone copy), numbers are kept and `parent` carries the Zone's `mapping` of old to new
      # ids and its `references` (Records::ReferenceEntry rows), so payloads and a Space's `zone_id` follow
      # the Zone's ids too.
      def build(scan, target, number:, allocate:, catalog:, engine:, scope: target.path, parent: nil)
        refuse!(scan, Resolve.kind_of(target.reference), target) if target
        inside = Authoring.inside(scan, scope).sort_by { |_kind, occurrence| occurrence.path }
        inside.each { |_kind, occurrence| refuse_lock!(occurrence) }
        keys = inside.map { |row_kind, occurrence| [row_kind, occurrence.path] }
        everywhere = Resolve::TARGETS.flat_map do |row_kind, kind_target|
          kind_target.occurrences_in(scan).map { |occurrence| [row_kind, occurrence] }
        end
        taken = everywhere.map { |_row_kind, occurrence| occurrence.record.fetch("id") }
        held = everywhere.reject { |row_kind, occurrence| keys.include?([row_kind, occurrence.path]) }
                         .map { |_row_kind, occurrence| occurrence.record.fetch("id") }
        keepers = keepers(inside, target, held)
        ordinals = Hash.new(-1)
        planned = inside.map do |row_kind, occurrence|
          before = occurrence.record
          ordinal = ordinals[[row_kind, before.fetch("id")]] += 1
          after = DeepCopy.call(before)
          zone_id = after["zone_id"]
          after["zone_id"] = parent.fetch(:mapping).fetch(zone_id, zone_id) if parent && zone_id
          unless keepers.any? { |keeper| keeper.equal?(occurrence) }
            after["id"] = fresh(allocate, KINDS.fetch(row_kind).id_prefix, taken)
            after["floor_id"] = fresh(allocate, FLOOR_PREFIX, taken) if row_kind == VOLUME_KIND
            after["number"] = number if target && occurrence.equal?(target) && number
          end
          Planned.new(:occurrence => occurrence,
                      :row => Row.new(:kind => row_kind, :ordinal => ordinal, :before => before, :after => after))
        end
        copy_extensions(planned, catalog, engine, parent)
        rows = planned.map(&:row).reject { |row| row.after == row.before }
        rows.each { |row| Spaces.validate!(KINDS.fetch(row.kind), row.after) }
        Plan.new(:rows => rows,
                 :counts => inside.map { |row_kind, occurrence| [row_kind, occurrence.record.fetch("id")] }.tally)
      end

      # The named occurrence must be one of several carrying its id, in storage it can be given alone. A
      # Space inside a component or a copied container is refused first, whatever its id count, because no
      # Spaces repair can isolate that storage.
      def refuse!(scan, kind, target)
        kind_target = Resolve::TARGETS.fetch(kind)
        label = kind_target.label
        if target.shared_above
          raise CodedError.new("target.shared_definition",
                               "That #{label} is inside storage a component or a copied Group above it shares. Draw " \
                               "the Space directly, or make that container unique first. Nothing was written.")
        end
        copies = kind_target.occurrences_in(scan).count do |occurrence|
          occurrence.record.fetch("id") == target.record.fetch("id")
        end
        unless copies > 1
          raise CodedError.new("space.identity_unique", "That #{label} already has an identity of its own. " \
                                                        "Nothing was written.")
        end
        refuse_lock!(target)
      end

      # The occurrences inside the target that keep their id: one per id held nowhere outside it.
      def keepers(inside, target, held)
        inside.group_by { |row_kind, occurrence| [row_kind, occurrence.record.fetch("id")] }
              .reject { |(_row_kind, id), _group| held.include?(id) }
              .filter_map do |_key, group|
                group.map(&:last).find { |occurrence| target.nil? || !occurrence.equal?(target) }
              end
      end

      def refuse_lock!(occurrence)
        return unless occurrence.locked

        raise CodedError.new("target.locked", "A Group being made independent, or one above it, is locked. Nothing " \
                                              "was written.")
      end

      def fresh(allocate, prefix, taken)
        id = allocate.call(prefix)
        if taken.include?(id)
          raise CodedError.new("identity.conflict", "The allocated identity already exists. Nothing was written.")
        end

        taken << id
        id
      end

      # Each payload inside the copy is remapped to its own record's new id and to every renamed record
      # whose old id no other record inside the copy holds. A payload naming another id that several
      # records inside the copy hold, renamed or kept, names none of them unambiguously, and refuses.
      def copy_extensions(planned, catalog, engine, parent)
        rows = planned.map(&:row)
        counts = rows.map { |row| row.before.fetch("id") }.tally
        shared = rows.each_with_object(DeepCopy.call(parent ? parent.fetch(:mapping) : {})) do |row, mapping|
          old_id = row.before.fetch("id")
          mapping[old_id] = row.after.fetch("id") if counts[old_id] == 1 && row.after.fetch("id") != old_id
        end
        entries = planned.map do |item|
          Records::ReferenceEntry.new(:kind => item.row.kind, :key => item.occurrence.path, :record => item.row.after)
        end
        plan = Records::ReferencePlan.new(:entries => (parent ? parent.fetch(:references) : []) + entries)
        rows.each do |row|
          data = row.before.fetch("extension_data", {})
          next if data.empty?

          old_id = row.before.fetch("id")
          label = KINDS.fetch(row.kind).label
          Records::Extension.check_copy_rules!(data, catalog, label, old_id)
          refuse_ambiguous!(data, counts, old_id)
          row.after["extension_data"] = Records::Extension.copy_data(data, catalog, label, old_id,
                                                                     shared.merge(old_id => row.after.fetch("id")),
                                                                     :engine => engine, :reference_plan => plan)
        end
      end

      def refuse_ambiguous!(data, counts, own_id)
        named = data.each_value.flat_map do |envelope|
          Records::Extension.referenced_ids(envelope.fetch("payload"), envelope.fetch("references", [])).map(&:last)
        end
        return unless named.any? { |id| id != own_id && counts.fetch(id, 0) > 1 }

        raise CodedError.new("reference.invalid", "A payload in the copy names an identity several records in the " \
                                                  "copy share, so its target is ambiguous. Nothing was written.")
      end
      private_class_method :keepers, :refuse_lock!, :fresh, :copy_extensions, :refuse_ambiguous!
    end
  end
end
