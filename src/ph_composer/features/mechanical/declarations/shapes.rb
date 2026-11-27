# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The schemas every equipment family's declarations share. A family's own values come from its kind.
    module Shapes
      extend SchemaShapes

      TEXT = { "type" => "string" }.freeze
      NONE = object({}).freeze
      RESULT = object({ "id" => TEXT }).freeze
      EXPECTED = "Any of the record's values as last read; if one changed since, the edit is refused as " \
                 "target.changed. {} skips the check."
      USER_DATA = { "type" => "object",
                    "description" => "Local JSON metadata kept with the record in the Model. Export needs an " \
                                     "explicit mapping; arbitrary metadata is left out with a finding." }.freeze
      EXPORT_READY = described({ "type" => "boolean" }, "Whether the record can export once it serves something.")
      EXPORT_BLOCKERS = described(list(TEXT), "The codes keeping it out of an export; empty when export_ready.")

      module_function

      def example_id(kind)
        "#{kind.id_prefix}_Ab12Cd34Ef56"
      end

      def expected(kind)
        described(kind.descriptor.patch_schema, EXPECTED)
      end

      def create(kind)
        values = DeepCopy.call(kind.values_schema).merge("required" => ["name"])
        # A line type's assigned colour (Duct Types) is the next unused one, set by create itself.
        values["properties"].delete("assigned_color")
        object({ "values" => described(values, "The new #{kind.label}'s values; name is required and every " \
                                               "other value takes its default."),
                 "user_data" => USER_DATA }, :optional => ["user_data"])
      end

      # Provenance is set by create and duplicate, never by an edit.
      def update(kind)
        patch = kind.descriptor.patch_schema
        patch["properties"].delete("source")
        # A line type's assigned colour (Pipe and Duct Types) is set when it is made or copied, never by an edit.
        patch["properties"].delete("assigned_color")
        object({ "id" => id(kind.id_prefix, "The #{kind.label} to edit."),
                 "values" => described(patch, "The values to change; any not given stay. Null removes an optional " \
                                              "value."),
                 "expected_values" => expected(kind) })
      end

      def duplicate(kind)
        object({ "id" => id(kind.id_prefix, "The #{kind.label} to copy."),
                 "name" => { "type" => "string", "minLength" => 1,
                             "description" => "The copy's name. When absent, the first free of \"<name> (copy)\", " \
                                              "\"<name> (copy 2)\" and so on; read the result's id. Names are " \
                                              "unique." } },
               :optional => ["name"])
      end

      def delete(kind)
        object({ "id" => id(kind.id_prefix, "The #{kind.label} to delete."), "expected_values" => expected(kind) },
               :optional => ["expected_values"])
      end

      # A family's read row: the record's view, its extension payloads' status and its export readiness.
      def row(kind)
        with(kind.descriptor.view_schema, "kind" => TEXT, "extension_status" => { "type" => "object" },
                                          "export_ready" => EXPORT_READY, "export_blockers" => EXPORT_BLOCKERS)
      end
    end
  end
end
