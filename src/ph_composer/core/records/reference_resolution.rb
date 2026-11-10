# frozen_string_literal: true

module PhComposer
  module Records
    class Engine
      # Finds exactly one typed target in the proposed final state. Reads are detached and never
      # repair. A plan replaces exact occurrences so copied UUIDs cannot hide live ambiguity.
      def resolve_reference(kind_id, id, reference_plan: nil, change_set: nil)
        entries = reference_entries(kind_id, :change_set => change_set)
        if reference_plan
          validate_reference_plan!(reference_plan)
          other_kinds = reference_plan.removals.map(&:kind).uniq - [kind_id]
          entries += other_kinds.flat_map { |kind| reference_entries(kind, :change_set => change_set) }
          entries = reference_plan.project(entries).select { |entry| entry.kind == kind_id }
        end
        matches = entries.select { |entry| reference_identity(entry) == id }
        detail = { "target_kind" => kind_id, "id" => id }
        if matches.empty?
          raise CodedError.new("reference.invalid", "#{kind_id} #{id} does not exist.", detail)
        end
        if matches.length > 1
          raise CodedError.new("target.ambiguous", "#{kind_id} #{id} occurs more than once.", detail)
        end

        entry = matches.first
        problems = reference_problems(entry)
        unless problems.empty?
          raise CodedError.new("record.unreadable", "#{kind_id} #{id} cannot be used: #{problems.first}.")
        end

        ReferenceEntry.new(:kind => DeepCopy.call(entry.kind), :key => DeepCopy.call(entry.key),
                           :record => DeepCopy.call(entry.record))
      end

      # Every declared incoming reference: core references each kind's descriptor declares, catalog
      # and entity-owned alike, and readable envelopes from unavailable extensions.
      # When identity disappears an opaque/invalid envelope cannot prove that its payload is safe.
      def incoming_references(kind_id, id, change_set: nil, removing: false, reference_plan: nil)
        entries = all_reference_entries(:change_set => change_set)
        if reference_plan
          validate_reference_plan!(reference_plan)
          entries = reference_plan.project(entries)
        end
        entries.filter_map do |entry|
          record = entry.record
          targets = @catalog.descriptor(entry.kind).referenced_targets(record)
          record.fetch("extension_data", {}).each do |namespace, envelope|
            readable = Extension.readable?(envelope)
            status = Extension.status(envelope, @catalog.extension(namespace))
            if removing && (!readable || status == "invalid")
              raise CodedError.new("copy.rule_missing", "#{entry.kind} #{record['id']} carries #{namespace} " \
                                                        "data whose incoming references cannot be established.",
                                   "namespace" => namespace)
            end
            next unless readable

            targets.concat(Extension.referenced_ids(envelope.fetch("payload"), envelope.fetch("references", [])))
          end
          next unless targets.include?([kind_id, id])

          entry
        end
      end

      def check_identity_removal!(kind_id, id, change_set: nil, reference_plan: nil)
        incoming = incoming_references(kind_id, id, :change_set => change_set, :removing => true,
                                                    :reference_plan => reference_plan)
        return if incoming.empty?

        source = incoming.first
        message = "#{source.kind} #{source.record.fetch('id')} still refers to #{kind_id} #{id}."
        raise CodedError.new("reference.in_use", message, "target_kind" => kind_id, "id" => id)
      end

      # How many of the records `check_subtree_removal!` refuses for its detail names; `total` counts them all.
      FOREIGN_RECORD_DETAIL = 20

      # Refuses `target.foreign_records` when a record of a kind outside `owned_kinds` sits on the entity at
      # the root-to-entity persistent-id `path` or anywhere below it: erasing or exploding that subtree would
      # take another owner's data with it. It reads every registered entity-owned target whose occurrence key
      # is such a path (context/EXTENSIBILITY.md, "Entity-owned reference targets"); a target keyed otherwise
      # holds nothing in a subtree. A target whose records cannot be read refuses as reading it does.
      def check_subtree_removal!(path, owned_kinds:)
        foreign = @catalog.reference_targets.reject { |target| owned_kinds.include?(target.id) }.flat_map do |target|
          target.entries(@model).select { |entry| within_path?(entry.key, path) }
        end
        return if foreign.empty?

        labels = foreign.map { |entry| @catalog.reference_target(entry.kind).label }.uniq
        raise CodedError.new("target.foreign_records",
                             "It holds #{labels.join(', ')} data another feature owns, which would go with it. " \
                             "Remove that data with its own feature first. Nothing was written.",
                             "total" => foreign.length,
                             "records" => foreign.first(FOREIGN_RECORD_DETAIL).map do |entry|
                               { "kind" => entry.kind, "path" => entry.key }
                             end)
      end

      private

      def within_path?(key, path)
        key.is_a?(Array) && key.length >= path.length && key[0, path.length] == path
      end

      def reference_identity(entry)
        id = entry.record["id"]
        return id if id.is_a?(String) && !id.empty?

        raise CodedError.new("record.unreadable", "#{entry.kind} at #{entry.key.inspect} has no valid record id.",
                             "target_kind" => entry.kind, "key" => DeepCopy.call(entry.key))
      end

      def all_reference_entries(change_set: nil)
        ids = @catalog.kinds.map(&:id) + @catalog.reference_targets.map(&:id)
        ids.flat_map { |id| reference_entries(id, :change_set => change_set) }
      end

      def reference_entries(kind_id, change_set: nil)
        if @catalog.kind?(kind_id)
          kind = @catalog.kind(kind_id)
          ids = kind.store.ids(@model)
          ids += change_set.writes.select { |write| write.kind == kind_id }.map(&:id) if change_set
          return ids.uniq.filter_map do |id|
            staged = change_set&.find(kind_id, id)
            record = staged ? staged.after : read(kind, id)
            ReferenceEntry.new(:kind => kind_id, :key => id, :record => record) if record
          end
        end
        target = @catalog.reference_target(kind_id)
        unless target
          raise CodedError.new("reference.invalid", "Reference target #{kind_id} is not registered.",
                               "target_kind" => kind_id)
        end

        target.entries(@model)
      end

      def reference_problems(entry)
        return @catalog.kind(entry.kind).problems(entry.record) if @catalog.kind?(entry.kind)

        @catalog.reference_target(entry.kind).validator.call(entry.record)
      end

      def validate_reference_plan!(plan)
        removed = plan.removals.map do |removal|
          ReferenceEntry.new(:kind => removal.kind, :key => removal.key, :record => removal.before)
        end
        (plan.entries + removed).each do |entry|
          unless @catalog.reference_target(entry.kind)
            raise CodedError.new("reference.invalid", "Planned entity target #{entry.kind} is not registered.")
          end

          problems = reference_problems(entry)
          next if problems.empty?

          raise CodedError.new("validation.failed", "Planned #{entry.kind} is invalid: #{problems.first}.")
        end
      end
    end
  end
end
