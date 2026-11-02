# frozen_string_literal: true

module PhComposer
  module Library
    class Error < CodedError; end

    # Providers expose catalog data, never transport configuration or Model operations. The reusable
    # contract test accepts any provider implementing id/provider_kind/label/kinds/list/freshness.
    module Provider
      module_function

      # JSON values only, including cycle/encoding checks before any structural copy. The same
      # depth ceiling as JSON.parse keeps a Ruby-only provider from supplying an unrepresentable tree.
      def json_value?(value)
        pending = [[value, []]]
        until pending.empty?
          node, ancestors = pending.pop
          case node
          when Hash, Array
            return false if ancestors.length >= 100 || ancestors.any? { |entry| entry.equal?(node) }
            if node.is_a?(Hash) && node.keys.any? { |key|
              !key.is_a?(String) || !key.valid_encoding? || !(key.encoding == Encoding::UTF_8 || key.ascii_only?)
            }
              return false
            end

            children = node.is_a?(Hash) ? node.values : node
            children.each { |child| pending << [child, ancestors + [node]] }
          when String
            return false unless node.valid_encoding? && (node.encoding == Encoding::UTF_8 || node.ascii_only?)
          when Float
            return false unless node.finite?
          when Integer, TrueClass, FalseClass, NilClass
            next
          else
            return false
          end
        end
        true
      end

      def immutable(value)
        copy = DeepCopy.call(value)
        freeze_tree(copy)
      end

      def freeze_tree(value)
        case value
        when Hash
          value.each do |key, child|
            key.freeze
            freeze_tree(child)
          end
        when Array
          value.each { |child| freeze_tree(child) }
        end
        value.freeze
      end
      private_class_method :freeze_tree

      class Batch
        attr_reader :rows, :warnings, :unavailable, :freshness

        def initialize(rows:, warnings:, unavailable:, freshness:)
          valid = rows.is_a?(Array) && rows.all? { |row| valid_row?(row) } &&
                  warnings.is_a?(Array) && unavailable.is_a?(Array) && freshness.is_a?(Hash) &&
                  Provider.json_value?([rows, warnings, unavailable, freshness])
          unless valid
            raise Error.new("library.provider_invalid", "The provider catalog response is malformed.")
          end

          @rows = Provider.immutable(rows)
          @warnings = Provider.immutable(warnings)
          @unavailable = Provider.immutable(unavailable)
          @freshness = Provider.immutable(freshness)
          freeze
        end

        def to_h
          { "rows" => rows, "warnings" => warnings, "unavailable" => unavailable, "freshness" => freshness }.freeze
        end

        private

        # `display_label` is admission's (Admission.label_for). A provider's own, of any value, is
        # tolerated here and replaced there, so it can neither spoof a label nor reject a usable row.
        def valid_row?(row)
          fields = %w[library_id library_name record_id snapshot wire_schema_version]
          labelled = row.is_a?(Hash) && row.key?("display_label")
          row.is_a?(Hash) && row.keys.length == fields.length + (labelled ? 1 : 0) &&
            fields.all? { |key| row.key?(key) } &&
            %w[library_id library_name record_id].all? { |key| row[key].is_a?(String) && !row[key].strip.empty? } &&
            row["wire_schema_version"].is_a?(Integer) && row["wire_schema_version"].positive? &&
            row["snapshot"].is_a?(Hash) && row.dig("snapshot", "id") == row["record_id"]
        end
      end

      # What a contract version 2 provider's `poll_load` completes with: a v1 Batch, unchanged, plus the
      # snapshot it was read from and each row's exact source revision, keyed by `source_key`. The
      # revisions are checked against the rows at admission (Admission.revisioned), not here.
      class RevisionedBatch
        attr_reader :batch, :snapshot, :source_revisions

        def initialize(batch:, snapshot:, source_revisions:)
          valid = batch.is_a?(Batch) && valid_snapshot?(snapshot) && source_revisions.is_a?(Hash) &&
                  Provider.json_value?([snapshot, source_revisions])
          unless valid
            raise Error.new("library.provider_invalid", "The provider snapshot response is malformed.")
          end

          @batch = batch
          @snapshot = Provider.immutable(snapshot)
          @source_revisions = Provider.immutable(source_revisions)
          freeze
        end

        private

        def valid_snapshot?(snapshot)
          snapshot.is_a?(Hash) && snapshot.keys.sort == %w[id library_revision projection_schema_version] &&
            snapshot["id"].is_a?(String) && /\A[A-Za-z0-9_.:-]{1,128}\z/.match?(snapshot["id"]) &&
            %w[library_revision projection_schema_version].all? do |key|
              snapshot[key].is_a?(Integer) && snapshot[key].positive?
            end
        end
      end

      # The key a row's source revision is listed under: `<wire kind>/<library id>/<record id>`.
      def source_key(kind, row)
        "#{kind}/#{row.fetch('library_id')}/#{row.fetch('record_id')}"
      end
    end
  end
end
