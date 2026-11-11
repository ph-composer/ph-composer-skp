# frozen_string_literal: true

module PhComposer
  module Zones
    # The explicit repairs a Zone can need after the user copies or explodes one. None infers membership
    # from geometry: identity repair and Make Zone independent work on one occurrence the caller named
    # by path, and Restore works only on members that carry a stamp. Make Zone independent also runs on
    # a fresh native copy, through the copy watcher (copy_watch.rb); the other two never run from an
    # observer.
    module Repair
      module_function

      # The occurrence at exactly this path, whatever its id's ambiguity. Ordinary resolution refuses
      # a duplicated Zone id, which is right everywhere except here: repairing the duplicate is the
      # whole point, so the path is the identity and the id is the thing being changed.
      def occurrence_at(model, path)
        wanted = Occurrences.integer_path(path)
        found = Occurrences.zones(model).select { |zone| zone.path == wanted }
        raise CodedError.new("target.not_found", "No Zone occurrence is at that path.") if found.empty?
        # Two Zones cannot share a path; if they do the Model is not something to write to.
        raise CodedError.new("target.ambiguous", "That path resolves to more than one Zone.") if found.length > 1

        found.first
      end

      # What identity repair would change, as detached values. Raises rather than returning a partial
      # plan: a repair that cannot be done completely must write nothing. `isolating` is Make Zone
      # independent's feasibility read: storage is still shared because the step isolates it before it
      # writes, so only the shared-storage refusal is waived.
      def identity_plan(model, zone, revision, catalog, engine, isolating: false)
        check_repairable!(model, zone, :isolating => isolating)
        plan_with(zone, identity_mapping(model, zone, revision), catalog, engine)
      end

      # Every new id, fixed before anything is written: the Zone's from its occurrence path, each Face's
      # from the id it was copied with. Neither reads a Face entity, so Make Unique, which replaces the
      # copy's Faces with new entities, leaves the mapping valid between preview and apply.
      def identity_mapping(model, zone, revision)
        old_id = zone.record.fetch("id")
        new_id = Records::Identity.derived("zon", "model" => model.guid, "revision" => revision,
                                                  "zone_path" => zone.path, "repaired" => old_id)
        if Occurrences.zones(model).any? { |other| other.record.fetch("id") == new_id }
          raise CodedError.new("target.ambiguous", "The repaired Zone identity is already present.")
        end

        mapping = { old_id => new_id }
        member_entries(zone).each do |entry|
          face_id = entry.fetch(:before)&.fetch("id", nil)
          next unless face_id

          if mapping.key?(face_id)
            raise CodedError.new("target.ambiguous", "A copied Face id occurs more than once in this Zone.")
          end

          mapping[face_id] = Records::Identity.derived("fac", "model" => model.guid, "revision" => revision,
                                                              "zone_id" => new_id, "copied_from" => face_id)
        end
        mapping
      end

      # The records identity repair writes for this mapping, read from the occurrence as it is now: the
      # remapped payloads and the typed reference plan are built against the live Face entities, so
      # they are right after storage isolation too. A Face record the mapping does not know was added
      # after the preview, and the repair refuses rather than guess.
      def plan_with(zone, mapping, catalog, engine)
        old_id = zone.record.fetch("id")
        faces = member_entries(zone)
        faces.each do |entry|
          face_id = entry.fetch(:before)&.fetch("id", nil)
          next if face_id.nil? || mapping.key?(face_id)

          raise CodedError.new("target.changed", "A Face of the Zone changed after the repair was previewed.")
        end
        reference_plan = identity_reference_plan(zone, faces, mapping)
        record = DeepCopy.call(zone.record).merge("id" => mapping.fetch(old_id))
        record["extension_data"] = Records::Extension.copy_data(zone.record.fetch("extension_data", {}), catalog,
                                                                "Zone", old_id, mapping,
                                                                :engine => engine,
                                                                :reference_plan => reference_plan)
        Schema.validate!(record)
        plans = face_plans(faces, zone, mapping.fetch(old_id), mapping, catalog, engine, reference_plan)
        { :old_id => old_id, :record => record, :faces => plans, :mapping => mapping,
          :reference_plan => reference_plan }
      end

      def identity_reference_plan(zone, faces, mapping)
        entries = [Records::ReferenceEntry.new(
          :kind => REFERENCE_KIND, :key => zone.path,
          :record => zone.record.merge("id" => mapping.fetch(zone.record.fetch("id")))
        )]
        faces.each do |entry|
          before = entry.fetch(:before)
          next unless before

          entries << Records::ReferenceEntry.new(
            :kind => Faces::REFERENCE_KIND, :key => zone.path + entry.fetch(:occurrence).path,
            :record => before.merge("id" => mapping.fetch(before.fetch("id")))
          )
        end
        Records::ReferencePlan.new(:entries => entries)
      end

      def check_repairable!(model, zone, isolating: false)
        if zone.shared_definition && !isolating
          raise CodedError.new("target.shared_definition",
                               "That Zone is inside shared component storage, so it cannot be given an " \
                               "identity of its own.")
        end
        raise CodedError.new("target.wrong_hierarchy", "A Zone cannot be nested inside another Zone.") if zone.nested

        refusal = lock_refusal(zone)
        raise refusal if refusal

        copies = Occurrences.zones(model).count { |other| other.record.fetch("id") == zone.record.fetch("id") }
        return if copies > 1

        raise CodedError.new("zone.identity_unique",
                             "That Zone's identity is already unique; there is nothing to repair.")
      end

      # Why Make Zone independent cannot act on this occurrence, as an unraised CodedError, or nil when
      # it can. It acts on a Zone whose id another occurrence also holds, whether or not its own Group
      # still shares its Faces; it never isolates storage above the Zone, because a component is shared
      # by design and a shared parent Group would make Groups unique inside the original's contents.
      # A shared Group's placement gets its own definition once opened for editing (context/SKETCHUP_HOST_BEHAVIOR.md);
      # SketchUp 2026 offers no Make Unique on a Group's menu, and Make Unique leaves a component placement refused.
      OPEN_GROUP = "Open that Group with Edit Group, or double-click it, then close it"

      def independence_refusal(model, zone, id_count: nil)
        ids = id_count || Occurrences.zones(model).count { |other| other.record.fetch("id") == zone.record.fetch("id") }
        ancestors = path_entities(model, zone.path)[0...-1]
        if zone.nested
          CodedError.new("target.wrong_hierarchy",
                         "This Zone is inside another Zone. Move it out of that Zone first.")
        elsif ancestors.any? { |entity| entity.is_a?(Sketchup::ComponentInstance) }
          CodedError.new("target.shared_definition",
                         "This Zone is inside a component, whose placements share it by design. Explode that " \
                         "component first.")
        elsif ancestors.any? { |entity| Occurrences.shared_storage?(entity) }
          CodedError.new("target.shared_definition",
                         "This Zone is inside a copied Group that still shares its contents. #{OPEN_GROUP}, " \
                         "then try again.")
        elsif (locked = lock_refusal(zone))
          locked
        elsif member_containers(zone).any? { |entity| entity.is_a?(Sketchup::ComponentInstance) }
          CodedError.new("target.shared_definition",
                         "Some of this Zone's Faces are inside a component, which its placements share by " \
                         "design. Explode that component first.")
        elsif member_containers(zone).any? { |entity| entity.respond_to?(:locked?) && entity.locked? }
          CodedError.new("target.locked", "A Group holding some of this Zone's Faces is locked. Unlock it first.")
        elsif ids < 2
          CodedError.new("zone.identity_unique", "This Zone already has an identity of its own.")
        end
      end

      # The refusal a write to this occurrence meets from its own lock or a locked Group above it, as every Zone
      # write refuses, as an unraised CodedError, or nil when neither is locked.
      def lock_refusal(zone)
        return nil unless zone.locked_parent || (zone.entity.respond_to?(:locked?) && zone.entity.locked?)

        CodedError.new("target.locked", "This Zone or a Group containing it is locked. Unlock it first.")
      end

      # Every Group or ComponentInstance inside the Zone that holds a Face the repair writes. Nested
      # Groups are isolated with the Zone (MakeIndependentStep); a component or a lock is a prerequisite.
      def member_containers(zone)
        member_entries(zone).flat_map do |entry|
          entities = zone.entity.entities
          entry.fetch(:occurrence).path[0...-1].map do |persistent_id|
            container = Occurrences.unique_entity(entities, persistent_id)
            entities = container.is_a?(Sketchup::ComponentInstance) ? container.definition.entities : container.entities
            container
          end
        end.uniq
      end

      # The entities on a root-to-Zone path, through Groups and ComponentInstances alike.
      def path_entities(model, path)
        entities = model.entities
        path.map do |persistent_id|
          entity = Occurrences.unique_entity(entities, persistent_id)
          entities = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.entities : entity.entities
          entity
        end
      end

      # Every member record the repair rewrites. A copied `fac_` id is ambiguous data, so each face
      # takes a fresh one; a copied adjacency envelope is not a relationship, so it is dropped with
      # its boundary condition and the Face needs classifying again.
      def member_entries(zone)
        Occurrences.faces(zone).filter_map do |occurrence|
          record = Faces::FACE_STORE.read(occurrence.entity)
          existing_stamp = STAMP_STORE.read(occurrence.entity)
          next if record.nil? && existing_stamp.nil?

          { :occurrence => occurrence, :before => record }
        end
      end

      def face_plans(entries, zone, new_zone_id, mapping, catalog, engine, reference_plan)
        stamp = Schema.stamp(zone.record.merge("id" => new_zone_id))
        entries.map do |entry|
          occurrence = entry.fetch(:occurrence)
          before = entry.fetch(:before)
          { :reference => occurrence.reference(before&.fetch("id", nil)), :before => before,
            :after => repaired_face(before, mapping, catalog, engine, reference_plan), :stamp => stamp }
        end
      end

      def repaired_face(record, mapping, catalog, engine, reference_plan)
        return nil unless record

        after = DeepCopy.call(record)
        after["id"] = mapping.fetch(record.fetch("id"))
        after["extension_data"] = Records::Extension.copy_data(record.fetch("extension_data", {}), catalog,
                                                               "Face", record.fetch("id"), mapping,
                                                               :engine => engine,
                                                               :reference_plan => reference_plan)
        Faces::Schema.leave_pair!(after)
        after.delete("boundary_condition") if record["boundary_condition"] == "Surface"
        Faces::Schema.validate!(after)
      end

      # Faces carrying a Zone stamp whose Zone is gone, grouped by the id
      # they remember and the one parent context they sit in. This is the only membership evidence
      # Restore accepts.
      def orphans(model)
        live = Occurrences.zones(model).map { |zone| zone.record.fetch("id") }
        found = []
        walk_orphans(model.entities, [], live, found)
        found.group_by { |entry| entry.fetch(:zone_id) }.map { |zone_id, entries| orphan_group(zone_id, entries) }
      end

      def orphan_group(zone_id, entries)
        contexts = entries.group_by { |entry| entry.fetch(:parent_path) }
        stamps = entries.map { |entry|
          entry.fetch(:stamp).slice("schema_version", "building_segment", "level",
                                    "building_segment_id", "level_id", "choice_evidence")
        }.uniq
        first = entries.first.fetch(:stamp)
        offer = {
          "zone_id" => zone_id,
          "building_segment" => first["building_segment"] || first.dig("choice_evidence", "building_segment", "name"),
          "level" => first["level"] || first.dig("choice_evidence", "level", "name"),
          "parent_path" => entries.first.fetch(:parent_path),
          # Always every remembered member, so the count and the ids cannot disagree. A refused
          # offer never reaches a write, and a reader comparing the two should not be misled.
          "entity_ids" => entries.map { |entry| entry.fetch(:persistent_id) }.sort,
          "member_count" => entries.length,
          "refusal" => orphan_refusal(contexts, stamps, entries),
          # Restore recovers the id, Building-Segment and Level and nothing else. Everything the
          # Group itself carried went with it, and saying so is part of the offer.
          "unrecoverable" => %w[name user_data extension_data ground_depth_mm]
        }
        offer["choice_record"] = first if first.fetch("schema_version") == 2
        offer
      end

      def orphan_refusal(contexts, stamps, entries)
        return "mixed_context" if contexts.length > 1
        return "stamps_conflict" if stamps.length > 1
        return "shared_edge" if shared_edge?(entries)

        nil
      end

      # Regrouping takes a Face's bounding Edges with it, so an Edge also used by a Face nobody
      # stamped would drag unstamped geometry into the restored Zone. Restore refuses rather than
      # move geometry the user did not ask it to move.
      def shared_edge?(entries)
        members = entries.map { |entry| entry.fetch(:entity) }
        members.any? do |face|
          face.edges.any? { |edge| edge.faces.any? { |other| !members.include?(other) } }
        end
      end

      def restore_plan(model, parent_path, zone_id)
        wanted = Occurrences.integer_path(parent_path)
        if Occurrences.zones(model).any? { |zone| zone.record.fetch("id") == zone_id }
          raise CodedError.new("zone.identity_in_use", "Zone #{zone_id} is already in the Model.")
        end

        offer = orphans(model).find { |entry| entry.fetch("zone_id") == zone_id }
        raise CodedError.new("target.not_found", "No stamped members remember Zone #{zone_id}.") unless offer
        unless offer.fetch("parent_path") == wanted
          raise CodedError.new("target.changed", "Those stamped members are not in that parent context.")
        end

        if offer.fetch("refusal")
          raise CodedError.new("zone.restore_unsafe",
                               "Zone #{zone_id} cannot be restored: #{offer.fetch('refusal')}.")
        end

        record = {
          "id" => zone_id, "schema_version" => 1, "name" => Zones.default_name(model),
          "building_segment" => offer["building_segment"] || Occurrences::DEFAULT_SEGMENT,
          "level" => offer["level"], "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {}
        }
        if offer["choice_record"]
          record = record.reject { |key, _| %w[building_segment level].include?(key) }
                         .merge(offer.fetch("choice_record").reject { |key, _| key == "zone_id" })
        end
        Schema.validate!(record)
        [record, offer]
      end

      # A stamped Face is a member; a Group is walked for the Faces inside it, but a live Zone's Faces are
      # that Zone's, and offering them would build a Zone inside it.
      def walk_orphans(entities, path, live, found)
        entities.each do |entity|
          if entity.is_a?(Sketchup::Group)
            next unless entity.get_attribute(ZONE_STORE.dictionary, ZONE_STORE.key).nil?

            walk_orphans(entity.entities, path + [entity.persistent_id], live, found)
            next
          end
          next unless entity.is_a?(Sketchup::Face)

          stamp = readable_stamp(entity)
          # A stamp this feature did not write, or that does not read, cannot name a Zone to restore; it
          # is left alone rather than failing the whole Zones read.
          next unless Schema.stamp?(stamp) && !live.include?(stamp["zone_id"])

          found << { :zone_id => stamp["zone_id"], :stamp => stamp, :parent_path => path,
                     :persistent_id => entity.persistent_id, :entity => entity }
        end
      end

      # A stamp is stored as JSON text; any other stored value reads as no stamp.
      def readable_stamp(entity)
        return nil unless entity.get_attribute(STAMP_DICTIONARY, STAMP_STORE.key).is_a?(String)

        STAMP_STORE.read(entity)
      rescue CodedError
        nil
      end

      private_class_method :orphan_group, :readable_stamp, :orphan_refusal,
                           :shared_edge?, :walk_orphans, :repaired_face, :face_plans, :member_entries,
                           :member_containers
    end
  end
end
