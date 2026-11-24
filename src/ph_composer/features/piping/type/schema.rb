# frozen_string_literal: true

module PhComposer
  module Piping
    PIPE_TYPE_KIND = "#{FEATURE_ID}.pipe_type".freeze
    Fields = Records::AuthoringFields

    # The Pipe Type: a Model-owned specification of one hot water pipe, the values honeybee-ph's pipe segment takes
    # from it: material, diameter and insulation. A pipe's role, temperature and hours are not on the type. It names
    # no Edge, group or run, so the rest of the feature depends on it and never the other way round.
    module PipeType
      KIND_ID = PIPE_TYPE_KIND
      # honeybee-ph's material numbers and their words (context/UBIQUITOUS_LANGUAGE.md, "Pipe Type").
      MATERIALS = { 1 => "Copper M", 2 => "Copper L", 3 => "Copper K", 4 => "CPVC CTS SDR", 5 => "CPVC Sch 40",
                    6 => "PEX", 7 => "PE", 8 => "PEX CTS SDR" }.freeze
      # The eight nominal sizes METr takes, in millimetres: each the inch size times 25.4, written as the decimal it
      # is, which PHX maps back to its inch size exactly. A value must equal one of these literals. Labelled by the
      # inch size in both unit systems.
      DIAMETERS_MM = { 9.525 => "3/8 in", 12.7 => "1/2 in", 15.875 => "5/8 in", 19.05 => "3/4 in", 25.4 => "1 in",
                       31.75 => "1 1/4 in", 38.1 => "1 1/2 in", 50.8 => "2 in" }.freeze
      INSULATION_QUALITIES = { 1 => "None", 2 => "Moderate", 3 => "Good" }.freeze
      RAMP = %w[#3b7ea1 #c26a2e #6b8f3a #9b5fa8 #c9a227 #4f9b94].freeze

      def self.listed(words)
        words.map { |key, word| "#{key} #{word}" }.join(", ")
      end

      FIELDS = Fields.with_source_snapshot(Fields.common + [
        Fields.field("material", { "type" => "integer", "minimum" => 1, "maximum" => MATERIALS.length,
                                   "description" => "The pipe material: #{listed(MATERIALS)}." },
                     :required => true),
        Fields.field("diameter_mm", { "type" => "number", "enum" => DIAMETERS_MM.keys, "x-unit" => "mm",
                                      "description" => "The nominal diameter, one of eight sizes: " \
                                                       "#{DIAMETERS_MM.map { |mm, size| "#{mm} (#{size})" }
                                                                      .join(', ')}." },
                     :required => true),
        Fields.field("insulation_thickness_mm", { "type" => "number", "minimum" => 0, "x-unit" => "mm",
                                                  "description" => "The insulation thickness; 0 for a bare pipe." },
                     :required => true),
        # Null is a type still being entered, which blocks export only once a pipe uses it.
        Fields.field("insulation_conductivity_w_mk", { "type" => %w[number null], "exclusiveMinimum" => 0,
                                                       "x-unit" => "W/mK",
                                                       "description" => "The insulation's conductivity; absent " \
                                                                        "while unknown, which blocks the export " \
                                                                        "of an insulated type once a pipe uses " \
                                                                        "it." }),
        Fields.field("insulation_reflective", { "type" => "boolean",
                                                "description" => "Whether the insulation has a reflective " \
                                                                 "facing." },
                     :required => true),
        Fields.field("insulation_quality", { "type" => "integer", "minimum" => 1,
                                             "maximum" => INSULATION_QUALITIES.length,
                                             "description" => "The quality of the insulation's installation: " \
                                                              "#{listed(INSULATION_QUALITIES)}." },
                     :required => true),
        # Stored only once authored; a read shows the ramp colour for the id until then.
        Fields.field("color", SchemaShapes::HEX_COLOUR)
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
      # A new Pipe Type: honeybee-ph's pipe segment defaults, a 1/2 in Copper L pipe with 12.7 mm of reflective
      # insulation at 0.04 W/(m K), installed with no particular quality.
      DEFAULTS = { "material" => 2, "diameter_mm" => 12.7, "insulation_thickness_mm" => 12.7,
                   "insulation_conductivity_w_mk" => 0.04, "insulation_reflective" => true,
                   "insulation_quality" => 1 }.freeze

      KIND = Records::RecordKind.new(
        :id => KIND_ID, :label => "Pipe Type", :schema_version => 1, :id_prefix => "ppt", :fields => FIELDS,
        :validate => ->(values) { Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) }
      )

      module_function

      # A null given on create leaves an optional value absent, as a null on update removes it.
      def defaults(values)
        DEFAULTS.merge(Fields.defaults(values)).compact
      end

      # The colour a type draws in: its own, or the ramp's by id.
      def color(record)
        record["color"] || RAMP.fetch(record.fetch("id").each_byte.sum % RAMP.length)
      end

      # What keeps a type out of an export once a pipe uses it: insulation with no conductivity. A bare pipe needs
      # none.
      def export_blockers(record)
        insulated = record.fetch("insulation_thickness_mm").positive?
        insulated && record["insulation_conductivity_w_mk"].nil? ? [Codes::INSULATION_CONDUCTIVITY_MISSING] : []
      end
    end
  end
end
