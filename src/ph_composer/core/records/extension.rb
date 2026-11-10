# frozen_string_literal: true

module PhComposer
  module Records
    # A maintained extension's structured data on records (context/CONTRACTS.md, "Records and
    # extension data"). A record carries one envelope per namespace under `extension_data`:
    #
    #   {"example.review": {"schema_version": 2, "payload": {...},
    #    "references": [{"path": "$.checked_against", "target_kind": "example.part", "cardinality": "one"}],
    #    "export_relevance": "required"}}
    #
    # The envelope stores its own reference declarations and export relevance, so a record keeps
    # them even where the extension is not installed. Preserving a payload never implies it was
    # understood, validated or may be exported.
    class Extension
      RELEVANCE = %w[required local_only unknown].freeze

      # How a record's envelope for one namespace stands against what is installed.
      #   understood   registered, stored at the current version, and its payload and reference
      #                declarations meet the installed contract
      #   invalid      registered and current, but the payload fails the installed validator or the
      #                envelope does not declare the installed references. Kept as stored; nothing
      #                that depends on it (copy, migration, export) may use it
      #   outdated     registered, stored at an older version that migrations can raise
      #   unsupported  a newer version than installed, or an envelope that cannot be read
      #   unavailable  no extension with this namespace is installed
      STATUSES = %w[understood invalid outdated unsupported unavailable].freeze
      # The same, as discovery publishes it beside the installed extensions.
      STATUS_MEANINGS = {
        "understood" => "Installed, current, and the payload meets the installed contract.",
        "invalid" => "Installed and current, but the payload or its references fail the installed contract; " \
                     "kept as stored and never copied, migrated or exported.",
        "outdated" => "Stored at an older version the installed migrations can raise.",
        "unsupported" => "Stored at a newer version than installed, or not readable as an envelope.",
        "unavailable" => "No extension with this namespace is installed; the envelope is preserved as stored."
      }.freeze

      attr_reader :namespace, :schema_version, :references, :export_relevance, :copy, :migrations

      # `references` are the current version's declarations. `migrations` maps a version to
      # `->(payload) { payload_at_the_next_version }`. `validate` is `->(payload) { [finding, ...] }`.
      # `copy` is :remap (declared references follow a duplicated collection) or :refuse.
      def initialize(namespace:, schema_version:, references: [], export_relevance: "unknown",
                     migrations: {}, validate: nil, copy: :remap)
        @namespace = DeepCopy.frozen(namespace)
        @schema_version = schema_version
        @references = DeepCopy.frozen(references.map { |reference| DeepCopy.string_keys(reference) })
        @export_relevance = DeepCopy.frozen(export_relevance)
        @migrations = migrations.freeze
        @validate = validate
        @copy = copy
      end

      # What `describe` answers for this namespace: the installed contract only. A declaration carries a
      # validator, not a JSON Schema, so `payload_schema` is null rather than one inferred from data.
      def descriptor
        { "namespace" => namespace, "schema_version" => schema_version, "references" => DeepCopy.call(references),
          "export_relevance" => export_relevance, "copy" => @copy.to_s, "migrates_from" => migrations.keys.sort,
          "payload_schema" => nil, "statuses" => STATUS_MEANINGS }
      end

      def problems(payload)
        found = JsonValue.problems(payload)
        found.concat(Array(@validate&.call(payload))) if found.empty?
        found
      end

      # Every reason a current-version envelope does not meet this installed contract. Empty means it is
      # understood. A validator that raises counts as a finding, never as a pass.
      def envelope_problems(envelope)
        canonical = ->(list) { list.map { |reference| CanonicalJson.generate(reference) }.sort }
        declared = canonical.call(Array(envelope.fetch("references", [])))
        found = declared == canonical.call(references) ? [] : ["references differ from the installed declaration"]
        found + problems(envelope.fetch("payload"))
      rescue StandardError => error
        ["the installed validator failed (#{error.class})"]
      end

      # A current-version envelope for `payload`, carrying this declaration's references.
      def envelope(payload)
        {
          "schema_version" => schema_version, "payload" => payload,
          "references" => DeepCopy.call(references), "export_relevance" => export_relevance
        }
      end

      # The envelope's status given the installed extension for its namespace, or nil.
      def self.status(envelope, installed)
        return "unsupported" unless readable?(envelope)
        return "unavailable" unless installed

        version = envelope.fetch("schema_version")
        if version == installed.schema_version
          return installed.envelope_problems(envelope).empty? ? "understood" : "invalid"
        end
        return "unsupported" if version > installed.schema_version

        migratable = (version...installed.schema_version).all? { |step| installed.migrations.key?(step) }
        migratable ? "outdated" : "unsupported"
      end

      # Whether the envelope's versioned shape can be read at all; only then are its declared
      # references usable.
      def self.readable?(envelope)
        return false unless envelope.is_a?(Hash) && envelope["schema_version"].is_a?(Integer)
        return false unless envelope.key?("payload")
        return false unless RELEVANCE.include?(envelope.fetch("export_relevance", "unknown"))

        Array(envelope.fetch("references", [])).all? do |reference|
          reference.is_a?(Hash) && reference["path"].to_s.start_with?("$.") &&
            reference["target_kind"].is_a?(String) && %w[one many].include?(reference["cardinality"])
        end
      end

      # The payload with every declared reference whose id is in `mapping` replaced by its counterpart.
      def self.remap(payload, references, mapping, reference_plan: nil, mapping_kind: nil)
        references.reduce(DeepCopy.call(payload)) do |copy, reference|
          keys = reference.fetch("path").delete_prefix("$.").split(".")
          parent = keys[0...-1].reduce(copy) { |node, key| node.is_a?(Hash) ? node[key] : nil }
          next copy unless parent.is_a?(Hash) && parent.key?(keys.last)

          typed_mapping = reference_mapping(mapping, reference, reference_plan, mapping_kind)
          current = parent[keys.last]
          parent[keys.last] =
            if current.is_a?(Array)
              current.map { |id| typed_mapping.fetch(id, id) }
            else
              typed_mapping.fetch(current, current)
            end
          copy
        end
      end

      def self.reference_mapping(mapping, reference, plan, mapping_kind)
        return reference.fetch("target_kind") == mapping_kind ? mapping : {} if mapping_kind
        return mapping unless plan

        targets = plan.entries.select { |entry| entry.kind == reference.fetch("target_kind") }
        ids = targets.map { |entry| entry.record.fetch("id") }
        mapping.select { |_source, copied| ids.include?(copied) }
      end
      private_class_method :reference_mapping

      # The ids a payload's declared references name, as [target_kind, id] pairs.
      def self.referenced_ids(payload, references)
        references.flat_map do |reference|
          keys = reference.fetch("path").delete_prefix("$.").split(".")
          value = keys.reduce(payload) { |node, key| node.is_a?(Hash) ? node[key] : nil }
          Array(value).compact.map { |id| [reference.fetch("target_kind"), id] }
        end
      end

      # Copy rules are shared by catalog records and entity-owned feature records. A copied
      # identity must not carry references whose meaning the installed extension cannot check.
      def self.check_copy_rules!(data, catalog, label, id)
        data.each do |namespace, envelope|
          installed = catalog.extension(namespace)
          status = status(envelope, installed)
          next if status == "understood" && installed.copy == :remap

          Metadata.refuse_extension!(namespace, id, status) if status == "invalid"
          raise CodedError.new(
            "copy.rule_missing",
            "#{label} #{id} carries #{namespace} data (#{status}) that cannot be copied safely.",
            "id" => id, "namespace" => namespace, "status" => status
          )
        end
      end

      # Entity-owned records pass their Engine so declared references are checked before
      # a host operation opens. Catalog records validate staged references through Engine itself.
      def self.copy_data(data, catalog, label, id, mapping, engine: nil, reference_plan: nil, mapping_kind: nil)
        check_copy_rules!(data, catalog, label, id)
        copied = DeepCopy.call(data).each_value do |envelope|
          envelope["payload"] = remap(envelope.fetch("payload"), envelope.fetch("references", []), mapping,
                                      :reference_plan => reference_plan, :mapping_kind => mapping_kind)
        end
        check_copy_rules!(copied, catalog, label, id)
        if engine
          copied.each_value do |envelope|
            referenced_ids(envelope.fetch("payload"), envelope.fetch("references", [])).each do |target_kind, target_id|
              engine.resolve_reference(target_kind, target_id, :reference_plan => reference_plan)
            end
          end
        end
        copied
      end
    end
  end
end
