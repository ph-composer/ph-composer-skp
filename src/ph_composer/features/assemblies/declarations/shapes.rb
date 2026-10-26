# frozen_string_literal: true

module PhComposer
  module Assemblies
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
      EXAMPLE_ID = "asm_Ab12Cd34Ef56"
      EXAMPLE_LAYER = "lyr_Ab12Cd34Ef56"
      EXAMPLE_SEGMENT = "seg_Ab12Cd34Ef56"
      FINDING = object({
        "code" => TEXT, "message" => TEXT,
        "message_parts" => { "type" => "array", "items" => OBJECT },
        "assembly_id" => TEXT, "material_id" => TEXT, "layer_id" => TEXT, "segment_id" => TEXT,
        "missing_fields" => { "type" => "array", "items" => TEXT }
      }, :optional => %w[assembly_id material_id layer_id segment_id missing_fields]).freeze
      FINDINGS = { "type" => "array", "items" => FINDING }.freeze

      module_function

      def expected(kind)
        described(kind.descriptor.patch_schema, EXPECTED)
      end

      def view(kind)
        with(kind.descriptor.view_schema, "kind" => TEXT, "extension_status" => OBJECT, "findings" => FINDINGS)
      end

      # `labelled` names fields whose param also takes a display label the command resolves, so their
      # param schema drops the stored enum.
      def without_enums(schema, labelled)
        labelled.each { |key| schema.fetch("properties").fetch(key).delete("enum") }
        schema
      end

      def editable_patch(kind, fields, labelled: [])
        schema = kind.descriptor.patch_schema
        schema["properties"] = schema.fetch("properties").select { |key, _value| fields.include?(key) }
        without_enums(schema, labelled)
      end

      def create(kind, labelled: [])
        values = without_enums(DeepCopy.call(kind.values_schema).merge("required" => ["name"]), labelled)
        object({ "values" => described(values, "The new #{kind.label}'s values; name is required and every " \
                                               "other value takes its default."),
                 "user_data" => USER_DATA }, :optional => ["user_data"])
      end

      def update(kind, fields, labelled: [])
        object({ "id" => id(kind.id_prefix, "The #{kind.label} to edit."),
                 "values" => described(editable_patch(kind, fields, :labelled => labelled),
                                       "The values to change; any not given stay."),
                 "expected_values" => expected(kind), "user_data" => USER_DATA }, :optional => ["user_data"])
      end
    end
  end
end
