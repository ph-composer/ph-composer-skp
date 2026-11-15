# frozen_string_literal: true

module PhComposer
  module Records
    # The metadata rules every stored record follows, catalog or entity-owned (context/CONTRACTS.md,
    # "Records and extension data"): whole-map `user_data` replacement, installed payload replacement
    # under the envelope statuses, the status map a read reports, and the pre-image check an entity
    # owner's metadata action makes. Pure: detached records in, detached records or a CodedError out.
    module Metadata
      # The most top-level keys a report of a discarded map lists, and the most discarded maps it lists.
      REPORT_LIMIT = 50
      # The most bytes a discard report's rows serialize to, so a delete or merge result and its outcome
      # envelope fit one agent reply (Pages::REPLY_BYTES).
      REPORT_BYTES = 8 * 1024

      module_function

      # What an operation reports of one `user_data` map it discards, such as a repaired Edge's: the
      # first REPORT_LIMIT top-level keys in sorted order, each cut to OccurrencePath::NAME_CHARACTERS, and
      # how many the map holds.
      def discarded_keys(map)
        names = map.is_a?(Hash) ? map.keys.sort : []
        { "user_data_keys" => names.first(REPORT_LIMIT).map { |key| key[0, OccurrencePath::NAME_CHARACTERS] },
          "user_data_key_total" => names.length }
      end

      # What removing `records` of `kind` discards, for a merge or delete result (D-UD-5): each record, then
      # each of its declared parts (Records::Part), whose map was not empty, in the order given, by `id` and,
      # for a part, `part_ids`, as `discard_report` bounds them. Undo brings them back.
      def removed_user_data(kind, records)
        mapped = records.flat_map do |record|
          address = { "id" => record.fetch("id") }
          parts = kind.parts.flat_map do |part|
            part.addressed_members(record).map { |ids, member| [address.merge("part_ids" => ids), member["user_data"]] }
          end
          [[address, record["user_data"]]].concat(parts).select { |_address, map| map.is_a?(Hash) && !map.empty? }
        end
        discard_report(mapped)
      end

      # The report every delete and merge makes of the non-empty maps it discards, given as [address, map]
      # pairs in report order: removed_user_data lists the first REPORT_LIMIT, each by its address and key
      # total, then fills in their sorted top-level keys, the first REPORT_LIMIT of each cut to
      # OccurrencePath::NAME_CHARACTERS, in row order until the rows reach REPORT_BYTES; removed_user_data_total
      # counts them all, and removed_user_data_truncated says whether a map or a key was left out.
      def discard_report(addressed)
        rows = []
        used = 2
        addressed.first(REPORT_LIMIT).each do |address, map|
          row = address.merge("user_data_keys" => [], "user_data_key_total" => map.length)
          size = JSON.generate(row).bytesize + (rows.empty? ? 0 : 1)
          break if used + size > REPORT_BYTES

          rows << row
          used += size
        end
        fill_keys(rows, addressed.map(&:last), used)
        cut = rows.length < addressed.length ||
              rows.any? { |row| row.fetch("user_data_keys").length < row.fetch("user_data_key_total") }
        { "removed_user_data" => rows, "removed_user_data_total" => addressed.length,
          "removed_user_data_truncated" => cut }
      end

      # Adds each row's keys from its map, in row order, while the rows stay within REPORT_BYTES.
      def fill_keys(rows, maps, used)
        rows.zip(maps).each do |row, map|
          keys = row.fetch("user_data_keys")
          map.keys.sort.first(REPORT_LIMIT).each do |name|
            key = name[0, OccurrencePath::NAME_CHARACTERS]
            size = JSON.generate(key).bytesize + (keys.empty? ? 0 : 1)
            return if used + size > REPORT_BYTES

            keys << key
            used += size
          end
        end
      end

      # Each envelope's status against what is installed (Extension::STATUSES), by namespace.
      def status_map(record, catalog)
        record.fetch("extension_data", {}).to_h do |namespace, envelope|
          [namespace, Extension.status(envelope, catalog.extension(namespace))]
        end
      end

      # The record after the update. Keys the update does not name are untouched, so a legacy record
      # without user_data stays without it; a record stored without a map reads it as empty, so clearing
      # that map leaves it absent and the update changes nothing.
      def updated(record, catalog, user_data: nil, extension_payloads: {})
        after = DeepCopy.call(record)
        after["user_data"] = checked_user_data(user_data) unless user_data.nil?
        after.delete("user_data") if after["user_data"] == {} && !record.key?("user_data")
        extension_payloads.each { |namespace, payload| set_extension_payload(after, namespace, payload, catalog) }
        after
      end

      # Refuses target.changed unless the stored metadata is what the caller last read, absent maps
      # reading as empty.
      def check_expected!(record, expected, label)
        current = { "user_data" => record.fetch("user_data", {}),
                    "extension_data" => record.fetch("extension_data", {}) }
        return if current == expected

        raise CodedError.new("target.changed", "#{label} #{record['id']} metadata changed since it was read.")
      end

      # The batch an owner's update_metadata action takes, one entry per reference: identical repeats
      # collapse; an entry naming nothing to write, or two entries naming one target differently, refuse.
      def distinct_updates(updates)
        updates.each_with_object({}) do |update, kept|
          unless update.key?("user_data") || update.key?("extension_payloads")
            raise CodedError.new("params.invalid", "Each update names user_data, extension_payloads or both.")
          end

          key = CanonicalJson.generate(update.fetch("reference"))
          if kept.key?(key) && kept[key] != update
            raise CodedError.new("params.invalid", "Two updates name one target differently.")
          end

          kept[key] = update
        end.values
      end

      # One target's record after its update: the pre-image checked against `stored`, what the caller
      # read; the maps written onto `record`, the record as the proposal already leaves it (an owner
      # repair staged earlier in the same action may have changed it); and every record a written
      # payload names resolved, through `reference_plan` when the proposal changes identities. Equal to
      # `record` when the update writes what is already there.
      def planned(engine, catalog, record, update, label, stored: record, reference_plan: nil)
        check_expected!(stored, update.fetch("expected_metadata"), label)
        payloads = update.fetch("extension_payloads", {})
        after = updated(record, catalog, :user_data => update["user_data"], :extension_payloads => payloads)
        payloads.each_key do |namespace|
          envelope = after.fetch("extension_data").fetch(namespace)
          Extension.referenced_ids(envelope.fetch("payload"), envelope.fetch("references", [])).each do |kind, id|
            engine.resolve_reference(kind, id, :reference_plan => reference_plan)
          end
        end
        after
      end

      def checked_user_data(user_data)
        problems = user_data.is_a?(Hash) ? JsonValue.problems(user_data) : ["$ must be a JSON object"]
        return DeepCopy.call(user_data) if problems.empty?

        raise CodedError.new("params.invalid", "User data must be plain JSON: #{problems.first}.",
                             "findings" => problems)
      end

      def set_extension_payload(record, namespace, payload, catalog)
        extension = catalog.extension(namespace)
        current = record.dig("extension_data", namespace)
        status = current && Extension.status(current, extension)
        # Replacing an invalid payload with a valid one depends on nothing stored, so it repairs it.
        writable = extension && [nil, "understood", "invalid"].include?(status)
        refuse_extension!(namespace, record["id"], status || "unavailable") unless writable
        problems = extension.problems(payload)
        unless problems.empty?
          raise CodedError.new("validation.failed", "#{namespace} data is not valid: #{problems.first}.",
                               "findings" => problems)
        end

        (record["extension_data"] ||= {})[namespace] = extension.envelope(DeepCopy.call(payload))
      end

      def refuse_extension!(namespace, id, status)
        if status == "outdated"
          message = "#{namespace} data on #{id} is stored at an older version; migrate it before changing it."
          raise CodedError.new("extension.migration_required", message, "namespace" => namespace)
        end
        if status == "unavailable"
          raise CodedError.new("extension.unavailable", "#{namespace} is not installed, so its data on #{id} " \
                                                        "cannot be changed.", "namespace" => namespace)
        end
        if status == "invalid"
          message = "#{namespace} data on #{id} does not meet the installed extension's contract, so it cannot " \
                    "be copied or migrated. Replace it with valid data first."
          raise CodedError.new("extension.invalid", message, "namespace" => namespace, "status" => status)
        end

        message = "#{namespace} data on #{id} uses a version the installed extension cannot read."
        raise CodedError.new("extension.schema_unsupported", message, "namespace" => namespace)
      end
      private_class_method :fill_keys
    end
  end
end
