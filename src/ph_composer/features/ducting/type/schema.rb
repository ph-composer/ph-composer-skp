# frozen_string_literal: true

module PhComposer
  module Ducting
    DUCT_TYPE_KIND = "#{FEATURE_ID}.duct_type".freeze
    Fields = Records::AuthoringFields

    # The Duct Type: a Model-owned specification of one ventilation duct, the values honeybee-ph's duct segment takes
    # from it: its shape, the shape's dimensions and the insulation. A duct's direction and length are not on the
    # type. It names no Edge, group or run, so the rest of the feature depends on it and never the other way round.
    module DuctType
      KIND_ID = DUCT_TYPE_KIND
      # Each shape's dimensions, stored lower case and shown Round and Rectangular. A shape's dimensions are required
      # and the other shape's are absent, so no stored type lacks its size.
      SHAPE_FIELDS = { "round" => %w[diameter_mm], "rectangular" => %w[width_mm height_mm] }.freeze
      SHAPES = SHAPE_FIELDS.keys.freeze
      DIMENSIONS = SHAPE_FIELDS.values.flatten.freeze
      RAMP = %w[#4a7fb5 #b5634a #5f9a5a #8d6bb0 #c29a3a #4a9a9a].freeze

      def self.dimension(description)
        Fields.number("mm", :nullable => true).merge("description" => description)
      end

      FIELDS = Fields.with_source_snapshot(Fields.common + [
        Fields.field("shape", { "type" => "string", "enum" => SHAPES,
                                "description" => "The duct's cross-section: round or rectangular." },
                     :required => true),
        Fields.field("diameter_mm", dimension("The inside diameter. A round type needs it, 160 when a create " \
                                              "leaves it out; a rectangular one has none, and null removes it.")),
        Fields.field("width_mm", dimension("The inside width. A rectangular type needs it; a round one has none, " \
                                           "and null removes it.")),
        Fields.field("height_mm", dimension("The inside height. A rectangular type needs it; a round one has " \
                                            "none, and null removes it.")),
        Fields.field("insulation_thickness_mm", { "type" => "number", "minimum" => 0, "x-unit" => "mm",
                                                  "description" => "The insulation thickness; 0 for a bare duct." },
                     :required => true),
        # Null is a type still being entered, which blocks export only once a duct uses it.
        Fields.field("insulation_conductivity_w_mk", Fields.number("W/mK", :nullable => true)
                                                           .merge("description" => "The insulation's conductivity; " \
                                                                                   "absent while unknown, which " \
                                                                                   "blocks the export of an " \
                                                                                   "insulated type once a duct " \
                                                                                   "uses it.")),
        Fields.field("insulation_reflective", { "type" => "boolean",
                                                "description" => "Whether the insulation has a reflective " \
                                                                 "facing." },
                     :required => true),
        # Stored only once authored; a read shows the ramp colour for the id until then.
        Fields.field("color", SchemaShapes::HEX_COLOUR)
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
      # A new Duct Type: honeybee-ph's duct segment defaults, a 160 mm round duct with 25.4 mm of reflective
      # insulation at 0.04 W/(m K). A rectangular type has no default size.
      DEFAULTS = { "shape" => "round", "insulation_thickness_mm" => 25.4, "insulation_conductivity_w_mk" => 0.04,
                   "insulation_reflective" => true }.freeze
      ROUND_DEFAULTS = { "diameter_mm" => 160.0 }.freeze

      KIND = Records::RecordKind.new(
        :id => KIND_ID, :label => "Duct Type", :schema_version => 1, :id_prefix => "dct", :fields => FIELDS,
        :validate => lambda { |values|
          Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) +
            DuctType.shape_problems(values)
        }
      )

      module_function

      # A new type's values: `values` over the defaults, a round one 160 mm across unless it says otherwise. A null
      # given leaves a value absent, as a null on update removes it.
      def defaults(values)
        merged = DEFAULTS.merge(Fields.defaults(values))
        merged = ROUND_DEFAULTS.merge(merged) if merged["shape"] == "round"
        merged.compact
      end

      # An edit's values with the old shape's dimensions removed when it changes the shape, unless the edit names
      # them itself.
      def reshaped(before, values)
        shape = values["shape"]
        return values if shape.nil? || shape == before["shape"]

        dropped = SHAPE_FIELDS.fetch(before.fetch("shape"), []) - SHAPE_FIELDS.fetch(shape, [])
        dropped.to_h { |key| [key, nil] }.merge(values)
      end

      # Each of the shape's dimensions that is missing, and each other shape's dimension that is present.
      def shape_problems(values)
        own = SHAPE_FIELDS.fetch(values["shape"], nil)
        return [] unless own

        missing = own.reject { |key| values[key].is_a?(Numeric) }
        foreign = (DIMENSIONS - own).select { |key| values.key?(key) }
        found = missing.empty? ? [] : ["A #{values['shape']} Duct Type needs #{missing.join(', ')}."]
        found << "A #{values['shape']} Duct Type takes no #{foreign.join(', ')}." unless foreign.empty?
        found
      end

      # The colour a type draws in: its own, or the ramp's by id.
      def color(record)
        record["color"] || RAMP.fetch(record.fetch("id").each_byte.sum % RAMP.length)
      end

      # What keeps a type out of an export once a duct uses it: insulation with no conductivity. A bare duct needs
      # none.
      def export_blockers(record)
        insulated = record.fetch("insulation_thickness_mm").positive?
        insulated && record["insulation_conductivity_w_mk"].nil? ? [Codes::INSULATION_CONDUCTIVITY_MISSING] : []
      end
    end
  end
end
