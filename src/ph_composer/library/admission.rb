# frozen_string_literal: true

require "json"
require_relative "library_file"

module PhComposer
  module Library
    # Every provider passes the same schema and privacy admission before a generation is published.
    # Third-party diagnostics are reduced to declared identities and codes, never arbitrary text.
    module Admission
      MAX_ROWS = 20_000
      MAX_BYTES = 64 * 1024 * 1024
      NOTE_FIELDS = %w[code kind library_id record_id index].freeze

      module_function

      def call(batch, kind:, adapter:)
        unless batch.is_a?(Provider::Batch)
          raise Error.new("library.provider_invalid", "The provider response is malformed.")
        end
        if batch.rows.length > MAX_ROWS || JSON.generate(batch.to_h).bytesize > MAX_BYTES
          raise Error.new("library.catalog_budget", "The provider response exceeds the catalog budget.")
        end

        warnings = notes(batch.warnings)
        unavailable = notes(batch.unavailable)
        duplicate = duplicate_libraries(batch.rows)
        duplicate.each do |id|
          unavailable << { "code" => "library.duplicate_record_id", "kind" => kind, "library_id" => id }
        end
        unsupported = unsupported_libraries(batch.rows, adapter)
        unsupported.each do |id|
          unavailable << { "code" => "library.kind_schema_unsupported", "kind" => kind, "library_id" => id }
        end
        rows = batch.rows.filter_map do |row|
          next if duplicate.include?(row.fetch("library_id")) || unsupported.include?(row.fetch("library_id"))

          admitted(row, kind, adapter, warnings)
        end
        # Admission is the one place rows are labelled, so it is the one place they are ordered.
        rows.sort_by! do |row|
          label = row.fetch("display_label")
          [row.fetch("library_id"), label.downcase, label, row.fetch("record_id")]
        end
        Provider::Batch.new(:rows => rows, :warnings => warnings, :unavailable => unavailable.uniq,
                            :freshness => freshness_of(batch))
      rescue JSON::GeneratorError, EncodingError
        raise Error.new("library.provider_invalid", "The provider response is malformed."), :cause => nil
      end

      # A version 2 snapshot: the v1 admission of its batch, once every row has exactly one positive
      # source revision and no revision names a row the batch does not hold. Any break refuses the
      # whole snapshot, so no row is published without its exact revision. Returns the admitted batch
      # and the revisions of the rows it kept.
      def revisioned(response, kind:, adapter:)
        unless response.is_a?(Provider::RevisionedBatch)
          raise Error.new("library.provider_invalid", "The provider response is malformed.")
        end

        keys = response.batch.rows.map { |row| Provider.source_key(kind, row) }
        revisions = response.source_revisions
        valid = keys.uniq.length == keys.length && revisions.keys.sort == keys.sort &&
                revisions.values.all? { |value| value.is_a?(Integer) && value.positive? }
        unless valid
          raise Error.new("library.source_revision_invalid",
                          "The provider snapshot does not give every record exactly one source revision.")
        end

        batch = call(response.batch, :kind => kind, :adapter => adapter)
        kept = batch.rows.map { |row| Provider.source_key(kind, row) }
        [batch, Provider.immutable(revisions.slice(*kept))]
      end

      # Each library that repeats a record id: the whole library is unavailable, not just the repeat.
      def duplicate_libraries(rows)
        rows.group_by { |row| [row.fetch("library_id"), row.fetch("record_id")] }
            .select { |_identity, repeated| repeated.length > 1 }.keys.map(&:first).uniq
      end

      # Each library with a row in a wire schema version the adapter does not read.
      def unsupported_libraries(rows, adapter)
        rows.reject { |row| row.fetch("wire_schema_version") == adapter.wire_version }
            .map { |row| row.fetch("library_id") }.uniq
      end

      # The provider's timestamps that read as ISO 8601; anything else is dropped.
      def freshness_of(batch)
        batch.freshness.slice("loaded_at", "exported_at").select do |_key, value|
          value.is_a?(String) && /\A\d{4}-\d\d-\d\dT[0-9:.+-]+Z?\z/.match?(value)
        end
      end

      # One row with its normalized snapshot and label, or nil with the reason added to `warnings`.
      def admitted(row, kind, adapter, warnings)
        note = ->(code) {
          { "code" => code, "kind" => kind, "library_id" => row.fetch("library_id"),
            "record_id" => row.fetch("record_id") }
        }
        snapshot, codes = LibraryFile.normalize_row(row.fetch("snapshot"), adapter.wire_schema)
        warnings.concat(codes.map(&note))
        return unless snapshot

        mapped = semantic_row(snapshot, adapter)
        label = mapped && label_for(adapter, mapped)
        unless label
          warnings << note.call(mapped ? "library.row_label_invalid" : "library.row_semantic_invalid")
          return
        end

        row.merge("snapshot" => snapshot, "display_label" => label)
      end

      # The row's mapped values, or nil when the adapter's semantic check refuses them.
      def semantic_row(snapshot, adapter)
        mapped = adapter.map.call(DeepCopy.call(snapshot))
        mapped if JsonValue.problems(mapped).empty? && JsonSchema.validate(mapped, adapter.mapped_schema).empty?
      rescue CodedError => error
        raise unless error.code == "library.row_semantic_invalid"

        nil
      end

      # The adapter's label for mapped values, trimmed, or nil when it does not give nonblank JSON text.
      def label_for(adapter, mapped)
        label = adapter.display_label.call(DeepCopy.call(mapped))
        return unless label.is_a?(String) && JsonValue.problems(label).empty?

        label.strip.empty? ? nil : label.strip
      rescue StandardError
        nil
      end

      def notes(values)
        values.filter_map do |row|
          next unless row.is_a?(Hash) && row["code"].is_a?(String) && /\Alibrary\.[a-z0-9_.]+\z/.match?(row["code"])

          row.slice(*NOTE_FIELDS).select do |key, value|
            key == "index" ? value.is_a?(Integer) && value >= 0 : value.is_a?(String)
          end
        end
      end
      private_class_method :notes, :semantic_row, :admitted
    end
  end
end
