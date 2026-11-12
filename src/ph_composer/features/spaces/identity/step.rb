# frozen_string_literal: true

module PhComposer
  module Spaces
    # Applies an IdentityPlan over the records at or below `scope_path`. For Make independent the scope is
    # the named target's path: a Space or Volume copied natively shares its definition with the original
    # (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts"), so the step first gives the target
    # storage of its own: Make Unique, then every Group inside it still sharing, as Zones does. For a Zone
    # copy the scope is the Zone's path, whose storage the Zone's own step isolated first, and there is no
    # target. Either way every entity inside was replaced, so each row is found again by kind, id and
    # ordinal and must still hold its pre-image. Restorable: `restore` writes the captured records back for
    # a follow-up that cannot abort; isolated storage stays isolated, which is consistent (the copy keeps
    # its finding and its repair).
    class IdentityStep
      # One entity's state before apply wrote it: its store, the record there (nil when none) and its name.
      Captured = Struct.new(:store, :entity, :record, :name, keyword_init: true)

      attr_reader :affected, :number, :planned, :zone_id

      # `zone_id` is the Zone a target is hosted in, nil for one in no Zone: where its number is reserved.
      def initialize(plan:, target: nil, scope_path: target.path, zone_id: nil)
        @zone_id = zone_id&.dup&.freeze
        @path = scope_path.dup.freeze
        @kind = target && Resolve.kind_of(target.reference)
        @record = target && DeepCopy.frozen(target.record)
        @counts = plan.counts.dup.freeze
        @rows = plan.rows.map do |row|
          { "kind" => row.kind, "ordinal" => row.ordinal, "before" => DeepCopy.call(row.before),
            "after" => DeepCopy.call(row.after) }
        end.freeze
        @affected = []
        @captured = nil
        renamed = target && plan.rows.find { |row| row.kind == @kind && row.before == target.record }
        @number = @kind == SPACE_KIND && renamed ? renamed.after["number"] : nil
        # What a contributor reports before apply: each rewritten record's kind, new id and change.
        @planned = @rows.map { |row| affected_row(row, nil).reject { |key, _value| key == "reference" } }
      end

      def descriptor
        { "name" => @record ? "make_space_independent" : "follow_zone_copy", "path" => @path, "record" => @record,
          "counts" => @counts.map { |(kind, id), count| [kind, id, count] }.sort, "rows" => DeepCopy.call(@rows) }
      end

      def temporary_ids
        @rows.reject { |row| row.dig("after", "id") == row.dig("before", "id") }
             .flat_map { |row| [row.dig("after", "id"), row.dig("after", "floor_id")] }
      end

      def apply(model, _slots)
        if @record
          target = target_occurrence(model)
          isolate(target.entity) if target.entity.is_a?(Sketchup::Group)
        end
        scan = Occurrences.scan(model, :strict => @record ? true : @path)
        inside = Authoring.inside(scan, @path).sort_by { |_kind, occurrence| occurrence.path }
        groups = inside.group_by { |kind, occurrence| [kind, occurrence.record.fetch("id")] }
        unless groups.transform_values(&:length) == @counts
          raise CodedError.new("target.changed", "The copy's contents changed after it was previewed.")
        end

        resolved = @rows.map do |row|
          _kind, occurrence = groups.fetch([row.fetch("kind"), row.dig("before", "id")]).fetch(row.fetch("ordinal"))
          check!(occurrence, row)
          [row, occurrence]
        end
        @captured = resolved.map do |row, occurrence|
          entity = occurrence.entity
          store = STORES.fetch(row.fetch("kind"))
          Captured.new(:store => store, :entity => entity, :record => store.read(entity),
                       :name => entity.respond_to?(:name) ? entity.name : nil)
        end
        resolved.each { |row, occurrence| write(row, occurrence.entity) }
        @affected = resolved.map { |row, occurrence| affected_row(row, occurrence.path) }
      end

      # Writes back what apply replaced; nothing when apply did not reach its writes. Every captured record
      # is attempted even after one fails, and the step raises once at the end.
      def restore
        return unless @captured

        failures = @captured.count do |captured|
          store = captured.store
          entity = captured.entity
          captured.record ? store.write(entity, captured.record) : store.delete(entity)
          entity.name = captured.name if captured.name && store.equal?(SPACE_STORE) && entity.respond_to?(:name=)
          false
        rescue StandardError => error
          Diagnostics.exception("space_restore", error)
          true
        end
        raise InternalError, "#{failures} Space records could not be restored." if failures.positive?
      end

      private

      def write(row, entity)
        store = STORES.fetch(row.fetch("kind"))
        store.write(entity, row.fetch("after"))
        entity.name = Names.space(row.fetch("after")) if store.equal?(SPACE_STORE) && entity.respond_to?(:name=)
      end

      # Each rewritten record with the path it has after isolation, which the caller can resolve.
      def affected_row(row, path)
        id = row.dig("after", "id")
        key = Resolve::TARGETS.fetch(row.fetch("kind")).id_key
        { "kind" => row.fetch("kind"), "id" => id,
          "change" => id == row.dig("before", "id") ? "updated" : "identity_repaired",
          "reference" => { key => id, "entity_path" => path } }
      end

      # The eligibility the plan checked holds again at apply.
      def target_occurrence(model)
        scan = Occurrences.scan(model)
        kind_target = Resolve::TARGETS.fetch(@kind)
        target = kind_target.occurrences_in(scan).find { |occurrence| occurrence.path == @path }
        unless target && target.record == @record
          raise CodedError.new("target.changed", "That #{kind_target.label} changed after it was previewed.")
        end

        IdentityPlan.refuse!(scan, @kind, target)
        target
      end

      def isolate(group)
        group.make_unique if Occurrences.shared_storage?(group)
        group.entities.to_a.grep(Sketchup::Group).each { |child| isolate(child) }
      end

      def check!(occurrence, row)
        unless occurrence.record == row.fetch("before")
          raise CodedError.new("target.changed", "A record in the copy changed after it was previewed.")
        end
        raise CodedError.new("target.locked", "A Group in the copy is locked.") if occurrence.locked
        return unless occurrence.shared

        raise CodedError.new("target.shared_definition", "The copy still shares storage with another placement.")
      end
    end
  end
end
