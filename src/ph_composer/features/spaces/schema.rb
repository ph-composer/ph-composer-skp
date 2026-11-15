# frozen_string_literal: true

module PhComposer
  # Spaces: the rooms of a Zone. A Space Group holds Volume Groups; a Volume holds the Faces the
  # user marked as Floor Segments. Each of the three stores its record on its own entity, so the
  # durable identity travels with the geometry (context/CONTRACTS.md, "Geometry records and occurrence
  # references"). A Space's Zone is the `zone_id` on its record, wherever its Group sits. The Space Floor
  # is logical: one per Volume, named by the Volume's `floor_id`, and its own `user_data` map is the
  # Volume's `floor_user_data`, which reads report as the Floor's and never as a Volume value.
  module Spaces
    FEATURE_ID = "ph_composer.spaces"
    ZONE_KIND = "ph_composer.zones.zone"
    SPACE_KIND = "#{FEATURE_ID}.space"
    VOLUME_KIND = "#{FEATURE_ID}.volume"
    FLOOR_SEGMENT_KIND = "#{FEATURE_ID}.floor_segment"
    SPACE_STORE = Records::EntityStore.new("ph_composer.space", :claims_entity => true)
    VOLUME_STORE = Records::EntityStore.new("ph_composer.space_volume", :claims_entity => true)
    FLOOR_SEGMENT_STORE = Records::EntityStore.new("ph_composer.floor_segment", :claims_entity => true)
    FLOOR_PREFIX = "flr"
    FLOOR_USER_DATA = "floor_user_data"
    AIRFLOWS = %w[v_sup_m3h v_eta_m3h v_tran_m3h].freeze
    DEFAULT_HEIGHT_M = 2.5

    PATH = { "type" => "array", "items" => { "type" => "integer" }, "minItems" => 1,
             "description" => "The root-to-entity persistent-id path." }.freeze

    # A record kind for validation only: the entity stores above persist it.
    module Schema
      module_function

      def field(key, schema, required: false)
        Records::Field.new(:key => key, :schema => schema, :required => required)
      end

      def factor(description)
        { "type" => "number", "minimum" => 0, "maximum" => 1, "description" => description }
      end

      def height(description)
        { "type" => "number", "exclusiveMinimum" => 0, "x-unit" => "m", "description" => description }
      end

      def airflow(description)
        { "type" => "number", "minimum" => 0, "x-unit" => "m3/h",
          "description" => "#{description} Absent is unset, distinct from 0." }
      end

      def kind(id, label, prefix, fields, validate: nil)
        Records::RecordKind.new(:id => id, :label => label, :schema_version => 1, :id_prefix => prefix,
                                :fields => fields, :validate => validate)
      end

      # The Space Floor's map is plain JSON, as every user_data map is (Records::RecordKind checks those).
      def floor_problems(values)
        JsonValue.problems(values.fetch(FLOOR_USER_DATA, {})).map { |problem| "#{FLOOR_USER_DATA} #{problem}" }
      end

      def reference(id_key)
        SchemaShapes.object({ id_key => { "type" => "string" }, "entity_path" => PATH })
      end
    end

    SPACE = Schema.kind(SPACE_KIND, "Space", "spc", [
      Schema.field("name", { "type" => "string" }, :required => true),
      Schema.field("number", { "type" => "string" }, :required => true),
      Schema.field("default_height_m", Schema.height("The height a new Volume takes."),
                   :required => true),
      Schema.field("next_volume_sequence", { "type" => "integer", "minimum" => 1 },
                   :required => true),
      Records::Reference.new(:key => "zone_id", :target_kind => ZONE_KIND, :cardinality => "one"),
      Schema.field("v_sup_m3h", Schema.airflow("Supply airflow.")),
      Schema.field("v_eta_m3h", Schema.airflow("Extract airflow.")),
      Schema.field("v_tran_m3h", Schema.airflow("Transfer airflow."))
    ])
    VOLUME = Schema.kind(VOLUME_KIND, "Volume", "vol", [
      Schema.field("number", { "type" => "integer", "minimum" => 1 }, :required => true),
      Schema.field("display_name", { "type" => "string" }, :required => true),
      Schema.field("avg_ceiling_height_m",
                   Schema.height("Average clear ceiling height; absent until entered.")),
      Schema.field("floor_id", SchemaShapes.id(FLOOR_PREFIX, "The logical Space Floor's id."),
                   :required => true),
      Schema.field("home_transform",
                   { "type" => "array", "items" => { "type" => "number" },
                     "minItems" => 16, "maxItems" => 16,
                     "description" => "The Volume's transform relative to its Space at " \
                                      "the last reconcile, for Restore position." }),
      Schema.field(FLOOR_USER_DATA, { "type" => "object",
                                      "description" => "The Space Floor's own user_data, written by its floor_id " \
                                                       "and read as the Floor's map." })
    ], :validate => ->(values) { Schema.floor_problems(values) })
    FLOOR_SEGMENT = Schema.kind(FLOOR_SEGMENT_KIND, "Floor Segment", "fsg", [
      Schema.field("display_name", { "type" => "string" }, :required => true),
      Schema.field("weighting_factor",
                   Schema.factor("The share of the area that counts toward the " \
                                 "weighted floor area (iCFA, or TFA)."),
                   :required => true),
      Schema.field("net_area_factor",
                   Schema.factor("The share of the area that counts toward net " \
                                 "volume."), :required => true)
    ])
    KINDS = { SPACE_KIND => SPACE, VOLUME_KIND => VOLUME, FLOOR_SEGMENT_KIND => FLOOR_SEGMENT }.freeze

    # The most Faces one Mark floor gesture may mark, as the Face schema bounds a Classify gesture: a drag
    # across a large plan refuses rather than writing hundreds of records in one step.
    FLOOR_GESTURE_LIMIT = 250

    class << self
      # The shipped bound is always FLOOR_GESTURE_LIMIT; the writer lets a test reach the ceiling without a
      # large model, and the reset puts it back. Nothing in the extension sets it.
      attr_writer :floor_gesture_limit

      def floor_gesture_limit
        @floor_gesture_limit ||= FLOOR_GESTURE_LIMIT
      end
    end
    PhComposer.on_reset("spaces.floor_gesture_limit") { Spaces.floor_gesture_limit = nil }

    SPACE_REFERENCE = Schema.reference("space_id")
    VOLUME_REFERENCE = Schema.reference("volume_id")
    FLOOR_SEGMENT_REFERENCE = Schema.reference("floor_segment_id")
    # A Space Floor: its Volume's `floor_id` and the Volume's path. It names the Floor's metadata only.
    FLOOR_REFERENCE = Schema.reference("floor_id")

    module_function

    def validate!(kind, record)
      found = kind.problems(record)
      return record if found.empty?

      raise CodedError.new("validation.failed", "The #{kind.label} record is invalid: #{found.first}.",
                           "findings" => found)
    end

    # A Volume's stored values without its Space Floor's map, as every read reports them.
    def values_schema(kind)
      schema = kind.values_schema
      schema.fetch("properties").delete(FLOOR_USER_DATA)
      schema
    end

    def view(record)
      {
        "id" => record.fetch("id"), "schema_version" => record.fetch("schema_version"),
        "values" => record.reject do |key, _value|
          Records::RecordKind::RESERVED_KEYS.include?(key) || key == FLOOR_USER_DATA
        end,
        "user_data" => DeepCopy.call(record.fetch("user_data", {})),
        "extension_data" => DeepCopy.call(record.fetch("extension_data", {}))
      }
    end

    # The logical Space Floor of the Volume `record` at `path`: the reference its metadata is written by, and
    # its own map, absent as {}.
    def floor(record, path)
      { "reference" => { "floor_id" => record.fetch("floor_id"), "entity_path" => path },
        "user_data" => DeepCopy.call(record.fetch(FLOOR_USER_DATA, {})) }
    end
  end
end
