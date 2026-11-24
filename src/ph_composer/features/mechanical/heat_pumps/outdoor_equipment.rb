# frozen_string_literal: true

module PhComposer
  module Mechanical
    HP_OUTDOOR_EQUIPMENT_KIND = "#{FEATURE_ID}.hp_outdoor_equipment".freeze
    HP_INDOOR_EQUIPMENT_KIND = "#{FEATURE_ID}.hp_indoor_equipment".freeze

    # Heat pumps are four flat catalogs: the outdoor and indoor equipment models, and the outdoor and indoor units
    # installed from them. Only an outdoor model carries performance, the Phius Heat Pump
    # Performance Estimator's inputs; an indoor model is identity only. Each kind is a definition and names nothing
    # it is used by.
    module HeatPumps
      # An outdoor model (a compressor or condensing unit): the estimator's inputs for one device type. Capacities
      # are kW at the estimator's rating points, 17 F and 47 F for heating and 95 F for cooling. The heating rating
      # is a COP pair or an HSPF (HSPF2 when `hspf_version` says so); the cooling rating, when the model cools, is
      # an EER and SEER pair (EER2 and SEER2 when `seer_version` says so) or an IEER. Each mode reads only its own
      # values; the others may stay stored, so switching back restores them. A model may name the one indoor model
      # its ratings were measured with.
      #
      # A value the blend needs and the record lacks keeps the model out of the blend with a finding
      # (`missing_inputs`), so a new model can be created from its Tag alone and filled in on its row.
      module OutdoorEquipment
        KIND_ID = HP_OUTDOOR_EQUIPMENT_KIND
        HEATING_MODES = %w[cop_pair hspf].freeze
        COOLING_MODES = %w[eer_seer ieer].freeze
        HSPF_VERSIONS = %w[hspf hspf2].freeze
        SEER_VERSIONS = %w[seer seer2].freeze
        CAPACITY = { "type" => %w[number null], "minimum" => 0, "x-unit" => "kW" }.freeze
        RATING = { "type" => %w[number null], "exclusiveMinimum" => 0 }.freeze
        # What each heating and cooling mode reads; heating capacities are read in every mode.
        HEATING_INPUTS = { "cop_pair" => %w[cop_17f cop_47f], "hspf" => %w[hspf_value] }.freeze
        COOLING_INPUTS = { "eer_seer" => %w[eer seer], "ieer" => %w[ieer] }.freeze
        LABELS = {
          "heating_cap_17f_kw" => "heating capacity at 17 F", "heating_cap_47f_kw" => "heating capacity at 47 F",
          "cop_17f" => "COP at 17 F", "cop_47f" => "COP at 47 F", "hspf_value" => "HSPF",
          "cooling_cap_95f_kw" => "cooling capacity at 95 F", "eer" => "EER", "seer" => "SEER", "ieer" => "IEER"
        }.freeze
        INDOOR_REFERENCE = Records::Reference.new(:key => "paired_indoor_equipment_id",
                                                  :target_kind => HP_INDOOR_EQUIPMENT_KIND, :cardinality => "one")
        FIELDS = Fields.with_source_snapshot(Fields.common + [
          Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when " \
                                                                                     "unknown." }),
          Fields.field("model", { "type" => %w[string null], "description" => "The maker's model; absent when " \
                                                                              "unknown." }),
          INDOOR_REFERENCE,
          Fields.field("heating_cap_17f_kw", CAPACITY.merge("description" => "Heating capacity at 17 F (-8.3 C).")),
          Fields.field("heating_cap_47f_kw", CAPACITY.merge("description" => "Heating capacity at 47 F (8.3 C).")),
          Fields.field("heating_rating_mode", { "type" => "string", "enum" => HEATING_MODES,
                                                "description" => "How heating is rated: cop_pair (COP at 17 F " \
                                                                 "and 47 F) or hspf." }, :required => true),
          Fields.field("cop_17f", RATING.merge("description" => "COP at 17 F, read when cop_pair.")),
          Fields.field("cop_47f", RATING.merge("description" => "COP at 47 F, read when cop_pair.")),
          Fields.field("hspf_value", RATING.merge("description" => "The HSPF rating, read when hspf.")),
          Fields.field("hspf_version", { "type" => "string", "enum" => HSPF_VERSIONS,
                                         "description" => "Whether hspf_value is an HSPF or an HSPF2 rating." },
                       :required => true),
          Fields.field("cooling_cap_95f_kw", CAPACITY.merge("description" => "Cooling capacity at 95 F (35 C); " \
                                                                             "absent for a heating-only model.")),
          Fields.field("cooling_rating_mode", { "type" => %w[string null], "enum" => COOLING_MODES + [nil],
                                                "description" => "How cooling is rated: eer_seer, ieer, or null " \
                                                                 "for a heating-only model." }),
          Fields.field("eer", RATING.merge("description" => "The EER rating, read when eer_seer.")),
          Fields.field("seer", RATING.merge("description" => "The SEER rating, read when eer_seer.")),
          Fields.field("seer_version", { "type" => "string", "enum" => SEER_VERSIONS,
                                         "description" => "Whether eer and seer are EER and SEER or EER2 and " \
                                                          "SEER2 ratings." }, :required => true),
          Fields.field("ieer", RATING.merge("description" => "The IEER rating, read when ieer."))
        ])
        SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
        # honeybee-ph's rated monthly heat pump defaults, COP 2.5 at 17 F and 47 F, and current ratings' versions.
        DEFAULTS = { "heating_rating_mode" => "cop_pair", "cop_17f" => 2.5, "cop_47f" => 2.5,
                     "hspf_version" => "hspf2", "seer_version" => "seer2" }.freeze

        KIND = Records::RecordKind.new(
          :id => KIND_ID, :label => "Heat Pump Outdoor Equipment", :schema_version => 1, :id_prefix => "hpo",
          :fields => FIELDS,
          :validate => lambda { |values|
            Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA)
          }
        )

        module_function

        def defaults(values)
          DEFAULTS.merge(Fields.defaults(values))
        end

        # The values the blend needs that `record` lacks, by their labels: both heating capacities, its heating
        # mode's ratings and, when it cools, the cooling capacity and its cooling mode's ratings.
        def missing_inputs(record)
          needed = %w[heating_cap_17f_kw heating_cap_47f_kw] + HEATING_INPUTS.fetch(record["heating_rating_mode"], [])
          cooling = record["cooling_rating_mode"]
          needed += ["cooling_cap_95f_kw"] + COOLING_INPUTS.fetch(cooling, []) if cooling
          missing = needed.reject { |key| record[key].is_a?(Numeric) }
          missing += %w[heating_cap_17f_kw heating_cap_47f_kw].select { |key| record[key]&.zero? }
          missing.uniq.map { |key| LABELS.fetch(key) }
        end
      end

      # An indoor model (a head, cassette or air handler): identity only. The estimator takes outdoor units' ratings
      # and leaves indoor units out, so nothing here exports.
      module IndoorEquipment
        KIND_ID = HP_INDOOR_EQUIPMENT_KIND
        FIELDS = Fields.with_source_snapshot(Fields.common + [
          Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when " \
                                                                                     "unknown." }),
          Fields.field("model", { "type" => %w[string null], "description" => "The maker's model; absent when " \
                                                                              "unknown." })
        ])
        SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)

        KIND = Records::RecordKind.new(
          :id => KIND_ID, :label => "Heat Pump Indoor Equipment", :schema_version => 1, :id_prefix => "hpi",
          :fields => FIELDS,
          :validate => lambda { |values|
            Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA)
          }
        )

        module_function

        def defaults(values)
          Fields.defaults(values)
        end
      end
    end
  end
end
