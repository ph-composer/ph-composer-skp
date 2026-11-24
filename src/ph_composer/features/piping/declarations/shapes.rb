# frozen_string_literal: true

module PhComposer
  module Piping
    # The schemas piping's declarations build from. A kind's own values come from the kind.
    module Shapes
      extend SchemaShapes

      TEXT = { "type" => "string" }.freeze
      OBJECT = { "type" => "object" }.freeze
      NONE = object({}).freeze
      RESULT = object({ "id" => TEXT }).freeze
      EXPECTED = "Any of the record's values as last read; if one changed since, the edit is refused as " \
                 "target.changed. {} skips the check."
      USER_DATA = { "type" => "object",
                    "description" => "Local JSON metadata kept with the record in the Model. No export writes a " \
                                     "Pipe Type's map." }.freeze

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
                 "values" => described(patch, "The values to change; any not given stay. Null removes an optional " \
                                              "value; a null color returns the type to its default colour."),
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

      def view(kind)
        with(kind.descriptor.view_schema, "kind" => TEXT, "extension_status" => OBJECT)
      end
    end
  end
end
