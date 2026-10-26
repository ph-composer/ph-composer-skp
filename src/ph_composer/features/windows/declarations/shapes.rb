# frozen_string_literal: true

module PhComposer
  module Windows
    module Shapes
      extend SchemaShapes

      # Any string: names, messages, codes and ids in results. A param naming a record uses `id`.
      TEXT = { "type" => "string" }.freeze
      OBJECT = { "type" => "object" }.freeze
      NONE = object({}).freeze
      RESULT = object({ "id" => TEXT }).freeze
      TYPE_RESULT = object({ "id" => TEXT, "unit_count" => { "type" => "integer", "minimum" => 0 } }).freeze
      FINDING = object({ "code" => TEXT, "message" => TEXT, "element_id" => TEXT, "side" => TEXT,
                         "product_id" => TEXT }, :optional => %w[element_id side product_id]).freeze
      EXPECTED = "Any of the record's values as last read; if one changed since, the edit is refused as " \
                 "target.changed. {} skips the check."
      USER_DATA = { "type" => "object",
                    "description" => "Local JSON metadata kept with the record in the Model. Export needs an " \
                                     "explicit mapping; arbitrary metadata is left out with a finding." }.freeze
      FINDINGS = { "type" => "array", "items" => FINDING }.freeze

      # Every Windows action but the named repair first gives copied Units new identities.
      COPIED_IDENTITIES = "It first gives every copied Window Unit that still shares an identity a new one, in the " \
                          "same Undo step; #{FEATURE_ID}.units.repair_copied_identities does only that.".freeze

      module_function

      # An action's side effects, with the copied-identity repair every Windows action makes.
      def side_effects(text)
        "#{text} #{COPIED_IDENTITIES}"
      end

      def expected(kind)
        described(kind.descriptor.patch_schema, EXPECTED)
      end

      def create_values(kind)
        DeepCopy.call(kind.values_schema).merge("required" => ["name"])
      end

      def create(kind)
        object({ "values" => described(create_values(kind), "The new #{kind.label}'s values; name is required " \
                                                            "and every other value takes its default."),
                 "user_data" => USER_DATA }, :optional => ["user_data"])
      end

      def patch(kind)
        shape = kind.descriptor.patch_schema
        shape["properties"].delete("source")
        shape
      end

      def update(kind)
        object({ "id" => id(kind.id_prefix, "The #{kind.label} to edit."),
                 "values" => described(patch(kind), "The values to change; any not given stay."),
                 "expected_values" => expected(kind), "user_data" => USER_DATA }, :optional => ["user_data"])
      end

      def view(kind)
        with(kind.descriptor.view_schema, "kind" => TEXT, "extension_status" => OBJECT, "findings" => FINDINGS)
      end

      def list_params
        object({ "ids" => list(TEXT).merge("maxItems" => Pages::MAXIMUM_LIMIT,
                                           "description" => "Only these record ids; every record when absent."),
                 "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR }, :optional => %w[ids limit cursor])
      end
    end
  end
end
