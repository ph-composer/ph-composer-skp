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

      attr_reader :id, :label, :schema_version, :id_prefix, :fields, :store, :parts

      # `validate`, when given, is `->(values) { [finding, ...] }` for rules a schema cannot express. The kind
      # keeps frozen copies of its id, label, prefix and fields; `validate` and `store` are kept as given.
      #
      # `owner_writes_metadata` is true for a kind whose owner keeps copies of its records elsewhere, such as
      # Zone options copied into each Zone's evidence: only the owner's own actions may change its metadata,
      # so ph_composer.records.update_metadata refuses it as target.wrong_kind.
      #
      # `parts` are the Records::Part declarations of nested objects that carry their own `user_data`, such as
      # an Assembly's Layers and Layer-Segments; the kind validates each part's map as it does the record's.
      def initialize(id:, label:, schema_version:, id_prefix:, fields:, validate: nil, store: nil, references: [],
                     owner_writes_metadata: false, parts: [])
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
        @parts = parts.map { |part| Fields.detached(part) }.freeze
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
                       :values_schema => values_schema, :references => references, :parts => parts)
      end

      # Every reason a `parts` declaration does not fit this kind's values schema, for registration.
      def part_declaration_problems
        paths = parts.map(&:path)
        parts.flat_map { |part| part.declaration_problems(values_schema, paths) }
      end

      # [part, member] for the part `part_ids` names in `record`, the member being the object inside
      # `record`; nil when no declared part has a member at that id path.
      def part(record, part_ids)
        parts.each do |part|
          member = part.find(record, part_ids)
          return [part, member] if member
        end
        nil
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

          found.concat(map_problems(record[key], key))
        end
        parts.each { |part| found.concat(part_problems(part, record)) }
        found
      end

      # A part's members are named by an id unique within their parent, and any map they carry is plain JSON.
      def part_problems(part, record)
        parent = parts.find { |candidate| part.path.start_with?("#{candidate.path}.") }&.label || label
        found = []
        part.sibling_groups(record).each do |members|
          ids = members.map { |member| member["id"] }
          found << "#{part.label} ids must be unique within their #{parent}." unless ids.uniq.length == ids.length
          members.select { |member| member.key?("user_data") }.each do |member|
            found.concat(map_problems(member["user_data"], "#{part.label} #{member['id']} user_data"))
          end
        end
        found
      end

      def map_problems(value, name)
        found = []
        found << "#{name} must be a JSON object" unless value.is_a?(Hash)
        found.concat(JsonValue.problems(value).map { |problem| "#{name} #{problem}" })
      end
    end
  end
end
