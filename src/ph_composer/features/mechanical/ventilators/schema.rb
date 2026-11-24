# frozen_string_literal: true

module PhComposer
  module Mechanical
    FEATURE_ID = "ph_composer.mechanical"
    VENTILATOR_KIND = "#{FEATURE_ID}.ventilator"
    Fields = Records::AuthoringFields

    # The Ventilator: a Model-owned definition of one heat recovery ventilation unit, the values honeybee-ph's
    # Ventilator carries. It is a definition only: it names nothing it is used by, so the rest of the feature
    # depends on it and never the other way round. No system type (always balanced with heat recovery) and no
    # rated flow are stored.
    module Ventilators
      FRACTION = { "type" => "number", "minimum" => 0, "maximum" => 1, "x-unit" => "fraction" }.freeze

      FIELDS = Fields.with_source_snapshot(Fields.common + [
        Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when unknown." }),
        Fields.field("model",
                     { "type" => %w[string null], "description" => "The maker's model; absent when unknown." }),
        Fields.field("quantity", { "type" => "integer", "minimum" => 1,
                                   "description" => "How many identical units this record stands for." },
                     :required => true),
        Fields.field("sensible_heat_recovery", FRACTION.merge("description" => "Sensible heat recovery, 0 to 1."),
                     :required => true),
        Fields.field("latent_heat_recovery", FRACTION.merge("description" => "Latent heat recovery, 0 to 1."),
                     :required => true),
        Fields.field("electric_efficiency_wh_m3", { "type" => "number", "minimum" => 0, "x-unit" => "Wh/m3",
                                                    "description" => "Fan electricity per volume of air moved." },
                     :required => true),
        Fields.field("frost_protection_reqd", { "type" => "boolean", "description" => "Whether frost protection " \
                                                                                      "is required." },
                     :required => true),
        Fields.field("temperature_below_defrost_used_c", { "type" => "number", "x-unit" => "C",
                                                           "description" => "The outdoor temperature below which " \
                                                                            "defrost runs." },
                     :required => true),
        Fields.field("in_conditioned_space", { "type" => "boolean", "description" => "Whether the unit sits " \
                                                                                     "inside the thermal envelope." },
                     :required => true),
        Fields.field("subsoil_heat_exchange_efficiency", FRACTION.merge("type" => %w[number null],
                                                                        "description" => "A subsoil heat " \
                                                                                         "exchanger's efficiency, " \
                                                                                         "0 to 1; absent for none.")),
        Fields.field("preheated_intake_temperature_c", { "type" => %w[number null], "x-unit" => "C",
                                                         "description" => "The intake air temperature after a " \
                                                                          "preheater; absent for none." })
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
      # A new Ventilator's values, honeybee-ph's own defaults. The two optional fields stay absent.
      DEFAULTS = { "quantity" => 1, "sensible_heat_recovery" => 0.0, "latent_heat_recovery" => 0.0,
                   "electric_efficiency_wh_m3" => 0.55, "frost_protection_reqd" => true,
                   "temperature_below_defrost_used_c" => -5.0, "in_conditioned_space" => true }.freeze

      KIND = Records::RecordKind.new(
        :id => VENTILATOR_KIND, :label => "Ventilator", :schema_version => 1, :id_prefix => "vnt", :fields => FIELDS,
        :validate => ->(values) { Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) }
      )

      module_function

      def defaults(values)
        DEFAULTS.merge(Fields.defaults(values))
      end

      # What keeps a Ventilator out of an export. Every stored Ventilator is complete, so none; the row carries the
      # list so every equipment family reads alike.
      def export_blockers(_record)
        []
      end
    end
  end
end
