# frozen_string_literal: true

require "json"

module PhComposer
  module Records
    # Reads records and proposes changes to them for one Model. It owns identity, reference checks,
    # metadata and extension-data rules (context/CONTRACTS.md, "Records and extension data"). Reads
    # never repair or write. Proposals add writes to a ChangeSet and never write; `apply` writes a
    # validated set and is called only inside the dispatcher's operation (shell/dispatch.rb).
    #
    # Refusals raise CodedError with a code from context/CONTRACTS.md, "Outcomes and codes".
    #
    # `identity` names each record a create or duplicate stages. A handler's engine derives them from its
    # request (HandlerRequest.for), so a preview and its invoke at one revision stage the same ids; an engine
    # built for a read or a repair check keeps the random default.
    class Engine
      def initialize(model, catalog, identity: Identity.method(:mint))
        @model = model
        @catalog = catalog
        @identity = identity
      end

      # ---------------------------------------------------------------- reads

      # The stored record, or a refusal naming why it cannot be used.
      # With a `change_set`, a record it stages is read as it will stand: a staged create is found and a
      # staged delete is not.
      def find(kind_id, id, change_set: nil)
        kind = @catalog.kind(kind_id)
        staged = change_set&.find(kind_id, id)
        record = staged ? DeepCopy.call(staged.after) : read(kind, id)
        raise CodedError.new("target.not_found", "There is no #{kind.label} with id #{id}.") unless record

        problems = kind.problems(record)
        return record if problems.empty?

        raise CodedError.new("record.unreadable", "#{kind.label} #{id} cannot be used: #{problems.first}.",
                             "findings" => problems)
      end

      def kind(kind_id)
        @catalog.kind(kind_id)
      end

      def ids(kind_id)
        @catalog.kind(kind_id).store.ids(@model)
      end

      # The caller's view of a stored record: values apart from metadata, absent metadata as empty, and
      # each extension envelope's status. The stored record is not changed.
      def view(kind_id, record)
        extension_data = record.fetch("extension_data", {})
        {
          "kind" => kind_id,
          "id" => record.fetch("id"),
          "schema_version" => record.fetch("schema_version"),
          "values" => DeepCopy.call(@catalog.kind(kind_id).values(record)),
          "user_data" => DeepCopy.call(record.fetch("user_data", {})),
          "extension_data" => DeepCopy.call(extension_data),
          "extension_status" => Metadata.status_map(record, @catalog)
        }
      end

      # The same reads through `change_set`, accepting writes only of `writable_kinds` into it
      # (ProjectedEngine). An empty list gives a read-only projection.
      def projected(change_set, writable_kinds:, refusal_code:)
        ProjectedEngine.new(self, change_set, :writable_kinds => writable_kinds, :refusal_code => refusal_code)
      end

      # ---------------------------------------------------------------- proposals

      def propose_create(kind_id, change_set, values:, user_data: nil)
        staging(change_set) do
          kind = @catalog.kind(kind_id)
          id = Identity.fresh(kind.id_prefix, reserved_ids(kind, change_set), @identity)
          check_value_keys!(kind, values)
          record = { "id" => id, "schema_version" => kind.schema_version }.merge(DeepCopy.call(values))
          record["user_data"] = Metadata.checked_user_data(user_data) unless user_data.nil?
          propose(kind, change_set, nil, record)
          id
        end
      end

      # An ordinary edit. `values` replaces the named fields (nil removes an optional one); `user_data`,
      # when given, replaces the whole mapping. Extension payloads the edit does not name are carried
      # through as they were stored, whether or not their extension is installed. `expected_values`
      # are the values the caller last read; any that differ now refuse the edit.
      def propose_update(kind_id, id, change_set, values: {}, user_data: nil, extension_payloads: {},
                         expected_values: {})
        staging(change_set) do
          kind = @catalog.kind(kind_id)
          before = find(kind_id, id)
          check_expected!(kind, before, expected_values)
          after = Metadata.updated(before, @catalog, :user_data => user_data,
                                                     :extension_payloads => extension_payloads)
          check_value_keys!(kind, values)
          values.each { |key, value| value.nil? ? after.delete(key) : after[key] = DeepCopy.call(value) }
          propose(kind, change_set, before, after)
        end
      end

      # `reference_plan`, when given, is the entity records the same proposal rewrites first (a
      # feature moving every Face off the record it deletes); the reference check reads them as planned.
      def propose_delete(kind_id, id, change_set, expected_values: {}, reference_plan: nil)
        staging(change_set) do
          kind = @catalog.kind(kind_id)
          before = find(kind_id, id)
          check_expected!(kind, before, expected_values)
          change_set.delete(kind.id, :before => before)
          check_identity_removal!(kind.id, id, :change_set => change_set, :reference_plan => reference_plan)
        end
      end

      # Duplicates records as one collection: every new id is allocated first, then each reference
      # between copied records points to the new counterpart while references outside the copy stay
      # shared. `user_data` is copied unchanged. A copy that needs copy rules the installed extensions
      # do not provide is refused whole. An optional block transforms detached authored values only;
      # identity and metadata remain engine-owned. Returns the old-to-new id mapping.
      def propose_duplicate(kind_id, ids, change_set)
        staging(change_set) do
          kind = @catalog.kind(kind_id)
          originals = ids.uniq.map { |id| find(kind_id, id) }
          originals.each do |record|
            Extension.check_copy_rules!(record.fetch("extension_data", {}), @catalog, kind.label, record.fetch("id"))
          end
          reserved = reserved_ids(kind, change_set)
          mapping = originals.to_h do |record|
            [record.fetch("id"), Identity.fresh(kind.id_prefix, reserved, @identity)]
          end
          copies = originals.map do |record|
            copy = copy_of(kind, record, mapping)
            if block_given?
              values = yield DeepCopy.call(kind.values(copy))
              unless values.is_a?(Hash)
                raise CodedError.new("params.invalid", "#{kind.label} duplicate values must be a JSON object.")
              end

              check_value_keys!(kind, values)
              copy = copy.select { |key, _value| RecordKind::RESERVED_KEYS.include?(key) }.merge(DeepCopy.call(values))
            end
            propose(kind, change_set, nil, copy, :check_references => false)
            copy
          end
          # A copy may name a counterpart staged after it, so references are checked once all are staged.
          copies.each { |copy| check_references!(kind, copy, change_set) }
          mapping
        end
      rescue StandardError => error
        change_set.refuse(error)
        raise
      end

      # Raises one namespace's payload to the installed version on each record, through the declared
      # migrations, validating the result. Any failure refuses the whole proposal, so the stored data
      # stays as it was. Returns each record's result: migrated, current or absent.
      def propose_migration(kind_id, ids, namespace, change_set)
        staging(change_set) do
          kind = @catalog.kind(kind_id)
          extension = @catalog.extension(namespace)
          ids.uniq.to_h do |id|
            before = find(kind_id, id)
            envelope = before.dig("extension_data", namespace)
            next [id, "absent"] unless envelope

            status = Extension.status(envelope, extension)
            Metadata.refuse_extension!(namespace, id, status) unless %w[understood outdated].include?(status)
            next [id, "current"] if status == "understood"

            after = DeepCopy.call(before)
            after["extension_data"][namespace] = extension.envelope(migrated_payload(extension, envelope, id))
            propose(kind, change_set, before, after)
            [id, "migrated"]
          end
        end
      end

      # ---------------------------------------------------------------- writes

      def apply(change_set)
        change_set.writes.each do |write|
          store = @catalog.kind(write.kind).store
          write.after ? store.write(@model, write.after) : store.delete(@model, write.id)
        end
      end

      # Whether every record the change set names is stored exactly as it was before. The dispatcher
      # checks this after an abort before it reports the operation as rolled back.
      def unchanged?(change_set)
        change_set.writes.all? { |write| read(@catalog.kind(write.kind), write.id) == write.before }
      rescue JSON::ParserError
        false
      end

      private

      # Runs a proposal; a refusal it raises also marks the change set refused (ChangeSet#refuse).
      def staging(change_set)
        yield
      rescue Error => error
        change_set.refuse(error)
        raise
      end

      def read(kind, id)
        kind.store.read(@model, id)
      rescue JSON::ParserError
        raise CodedError.new("record.unreadable", "#{kind.label} #{id} is not valid JSON.")
      end

      def propose(kind, change_set, before, after, check_references: true)
        problems = kind.problems(after)
        unless problems.empty?
          raise CodedError.new("validation.failed", "#{kind.label} #{after['id']} is not valid: #{problems.first}.",
                               "findings" => problems)
        end

        check_references!(kind, after, change_set) if check_references
        change_set.put(kind.id, :before => before, :after => after)
      end

      # One original with its new id, its references among the copied records pointed at their copies,
      # and its extension data copied under the installed copy rules.
      def copy_of(kind, record, mapping)
        copy = kind.references.reduce(DeepCopy.call(record)) do |value, field|
          field.target_kind == kind.id ? field.remap(value, mapping) : value
        end
        copy["id"] = mapping.fetch(record.fetch("id"))
        if record.key?("extension_data")
          copy["extension_data"] = Extension.copy_data(record.fetch("extension_data"), @catalog, kind.label,
                                                       record.fetch("id"), mapping, :mapping_kind => kind.id)
        end
        copy
      end

      def check_references!(kind, record, change_set)
        targets = kind.referenced_targets(record)
        record.fetch("extension_data", {}).each do |namespace, envelope|
          next unless Extension.status(envelope, @catalog.extension(namespace)) == "understood"

          targets.concat(Extension.referenced_ids(envelope.fetch("payload"), envelope.fetch("references", [])))
        end
        targets.each do |target_kind, id|
          resolve_reference(target_kind, id, :change_set => change_set)
        end
      end

      # Identity and metadata change only through their own arguments, never as a value.
      def check_value_keys!(kind, values)
        reserved = values.keys & RecordKind::RESERVED_KEYS
        return if reserved.empty?

        raise CodedError.new("params.invalid", "#{kind.label} values cannot set #{reserved.join(', ')}.")
      end

      def check_expected!(kind, record, expected_values)
        changed = expected_values.keys.reject { |key| record[key] == expected_values[key] }
        return if changed.empty?

        raise CodedError.new("target.changed", "#{kind.label} #{record['id']} has changed since it was read " \
                                               "(#{changed.join(', ')}).", "fields" => changed)
      end

      def migrated_payload(extension, envelope, id)
        steps = envelope.fetch("schema_version")...extension.schema_version
        payload = steps.reduce(DeepCopy.call(envelope["payload"])) do |value, version|
          extension.migrations.fetch(version).call(value)
        end
        problems = extension.problems(payload)
        return payload if problems.empty?

        message = "#{extension.namespace} data on #{id} is not valid after migration: #{problems.first}."
        raise CodedError.new("extension.migration_failed", message, "findings" => problems)
      rescue StandardError => error
        raise if error.is_a?(CodedError)

        message = "#{extension.namespace} data on #{id} could not be migrated (#{error.class})."
        raise CodedError.new("extension.migration_failed", message)
      end

      def reserved_ids(kind, change_set)
        kind.store.ids(@model) + change_set.writes.map(&:id)
      end
    end
  end
end
