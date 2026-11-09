# frozen_string_literal: true

module PhComposer
  module Zones
    class MakeZoneStep
      attr_reader :affected

      # `regroup` always groups the members anew, as Restore does: they may include a stamped Group, which
      # is a member and never the Zone's own Group.
      def initialize(parent_path:, entity_ids:, record:, regroup: false)
        @parent_path = parent_path.freeze
        @entity_ids = entity_ids.freeze
        @record = DeepCopy.call(record).freeze
        @regroup = regroup
        @affected = [{ "kind" => "zone", "id" => record.fetch("id"), "change" => "grouped" }]
      end

      def descriptor
        { "name" => "make_zone", "parent_path" => @parent_path, "entity_ids" => @entity_ids, "record" => @record,
          "regroup" => @regroup }
      end

      def temporary_ids
        [@record.fetch("id")]
      end

      def apply(model, slots)
        verify_edit_path!(model)
        entities = Operations::EntityScope.new(@parent_path).resolve(model)
        selected = @entity_ids.map { |id| Occurrences.unique_entity(entities, id) }
        group = (existing_group(selected) unless @regroup) || entities.add_group(selected)
        if group.respond_to?(:locked?) && group.locked?
          raise CodedError.new("target.locked", "The selected Group is locked.")
        end
        raise CodedError.new("target.changed", "The selected Group is already a Zone.") if ZONE_STORE.read(group)

        ZONE_STORE.write(group, @record)
        group.name = @record.fetch("name") if group.respond_to?(:name=)
        Names.track(model, group)
        reference = { "zone_id" => @record.fetch("id"), "zone_path" => @parent_path + [group.persistent_id] }
        slots[@record.fetch("id")] = reference
        @affected = [{ "kind" => "zone", "id" => @record.fetch("id"), "change" => "grouped",
                       "reference" => reference }]
      end

      private

      def existing_group(selected)
        return selected.first if selected.length == 1 && selected.first.is_a?(Sketchup::Group)
        return nil if selected.all? { |entity| entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge) }

        raise CodedError.new("target.wrong_kind", "Make Zone accepts one Group or loose Faces and Edges.")
      end

      def verify_edit_path!(model)
        return if Occurrences.active_path(model) == @parent_path

        raise CodedError.new("target.edit_path_changed", "The active edit path changed before Make Zone.")
      end
    end

    class UpdateZoneStep
      attr_reader :affected

      def initialize(reference:, before:, after:)
        @reference = DeepCopy.call(reference).freeze
        @before = DeepCopy.call(before).freeze
        @after = DeepCopy.call(after).freeze
        @affected = [{ "kind" => "zone", "id" => after.fetch("id"), "change" => "updated",
                       "reference" => @reference }]
      end

      def descriptor
        { "name" => "update_zone", "reference" => @reference, "before" => @before, "after" => @after }
      end

      def apply(model, _slots)
        occurrence = Occurrences.resolve_zone(model, @reference, :mutable => true)
        current = occurrence.record
        raise CodedError.new("target.changed", "The Zone changed after it was previewed.") unless current == @before

        ZONE_STORE.write(occurrence.entity, @after)
        occurrence.entity.name = @after.fetch("name") if occurrence.entity.respond_to?(:name=)
        Names.track(model, occurrence.entity)
        stamp = Schema.stamp(@after)
        stamped = Occurrences.faces(occurrence).map(&:entity) + Occurrences.containers(occurrence).map(&:first)
        stamped.each do |entity|
          existing = STAMP_STORE.read(entity)
          STAMP_STORE.write(entity, stamp) if existing && existing["zone_id"] == @after.fetch("id")
        end
      end
    end

    # Gives a copied plain Group storage of its own: Make Unique, then each Group inside still sharing its
    # contents, except Zones, whose own repair isolates them. Restorable for a host follow-up: isolated
    # storage stays isolated, which is consistent.
    class IsolateCopiedGroupStep
      attr_reader :affected

      def initialize(path:)
        @path = path.dup.freeze
        @affected = []
      end

      def descriptor
        { "name" => "isolate_copied_group", "path" => @path }
      end

      def apply(model, _slots)
        group = Repair.path_entities(model, @path).last
        group.make_unique if Occurrences.shared_storage?(group)
        MakeIndependentStep.isolate_groups(group.entities)
      end

      def restore; end
    end

    # Stamps a Group the calling feature's own earlier step created in this proposal, making it a nested
    # container of the Zone (context/CONTRACTS.md, "Zones geometry rules"). That step leaves the Group's
    # root-to-Group path in `slots[slot]` as `{ "entity_path" => [...] }`; Zones writes the stamp, so the
    # stamp stays Zones' to write wherever it is stored.
    class StampContainerStep
      attr_reader :affected

      def initialize(zone:, slot:)
        @zone = DeepCopy.call(zone).freeze
        @slot = slot.dup.freeze
        @affected = []
        @written = nil
      end

      def descriptor
        { "name" => "stamp_container", "zone" => @zone, "slot" => @slot }
      end

      def apply(model, slots)
        zone = Occurrences.resolve_zone(model, @zone, :mutable => true)
        raise CodedError.new("target.locked", "The Zone is locked.") if zone.entity.locked?

        path = Array(slots.fetch(@slot) { raise InternalError, "No step filled the container slot #{@slot}." }
                          .fetch("entity_path"))
        group = container_at(zone, path)
        @written = [group, STAMP_STORE.read(group)]
        STAMP_STORE.write(group, Schema.stamp(zone.record))
      end

      def restore(_model)
        return unless @written

        group, before = @written
        before ? STAMP_STORE.write(group, before) : STAMP_STORE.delete(group)
      end

      private

      # The Group must lie inside this Zone occurrence through plain Groups only, as `containers` finds it.
      def container_at(zone, path)
        inside = path[zone.path.length..-1]
        unless path[0, zone.path.length] == zone.path && inside && !inside.empty?
          raise CodedError.new("target.wrong_hierarchy", "The container is not inside that Zone.")
        end

        entities = zone.entity.entities
        group = nil
        inside.each_with_index do |persistent_id, index|
          group = Occurrences.unique_entity(entities, persistent_id)
          unless group.is_a?(Sketchup::Group) && !ZONE_STORE.read(group)
            raise CodedError.new("target.wrong_kind", "A container is a Group inside the Zone, through Groups only.")
          end
          raise CodedError.new("target.locked", "A Group on the container's path is locked.") if group.locked?
          if Occurrences.shared_storage?(group)
            raise CodedError.new("target.shared_definition", "The container's path runs through shared storage.")
          end
          # A container inside another is not one of the Zone's containers, so its stamp would go stale.
          if index < inside.length - 1 && !group.get_attribute(STAMP_DICTIONARY, STAMP_STORE.key).nil?
            raise CodedError.new("target.wrong_hierarchy", "The container would be inside another container.")
          end

          entities = group.entities
        end
        group
      end
    end

    # Gives one copied Zone occurrence an identity of its own. Every write lands inside that
    # occurrence's path, so the Zone it was copied from and that Zone's pairs are left exactly as
    # they were. The copy's own pairs go: a copied adjacency envelope was never a relationship. Its
    # nested containers' stamps name the new identity, as its Faces' do.
    class RepairIdentityStep
      attr_reader :affected

      def initialize(reference:, plan:)
        @reference = DeepCopy.call(reference).freeze
        @old_id = plan.fetch(:old_id)
        @record = DeepCopy.call(plan.fetch(:record)).freeze
        @faces = plan.fetch(:faces).map { |face| DeepCopy.call(face).freeze }.freeze
        @affected = [{ "kind" => "zone", "id" => @record.fetch("id"), "change" => "updated",
                       "reference" => @reference.merge("zone_id" => @record.fetch("id")) }]
        @affected.concat(@faces.filter_map { |face| face_affected(face) })
      end

      def descriptor
        { "name" => "repair_zone_identity", "reference" => @reference, "old_id" => @old_id,
          "record" => @record, "faces" => @faces }
      end

      def temporary_ids
        []
      end

      def apply(model, _slots)
        zone = Repair.occurrence_at(model, @reference.fetch("zone_path"))
        unless zone.record.fetch("id") == @old_id
          raise CodedError.new("target.changed", "The Zone identity changed after the repair was previewed.")
        end

        resolved = @faces.map { |face| [resolve_member(zone, face), face] }
        ZONE_STORE.write(zone.entity, @record)
        resolved.each do |occurrence, face|
          after = face.fetch(:after)
          Faces::FACE_STORE.write(occurrence.entity, after) if after
          STAMP_STORE.write(occurrence.entity, face.fetch(:stamp))
        end
        Occurrences.containers(zone).each { |group, _path| STAMP_STORE.write(group, Schema.stamp(@record)) }
      end

      private

      def face_affected(face)
        after = face.fetch(:after)
        return nil unless after

        { "kind" => "face", "id" => after.fetch("id"), "change" => "updated",
          "reference" => face.fetch(:reference).merge("zone_id" => @record.fetch("id"),
                                                      "entity_id" => after.fetch("id")) }
      end

      def resolve_member(zone, face)
        occurrence = Occurrences.face_at(zone, face.fetch(:reference).fetch("entity_path"), :mutable => true)
        current = Faces::FACE_STORE.read(occurrence.entity)
        unless current == face.fetch(:before)
          raise CodedError.new("target.changed", "A Face changed after the repair was previewed.")
        end

        occurrence
      end
    end

    # Make Zone independent: the copy gets storage of its own, then the identity repair above, as one
    # step. Make Unique creates the copy's Face entities, so their final references exist only during
    # apply. The preview therefore binds the logical change: the id mapping and every record's content,
    # keyed by the id it was copied with. Apply isolates storage, rebuilds the plan from the isolated
    # occurrence with that same mapping, refuses if any record differs from the preview, and only then
    # writes; `affected` carries the final references once apply has run.
    #
    # A host follow-up that must not abort its source gesture calls `restore` after a failure: it writes
    # back the records apply captured after isolating storage, so the copy keeps storage of its own and
    # the identity it was copied with, which this command can repair later.
    class MakeIndependentStep
      # One store's state on one entity before apply wrote it; `record` is nil when it held none.
      Captured = Struct.new(:store, :entity, :record, keyword_init: true)

      attr_reader :affected

      def initialize(reference:, plan:, catalog:)
        @reference = DeepCopy.call(reference).freeze
        @old_id = plan.fetch(:old_id)
        @mapping = DeepCopy.call(plan.fetch(:mapping)).freeze
        @record = DeepCopy.call(plan.fetch(:record)).freeze
        @contents = MakeIndependentStep.contents(plan).freeze
        @catalog = catalog
        @captured = nil
        @stamps = []
        new_id = @record.fetch("id")
        @affected = [{ "kind" => "zone", "id" => new_id, "change" => "updated",
                       "reference" => @reference.merge("zone_id" => new_id) }]
      end

      # Make Unique on the Zone's Group leaves the Groups inside it shared with the original's (measured on
      # SketchUp 26.1), so each nested Group still sharing its contents is made unique in turn, which leaves the
      # original's untouched. Components are left alone: eligibility refuses member Faces inside one.
      def self.isolate_groups(entities)
        entities.to_a.grep(Sketchup::Group).each do |group|
          next if ZONE_STORE.read(group)

          group.make_unique if Occurrences.shared_storage?(group)
          isolate_groups(group.entities)
        end
      end

      # Whether the occurrence or any Group inside it still shares its contents.
      def self.shared_storage?(entity)
        Occurrences.shared_storage?(entity) || entity.entities.to_a.grep(Sketchup::Group).any? do |group|
          !ZONE_STORE.read(group) && shared_storage?(group)
        end
      end

      # Every Face record change, without the Face paths that Make Unique replaces.
      def self.contents(plan)
        plan.fetch(:faces).map { |face| [face.fetch(:before), face.fetch(:after), face.fetch(:stamp)] }
            .sort_by { |entry| CanonicalJson.generate(entry) }
      end

      def descriptor
        { "name" => "make_zone_independent", "reference" => @reference, "mapping" => @mapping,
          "record" => @record, "faces" => @contents }
      end

      def temporary_ids
        []
      end

      def apply(model, _slots)
        path = @reference.fetch("zone_path")
        zone = Repair.occurrence_at(model, path)
        unless zone.record.fetch("id") == @old_id
          raise CodedError.new("target.changed", "The Zone identity changed after it was previewed.")
        end

        refusal = Repair.independence_refusal(model, zone)
        raise refusal if refusal

        zone.entity.make_unique if Occurrences.shared_storage?(zone.entity)
        MakeIndependentStep.isolate_groups(zone.entity.entities)
        zone = Repair.occurrence_at(model, path)
        live = Repair.plan_with(zone, @mapping, @catalog, Records::Engine.new(model, @catalog))
        unless live.fetch(:record) == @record && MakeIndependentStep.contents(live) == @contents
          raise CodedError.new("target.changed", "The Zone changed after Make Zone independent was previewed.")
        end

        write(zone, live)
      end

      # Writes back what apply captured, returning how many entities it touched; 0 before apply.
      def restore
        return 0 unless @captured

        @stamps.each do |group, raw|
          raw.nil? ? STAMP_STORE.delete(group) : group.set_attribute(STAMP_DICTIONARY, STAMP_STORE.key, raw)
        end
        @captured.each do |captured|
          store = captured.store
          captured.record ? store.write(captured.entity, captured.record) : store.delete(captured.entity)
        end.length + @stamps.length
      end

      private

      def write(zone, live)
        resolved = live.fetch(:faces).map do |face|
          [Occurrences.face_at(zone, face.fetch(:reference).fetch("entity_path"), :mutable => true), face]
        end
        @captured = [capture(ZONE_STORE, zone.entity)]
        resolved.each do |occurrence, _face|
          @captured << capture(Faces::FACE_STORE, occurrence.entity) << capture(STAMP_STORE, occurrence.entity)
        end
        containers = Occurrences.containers(zone).map(&:first)
        # A container's stamp attribute is captured as stored: its presence makes the Group a container
        # whatever its value reads as, and restore must not turn its Faces into the Zone's.
        @stamps = containers.map { |group| [group, group.get_attribute(STAMP_DICTIONARY, STAMP_STORE.key)] }
        ZONE_STORE.write(zone.entity, @record)
        resolved.each do |occurrence, face|
          after = face.fetch(:after)
          Faces::FACE_STORE.write(occurrence.entity, after) if after
          STAMP_STORE.write(occurrence.entity, face.fetch(:stamp))
        end
        containers.each { |group| STAMP_STORE.write(group, Schema.stamp(@record)) }
        @affected = @affected.take(1) + resolved.filter_map { |_occurrence, face| face_affected(face) }
      end

      def capture(store, entity)
        Captured.new(:store => store, :entity => entity, :record => store.read(entity))
      end

      def face_affected(face)
        after = face.fetch(:after)
        return nil unless after

        { "kind" => "face", "id" => after.fetch("id"), "change" => "updated",
          "reference" => face.fetch(:reference).merge("zone_id" => @record.fetch("id"),
                                                      "entity_id" => after.fetch("id")) }
      end
    end
  end
end
