# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Serves
      # Assign, Clear and the Zone half of an item's delete. Each reads the Zones once, checks every target before
      # anything is staged, builds each Zone's whole new payload and hands it to Zones' `stage_extension`, so the
      # command is one Undo step, Zones' write refusals (a locked Group, a shared definition, a Zone inside a Zone)
      # pass through unchanged and no Zone record is written here.
      module Operations
        # What `delete` takes for a replacement when the caller named none, as against null, which clears.
        KEEP = Object.new.freeze

        module_function

        # Names `item_id` in `slot` on each target. A single slot that already names another item refuses
        # mechanical.slot_filled, naming it, unless `replace`.
        def assign(request, proposal, targets:, slot:, item_id:, replace: false)
          slot = slot!(slot)
          unless slot.id?(item_id)
            raise CodedError.new("params.invalid", "#{slot.key} takes a #{slot.label} id; #{item_id} is not one.")
          end

          zones = targets!(State.zones(request), targets)
          item = request.engine.find(slot.kind, item_id)
          payloads = zones.to_h do |zone|
            current = zone.values.fetch(slot.key)
            filled!(request, zone, slot, current, item_id) unless replace || slot.many?
            value = slot.many? ? (current + [item_id]).uniq : item_id
            [zone, zone.values.merge(slot.key => value)]
          end
          State.stage(request, payloads)
          { "zone_ids" => zones.map(&:id), "slot" => slot.key, "item_id" => item.fetch("id") }
        rescue StandardError => error
          proposal.refuse(error)
          raise
        end

        # Empties `slot`, or every slot when nil, on each target; with `item_id`, takes only that item out of the
        # slot, which a list slot (several indoor units, heaters, pumps or fans on one Zone) needs. A Zone that stores
        # no payload is left as it is.
        def clear(request, proposal, targets:, slot: nil, item_id: nil)
          slot = slot && slot!(slot)
          raise CodedError.new("params.invalid", "item_id needs its slot.") if item_id && slot.nil?
          if item_id && !slot.id?(item_id)
            raise CodedError.new("params.invalid", "#{slot.key} takes a #{slot.label} id; #{item_id} is not one.")
          end

          zones = targets!(State.zones(request), targets)
          payloads = zones.select(&:status).to_h do |zone|
            value = slot && (item_id ? slot.renamed(zone.values.fetch(slot.key), item_id, nil) : slot.empty)
            [zone, slot ? zone.values.merge(slot.key => value) : EMPTY.dup]
          end
          State.stage(request, payloads)
          { "zone_ids" => zones.map(&:id), "slot" => slot&.key }
        rescue StandardError => error
          proposal.refuse(error)
          raise
        end

        # An item's delete with the Zones that name it, in one proposal and one Undo step (the Assembly delete
        # contract): `replacement` is KEEP when the caller named none, so a Zone naming the item refuses
        # reference.in_use, naming the Zones; an id moves every slot naming the item to it; nil empties them. A
        # stale `expected_values` refuses before any Zone is read. The block deletes the item itself, given the
        # reference plan that projects the moved Zones.
        def delete(request, proposal, kind, id:, expected_values:, replacement:)
          stale!(request, kind, id, expected_values)
          yield release(request, kind, id, replacement)
        rescue StandardError => error
          proposal.refuse(error)
          raise
        end

        # Only an understood payload is rebuilt; any other stays as stored, and the engine's incoming check then
        # refuses the delete.
        def release(request, kind, id, replacement)
          slots = SLOTS.select { |slot| slot.kind == kind }
          users = State.zones(request).select do |zone|
            zone.status == "understood" && slots.any? { |slot| slot.names?(zone.values.fetch(slot.key), id) }
          end
          if replacement == KEEP
            in_use!(request, kind, id, users) unless users.empty?
            return plan(State.entries(request))
          end

          check_replacement!(request, kind, id, replacement)
          shared = users.group_by(&:id).values.find { |group| group.length > 1 }
          if shared
            raise CodedError.new("target.ambiguous", "Zone #{label(shared.first)} has #{shared.length} occurrences " \
                                                     "sharing its id; make the copy independent first.")
          end

          payloads = users.to_h do |zone|
            moved = slots.to_h { |slot| [slot.key, slot.renamed(zone.values.fetch(slot.key), id, replacement)] }
            [zone, zone.values.merge(moved)]
          end
          State.stage(request, payloads)
          plan(State.entries(request))
        end

        def plan(entries)
          Records::ReferencePlan.new(:entries => entries.map do |entry|
            Records::ReferenceEntry.new(:kind => entry.fetch("kind"), :key => entry.fetch("key"),
                                        :record => entry.fetch("record"))
          end, :removals => [])
        end

        # ---------------------------------------------------------------- shared steps

        def slot!(key)
          Payload.slot(key) || raise(CodedError.new("params.invalid", "There is no slot #{key}."))
        end

        # The Zone occurrences `targets` name, each once, each with its slots as last read: a changed slot refuses
        # target.changed before anything is staged.
        def targets!(zones, targets)
          keys = targets.map { |target| target.fetch("reference").values_at("zone_id", "zone_path") }
          raise CodedError.new("params.invalid", "A Zone may appear only once.") if keys.uniq.length != keys.length

          targets.map do |target|
            zone = find!(zones, target.fetch("reference"))
            expected = target.fetch("expected_values", {})
            changed = expected.keys.reject { |key| zone.values[key] == expected[key] }
            unless changed.empty?
              raise CodedError.new("target.changed", "What serves Zone #{label(zone)} has changed since it was read " \
                                                     "(#{changed.join(', ')}).", "zone_id" => zone.id,
                                                                                 "fields" => changed)
            end
            zone
          end
        end

        def find!(zones, reference)
          id = reference.fetch("zone_id")
          same = zones.select { |zone| zone.id == id }
          raise CodedError.new("target.not_found", "Zone #{id} does not exist.") if same.empty?

          zone = same.find { |candidate| candidate.reference.fetch("zone_path") == reference.fetch("zone_path") }
          raise CodedError.new("target.changed", "The Zone occurrence path has changed.", "zone_id" => id) unless zone

          zone
        end

        def filled!(request, zone, slot, current, item_id)
          return if current.nil? || current == item_id

          name = item_name(request, slot.kind, current)
          raise CodedError.new(Codes::SLOT_FILLED, "Zone #{label(zone)} is served by #{slot.label} #{name}; " \
                                                   "assign with replace to use another.",
                               "zone_id" => zone.id, "slot" => slot.key, "current_id" => current)
        end

        def in_use!(request, kind, id, users)
          item = request.engine.kind(kind).label
          names = users.map { |zone| label(zone) }.uniq.sort
          raise CodedError.new("reference.in_use", "#{item} #{item_name(request, kind, id)} serves " \
                                                   "#{names.join(', ')}; name a replacement, or null to clear it.",
                               "target_kind" => kind, "id" => id, "zone_ids" => users.map(&:id).uniq.sort)
        end

        def stale!(request, kind, id, expected_values)
          record = request.engine.find(kind, id)
          changed = expected_values.keys.reject { |key| record[key] == expected_values[key] }
          return if changed.empty?

          raise CodedError.new("target.changed", "#{request.engine.kind(kind).label} #{id} has changed since it " \
                                                 "was read (#{changed.join(', ')}).", "fields" => changed)
        end

        def check_replacement!(request, kind, id, replacement)
          return if replacement.nil?

          if replacement == id
            raise CodedError.new("params.invalid", "Choose a different replacement #{request.engine.kind(kind).label}.")
          end

          request.engine.find(kind, replacement)
        end

        def item_name(request, kind, id)
          request.engine.find(kind, id).fetch("name")
        rescue CodedError
          id
        end

        def label(zone)
          zone.name || zone.id
        end
      end
    end
  end
end
