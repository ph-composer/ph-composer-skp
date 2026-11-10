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
      # The compact form (`compact`) counts the notes in `warning_total` and `unavailable_total` in place of
      # listing them; `warnings.list` and `unavailable.list` page them.
      def summary
        object({ "provider_id" => TEXT, "kind" => TEXT, "generation" => GENERATION,
                 "state" => { "type" => "string", "enum" => STATES },
                 "warnings" => list(note), "unavailable" => list(note), "freshness" => freshness,
                 "published_at" => NULLABLE_TEXT, "failure" => failure, "age_seconds" => NULLABLE_NUMBER,
                 "snapshot" => snapshot, "warning_total" => COUNT, "unavailable_total" => COUNT },
               :optional => %w[snapshot warnings unavailable warning_total unavailable_total])
      end

      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      # The fields a compact row or candidate cut at OccurrencePath::NAME_CHARACTERS.
      TRUNCATED = { "type" => "array", "items" => TEXT,
                    "description" => "Fields cut to 256 characters; the detail read gives them whole." }.freeze

      STATES = %w[unloaded empty loaded failed loading ready stale unavailable cancelled].freeze

      def snapshot
        object({ "id" => TEXT, "library_revision" => { "type" => "integer", "minimum" => 0 },
                 "projection_schema_version" => { "type" => "integer", "minimum" => 1 } })
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
        # A compact candidate gives `difference_fields` and `expected_values_summary` in place of `differences`
        # and `expected_values`, which in_file.detail reads whole.
        candidate = object({ "id" => TEXT,
                             "display_label" => { "type" => %w[string null],
                                                  "description" => "The local record's label; null when it has none." },
                             "differences" => list(difference),
                             "expected_values" => OBJECT, "comparison_available" => BOOLEAN,
                             "source_changed" => { "type" => %w[boolean null] },
                             "difference_fields" => list(TEXT), "expected_values_summary" => Fragments::SUMMARY,
                             "truncated" => TRUNCATED },
                           :optional => %w[differences expected_values difference_fields expected_values_summary
                                           truncated])
        outcomes = %w[create reuse review_required ambiguous_source ambiguous_name]
        total = { "type" => "integer", "minimum" => 0,
                  "description" => "Compact only: every candidate; candidates lists the first ones, at most 20, " \
                                   "that fit 8 KiB." }
        object({ "outcome" => { "type" => "string", "enum" => outcomes },
                 "candidates" => list(candidate), "candidate_total" => total }, :optional => ["candidate_total"])
      end

      def page(resolved: false)
        # A compact row gives `snapshot_summary` in place of `snapshot`, which catalog.detail reads whole.
        row = object({ "library_id" => TEXT, "library_name" => TEXT, "record_id" => TEXT,
                       "wire_schema_version" => { "type" => "integer", "minimum" => 1 }, "snapshot" => OBJECT,
                       "display_label" => described(TEXT, "The kind adapter's label for the row's mapped values."),
                       "snapshot_summary" => Fragments::SUMMARY, "truncated" => TRUNCATED },
                     :optional => %w[snapshot snapshot_summary truncated])
        row["properties"]["resolution"] = resolution if resolved
        row["required"] << "resolution" if resolved
        object(summary.fetch("properties").merge("rows" => list(row),
                                                 "total" => Pages::TOTAL, "next_cursor" => Pages::NEXT_CURSOR),
               :optional => summary.fetch("properties").keys - summary.fetch("required"))
      end

      # One page of a catalog's warnings or unavailable notes (`key` names which).
      def notes_page(key)
        object({ "provider_id" => TEXT, "kind" => TEXT, "generation" => GENERATION, key => list(note),
                 "total" => Pages::TOTAL, "next_cursor" => Pages::NEXT_CURSOR })
      end

      def detail
        object({ "generation" => GENERATION, "type" => Fragments::TYPE, "fragment" => Fragments::FRAGMENT,
                 "next_cursor" => Pages::NEXT_CURSOR })
      end

      def copy_result
        object({ "resolution" => resolution, "local_id" => NULLABLE_TEXT, "assigned" => BOOLEAN })
      end
    end
  end
end
