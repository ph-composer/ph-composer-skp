# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    module Shapes
      extend SchemaShapes

      # Any string: names, messages, codes and ids in results. A param naming a record uses `id`.
      TEXT = { "type" => "string" }.freeze
      OBJECT = { "type" => "object" }.freeze
      NONE = object({}).freeze
      RESULT = object({ "id" => TEXT }).freeze
      EXPECTED = "Any of the record's values as last read; if one changed since, the edit is refused as " \
                 "target.changed. {} skips the check."
      USER_DATA = { "type" => "object",
                    "description" => "Local JSON metadata kept with the record in the Model. Export needs an " \
                                     "explicit mapping; arbitrary metadata is left out with a finding." }.freeze

      module_function

      def example_id(kind)
        "#{kind.id_prefix}_Ab12Cd34Ef56"
      end

      def expected(kind)
        described(kind.descriptor.patch_schema, EXPECTED)
      end

      def create(kind)
        values = DeepCopy.call(kind.values_schema).merge("required" => ["name"])
        object({ "values" => described(values, "The new #{kind.label}'s values; name is required and every " \
                                               "other value takes its default."),
                 "user_data" => USER_DATA }, :optional => ["user_data"])
      end

      # Provenance is set by create and duplicate, never by an edit.
      def update(kind)
        patch = kind.descriptor.patch_schema
        patch["properties"].delete("source")
        object({ "id" => id(kind.id_prefix, "The #{kind.label} to edit."),
                 "values" => described(patch, "The values to change; any not given stay. A null color returns " \
                                              "the type to its default colour."),
                 "expected_values" => expected(kind), "user_data" => USER_DATA }, :optional => ["user_data"])
      end

      def view(kind)
        with(kind.descriptor.view_schema, "kind" => TEXT, "extension_status" => OBJECT)
      end
    end
  end
end
