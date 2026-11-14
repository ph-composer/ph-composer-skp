# frozen_string_literal: true

module PhComposer
  module Records
    # A stored record kind: its id, schema version, id prefix and fields. Validation here is pure: it
    # reads explicit values and never touches SketchUp, so a kind's rules run in any test.
    #
    # A stored record is flat JSON:
    #
    #   {"id": "exp_Ab12Cd34Ef56", "schema_version": 1, "label": "Sill", "length_mm": 1200.0,
    #    "definition_id": "exd_...", "user_data": {...}, "extension_data": {...}}
    #
    # `user_data` is JSON-compatible metadata under contributor namespaces, preserved and never
    # interpreted (context/EXTENSIBILITY.md). `extension_data` holds versioned payloads that
    # registered extensions own (extension.rb). Both are optional; absent reads as empty.
    class RecordKind
      RESERVED_KEYS = %w[id schema_version user_data extension_data].freeze

      attr_reader :id, :label, :schema_version, :id_prefix, :fields, :store

      # `validate`, when given, is `->(values) { [finding, ...] }` for rules a schema cannot express. The kind
      # keeps frozen copies of its id, label, prefix and fields; `validate` and `store` are kept as given.
      #
      # `owner_writes_metadata` is true for a kind whose owner keeps copies of its records elsewhere, such as
      # Zone options copied into each Zone's evidence: only the owner's own actions may change its metadata,
      # so ph_composer.records.update_metadata refuses it as target.wrong_kind.
      def initialize(id:, label:, schema_version:, id_prefix:, fields:, validate: nil, store: nil, references: [],
                     owner_writes_metadata: false)
        @id = DeepCopy.frozen(id)
        @label = DeepCopy.frozen(label)
        @schema_version = schema_version
        @id_prefix = DeepCopy.frozen(id_prefix)
        @fields = fields.map { |field| Fields.detached(field) }.freeze
        @nested_references = references.map { |reference| Fields.detached(reference) }.freeze
        @validate = validate
        @store = store || DictionaryStore.new(id)
        @id_pattern = Identity.pattern(id_prefix)
        @owner_writes_metadata = owner_writes_metadata
      end

      def owner_writes_metadata?
        @owner_writes_metadata
      end

      def references
        fields.select(&:reference?) + @nested_references
      end

      def field(key)
        fields.find { |field| field.key == key }
      end

      # The JSON Schema of this kind's values, published by discovery and used for validation.
      def values_schema
        {
          "type" => "object",
          "additionalProperties" => false,
          "required" => fields.select(&:required).map(&:key),
          "properties" => fields.to_h { |field| [field.key, field.schema] }
        }
      end

      def descriptor
        Descriptor.new(:kind => id, :label => label, :schema_version => schema_version,
                       :values_schema => values_schema, :references => references)
      end

      # [[target_kind, id], ...] for every core reference `record` holds (Descriptor#referenced_targets
      # answers the same for an entity-owned target).
      def referenced_targets(record)
        references.flat_map { |reference| reference.ids(record).map { |id| [reference.target_kind, id] } }
      end

      def values(record)
        record.reject { |key, _value| RESERVED_KEYS.include?(key) }
      end

      # Every reason `record` is not a valid stored record of this kind. Empty means it may be written.
      def problems(record)
        return ["#{label} record must be a JSON object"] unless record.is_a?(Hash)

        found = []
        found << "#{label} id #{record['id'].inspect} is invalid" unless @id_pattern.match?(record["id"].to_s)
        unless record["schema_version"] == schema_version
          found << "#{label} #{record['id']} uses schema version #{record['schema_version'].inspect}, " \
                   "not #{schema_version}"
        end
        found.concat(JsonSchema.validate(values(record), values_schema))
        found.concat(metadata_problems(record))
        found.concat(Array(@validate&.call(values(record)))) if found.empty?
        found
      end

      private

      def metadata_problems(record)
        found = []
        %w[user_data extension_data].each do |key|
          next unless record.key?(key)

          value = record[key]
          found << "#{key} must be a JSON object" unless value.is_a?(Hash)
          found.concat(JsonValue.problems(value).map { |problem| "#{key} #{problem}" })
        end
        found
      end
    end
  end
end
