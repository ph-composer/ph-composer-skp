# frozen_string_literal: true

module PhComposer
  module Library
    # Transport shapes stay generic; each registered kind validates its snapshot and mapped fields.
    module Schemas
      extend SchemaShapes

      TEXT = { "type" => "string" }.freeze
      NULLABLE_TEXT = { "type" => %w[string null] }.freeze
      OBJECT = { "type" => "object" }.freeze
      NULLABLE_NUMBER = { "type" => %w[number null], "minimum" => 0 }.freeze
      GENERATION = { "type" => %w[integer null], "minimum" => 1 }.freeze
      VALUE = { "type" => %w[string number boolean object array null] }.freeze
      BOOLEAN = { "type" => "boolean" }.freeze

      module_function

      # Version 1 catalogs are `unloaded`, `loaded`, `empty` or `failed`; version 2 catalogs are `unloaded`,
      # `loading`, `ready` (with or without rows), `stale` (a failed load kept the last generation),
      # `unavailable` (a failed load had none) or `cancelled`, and name the `snapshot` they were read from.
      def summary
        object({ "provider_id" => TEXT, "kind" => TEXT, "generation" => GENERATION,
                 "state" => { "type" => "string", "enum" => STATES },
                 "warnings" => list(note), "unavailable" => list(note), "freshness" => freshness,
                 "published_at" => NULLABLE_TEXT, "failure" => failure, "age_seconds" => NULLABLE_NUMBER,
                 "snapshot" => snapshot }, :optional => ["snapshot"])
      end

      STATES = %w[unloaded empty loaded failed loading ready stale unavailable cancelled].freeze

      def snapshot
        positive = { "type" => "integer", "minimum" => 1 }
        object({ "id" => TEXT, "library_revision" => positive, "projection_schema_version" => positive })
      end

      def note
        object({ "code" => TEXT, "kind" => TEXT, "library_id" => TEXT, "record_id" => TEXT,
                 "index" => { "type" => "integer", "minimum" => 0 } },
               :optional => %w[kind library_id record_id index])
      end

      def freshness
        object({ "loaded_at" => TEXT, "exported_at" => TEXT }, :optional => %w[loaded_at exported_at])
      end

      def failure
        schema = object({ "code" => TEXT, "message" => TEXT })
        schema.merge("type" => %w[object null])
      end

      def providers
        keys = %w[kind generation state failure age_seconds freshness]
        catalog = object(summary.fetch("properties").slice(*keys))
        connection = object({ "state" => { "type" => "string", "enum" => Connection::STATES }, "label" => TEXT })
        list(object({ "id" => TEXT, "provider_kind" => TEXT, "label" => TEXT,
                      "kinds" => list(TEXT), "catalogs" => list(catalog),
                      "connection" => described(connection, "A hosted library's connection; absent for others.") },
                    :optional => ["connection"]))
      end

      def resolution
        difference = object({ "field" => TEXT, "local" => VALUE, "incoming" => VALUE,
                              "local_present" => BOOLEAN, "incoming_present" => BOOLEAN })
        candidate = object({ "id" => TEXT,
                             "display_label" => { "type" => %w[string null],
                                                  "description" => "The local record's label; null when it has none." },
                             "differences" => list(difference),
                             "expected_values" => OBJECT, "comparison_available" => BOOLEAN,
                             "source_changed" => { "type" => %w[boolean null] } })
        outcomes = %w[create reuse review_required ambiguous_source ambiguous_name]
        object({ "outcome" => { "type" => "string", "enum" => outcomes },
                 "candidates" => list(candidate) })
      end

      def page(resolved: false)
        row = object({ "library_id" => TEXT, "library_name" => TEXT, "record_id" => TEXT,
                       "wire_schema_version" => { "type" => "integer", "minimum" => 1 }, "snapshot" => OBJECT,
                       "display_label" => described(TEXT, "The kind adapter's label for the row's mapped values.") })
        row["properties"]["resolution"] = resolution if resolved
        row["required"] << "resolution" if resolved
        object(summary.fetch("properties").merge("rows" => list(row),
                                                 "total" => Pages::TOTAL, "next_cursor" => Pages::NEXT_CURSOR),
               :optional => ["snapshot"])
      end

      def copy_result
        object({ "resolution" => resolution, "local_id" => NULLABLE_TEXT, "assigned" => BOOLEAN })
      end
    end
  end
end
