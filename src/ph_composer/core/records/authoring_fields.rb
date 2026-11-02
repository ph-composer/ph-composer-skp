# frozen_string_literal: true

require "time"

module PhComposer
  module Records
    # Shared authoring fields. Catalog provenance has no transport address or credentials.
    module AuthoringFields
      module_function

      def number(unit, nullable: false)
        { "type" => nullable ? %w[number null] : "number", "exclusiveMinimum" => 0, "x-unit" => unit }
      end

      def field(key, schema, required: false)
        Field.new(:key => key, :schema => schema, :required => required)
      end

      def common
        [field("name", { "type" => "string", "minLength" => 1 }, :required => true),
         field("notes", { "type" => "string" }),
         field("datasheet_links", { "type" => "array", "items" => { "type" => "string" } }),
         field("source", source_schema)]
      end

      def source_schema
        properties = %w[provider_kind library_id record_kind record_id fingerprint copied_at].to_h do |key|
          [key, { "type" => "string", "minLength" => 1 }]
        end
        # A hosted source's exact revision. Both keys or neither: a copy without them is legacy, and its
        # revision is unknown, never inferred from a matching fingerprint.
        properties.merge!("kind" => { "type" => "string", "enum" => %w[manual derived library] },
                          "fingerprint_version" => { "type" => "integer", "enum" => [1] },
                          "snapshot" => { "type" => "object" },
                          "source_revision" => { "type" => "integer", "minimum" => 1 },
                          "source_revision_schema_version" => { "type" => "integer", "enum" => [1] })
        SchemaShapes.object(properties, :optional => properties.keys - ["kind"])
      end

      # Until a library adapter declares a smaller wire set, snapshots have this kind's authored
      # field ceiling. Provenance and arbitrary metadata are excluded from that copied row.
      def source_snapshot_schema(fields)
        properties = fields.reject { |field| field.key == "source" }.to_h { |field| [field.key, field.schema] }
        SchemaShapes.object(properties, :optional => properties.keys)
      end

      # `fields` with the source field's snapshot declared, by default as the authored ceiling above.
      # The list passed in is not changed.
      def with_source_snapshot(fields, snapshot_schema = source_snapshot_schema(fields))
        fields.map do |item|
          next item unless item.key == "source"

          properties = item.schema.fetch("properties").merge("snapshot" => snapshot_schema)
          field("source", item.schema.merge("properties" => properties), :required => item.required)
        end
      end

      def source_problems(source, snapshot_schema)
        return [] unless source && source.fetch("kind") == "library"

        required = %w[provider_kind library_id record_kind record_id fingerprint fingerprint_version copied_at snapshot]
        missing = required - source.keys
        return ["Library provenance requires #{missing.join(', ')}."] unless missing.empty?

        found = JsonSchema.validate(source.fetch("snapshot"), snapshot_schema)
        found << "Library fingerprint version must be 1." unless source.fetch("fingerprint_version") == 1
        if source.key?("source_revision") != source.key?("source_revision_schema_version")
          found << "Library source revision and its schema version go together."
        end
        begin
          Time.iso8601(source.fetch("copied_at"))
        rescue ArgumentError
          found << "Library copied_at must be an ISO 8601 timestamp."
        end
        found
      end

      def problems(values)
        found = []
        found << "Name must contain non-whitespace text." if values.fetch("name").strip.empty?
        color = values["color"]
        found << "Color must be a six-digit hexadecimal color." if color && !/\A#[0-9a-fA-F]{6}\z/.match?(color)
        source = values["source"]
        if source && source.fetch("kind") != "library" && source.keys != ["kind"]
          found << "Only library sources can carry library provenance."
        end
        found
      end

      def defaults(values)
        { "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" } }
          .merge(DeepCopy.call(values)).tap { |result| result["name"] = result.fetch("name").strip }
      end
    end
  end
end
