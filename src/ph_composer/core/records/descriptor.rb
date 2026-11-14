# frozen_string_literal: true

module PhComposer
  module Records
    # What one record kind is, whoever stores it: its values schema, its identity field, how one
    # occurrence of it is named, and which of its fields name other records. A catalog kind
    # (record_kind.rb) and an entity-owned reference target (reference_target.rb) each publish one,
    # so discovery, validation and the incoming-reference scan read one shape for both. Describing
    # a kind grants no authority to create or delete what stores it.
    class Descriptor
      IDENTITY_FIELD = "id"
      ANY_OBJECT = { "type" => "object" }.freeze

      attr_reader :kind, :label, :schema_version, :values_schema, :occurrence_schema, :references, :parts

      # `references` are Records::Reference declarations over top-level or nested record fields. `occurrence_schema`
      # is nil for a catalog kind, whose records are named by id alone. `parts` are a catalog kind's
      # Records::Part declarations. The descriptor keeps frozen copies; `view_schema`, `patch_schema` and
      # `to_h` hand out editable ones.
      def initialize(kind:, label:, schema_version: nil, values_schema: ANY_OBJECT, occurrence_schema: nil,
                     references: [], parts: [])
        @kind = DeepCopy.frozen(kind)
        @label = DeepCopy.frozen(label)
        @schema_version = schema_version
        @values_schema = DeepCopy.frozen(values_schema)
        @occurrence_schema = DeepCopy.frozen(occurrence_schema)
        @references = references.map { |reference| Fields.detached(reference) }.freeze
        @parts = parts.map { |part| Fields.detached(part) }.freeze
      end

      # [[target_kind, id], ...] for every core reference `record` holds.
      def referenced_targets(record)
        references.flat_map { |reference| reference.ids(record).map { |id| [reference.target_kind, id] } }
      end

      # One stored record as a read returns it: identity, values and the two metadata maps.
      def view_schema
        {
          "type" => "object", "additionalProperties" => false,
          "required" => %w[id schema_version values user_data extension_data],
          "properties" => {
            IDENTITY_FIELD => { "type" => "string" }, "schema_version" => { "type" => "integer" },
            "values" => DeepCopy.call(values_schema),
            "user_data" => { "type" => "object", "description" => "Contributor metadata, preserved as written." },
            "extension_data" => { "type" => "object", "description" => "Versioned payloads registered extensions own." }
          }
        }
      end

      # A partial change to the values: every field optional, and an explicit null removes one.
      def patch_schema
        patch = DeepCopy.call(values_schema)
        patch.delete("required")
        patch.fetch("properties", {}).each_value do |field|
          field["type"] = (Array(field["type"]) + ["null"]).uniq
          field["enum"] += [nil] if field["enum"] && !field["enum"].include?(nil)
        end
        patch
      end

      # The public, plain-JSON form discovery publishes.
      def to_h
        reference_rows = references.map do |reference|
          { "key" => reference.key, "target_kind" => reference.target_kind, "cardinality" => reference.cardinality }
        end
        DeepCopy.call(
          "id" => kind, "label" => label, "schema_version" => schema_version, "identity_field" => IDENTITY_FIELD,
          "values" => values_schema, "occurrence_reference" => occurrence_schema, "references" => reference_rows,
          "parts" => parts.map { |part| { "label" => part.label, "path" => part.path } }
        )
      end
    end
  end
end
