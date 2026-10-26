# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    FEATURE_ID = "ph_composer.thermal_bridges"
    TYPE_KIND = "#{FEATURE_ID}.type"
    Fields = Records::AuthoringFields

    # The Thermal Bridge Type: a Model-owned definition holding one linear psi-value. It names no Edge,
    # Zone or run, so the rest of the feature depends on it and never the other way round.
    module Type
      # honeybee-ph's group strings, stored as written; the panel shows them in METr's words.
      GROUPS = %w[15-Ambient 16-Perimeter 17-FS/BC].freeze
      DEFAULT_GROUP = "15-Ambient"
      RAMP = %w[#d9a23b #c8553d #6a8eae #8a6fb0 #5b9a68 #b5677d].freeze

      FIELDS = Fields.with_source_snapshot(Fields.common + [
        # Signed and nullable: a negative psi-value is common with exterior dimensions, and null is a
        # type still being entered, which blocks export only once an Edge uses it.
        Fields.field("psi_w_mk", { "type" => %w[number null], "x-unit" => "W/mK" }),
        Fields.field("group", { "type" => "string", "enum" => GROUPS }, :required => true),
        # Stored only once authored; a read shows the ramp colour for the id until then.
        Fields.field("color", SchemaShapes::HEX_COLOUR)
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)

      KIND = Records::RecordKind.new(
        :id => TYPE_KIND, :label => "Thermal Bridge Type", :schema_version => 1, :id_prefix => "tbt",
        :fields => FIELDS,
        :validate => ->(values) { Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) }
      )

      module_function

      def defaults(values)
        { "psi_w_mk" => nil, "group" => DEFAULT_GROUP }.merge(Fields.defaults(values))
      end

      # The colour a type draws in: its own, or the ramp's by id.
      def color(record)
        record["color"] || RAMP.fetch(record.fetch("id").each_byte.sum % RAMP.length)
      end

      # What keeps a type out of an export once an Edge uses it.
      def export_blockers(record)
        record["psi_w_mk"].nil? ? ["thermal_bridge.psi_missing"] : []
      end
    end
  end
end
