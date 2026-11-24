# frozen_string_literal: true

module PhComposer
  module Mechanical
    HOT_WATER_HEATER_KIND = "#{FEATURE_ID}.hot_water_heater".freeze

    module HotWater
      # A Hot Water Heater: one of honeybee-ph's heater classes, chosen by `variant`, on the System it names. Its
      # variant picks which efficiency values it stores: an annual heat pump its total system performance ratio, a
      # monthly one its two COPs at two ambient temperatures, one inside the envelope its annual energy factor, and
      # an electric heater none. A variant's values are required and every other variant's are absent, so changing
      # the variant gives the new values and nulls the old in the same edit.
      module Heaters
        KIND_ID = HOT_WATER_HEATER_KIND
        POSITIVE = { "type" => %w[number null], "exclusiveMinimum" => 0 }.freeze
        TEMPERATURE = { "type" => %w[number null], "x-unit" => "C" }.freeze
        # Each variant's efficiency values, in the order honeybee-ph's class declares them.
        VARIANT_FIELDS = {
          "electric" => [],
          "heat_pump_annual" => %w[total_system_perf_ratio],
          "heat_pump_monthly" => %w[cop_1 ambient_temp_1_c cop_2 ambient_temp_2_c],
          "heat_pump_inside" => %w[annual_energy_factor]
        }.freeze
        VARIANTS = VARIANT_FIELDS.keys.freeze
        EFFICIENCY_FIELDS = VARIANT_FIELDS.values.flatten.freeze
        # honeybee-ph's own defaults for a monthly heat pump: COP 2.5 at 17 F and at 47 F. The annual and inside
        # kinds have none, so a new one gives its value.
        MONTHLY_DEFAULTS = { "cop_1" => 2.5, "ambient_temp_1_c" => -8.333, "cop_2" => 2.5,
                             "ambient_temp_2_c" => 8.333 }.freeze
        SYSTEM_REFERENCE = Records::Reference.new(:key => "hot_water_system_id", :target_kind => HOT_WATER_SYSTEM_KIND,
                                                  :cardinality => "one", :required => true)
        FIELDS = Fields.with_source_snapshot(Fields.common + [
          Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when " \
                                                                                     "unknown." }),
          Fields.field("model", { "type" => %w[string null], "description" => "The maker's model; absent when " \
                                                                              "unknown." }),
          SYSTEM_REFERENCE,
          Fields.field("variant", { "type" => "string", "enum" => VARIANTS,
                                    "description" => "The kind of heater, which picks its efficiency values: " \
                                                     "#{VARIANTS.join(', ')}." }, :required => true),
          Fields.field("percent_coverage", { "type" => "number", "minimum" => 0, "maximum" => 1, "x-unit" => "fraction",
                                             "description" => "The share of the System's hot water this heater " \
                                                              "makes, 0 to 1." }, :required => true),
          Fields.field("in_conditioned_space", { "type" => "boolean", "description" => "Whether the heater sits " \
                                                                                       "inside the thermal " \
                                                                                       "envelope." },
                       :required => true),
          Fields.field("total_system_perf_ratio", POSITIVE.merge("description" => "An annual heat pump's total " \
                                                                                  "system performance ratio.")),
          Fields.field("cop_1", POSITIVE.merge("description" => "A monthly heat pump's COP at ambient_temp_1_c.")),
          Fields.field("ambient_temp_1_c", TEMPERATURE.merge("description" => "A monthly heat pump's first rating " \
                                                                              "temperature.")),
          Fields.field("cop_2", POSITIVE.merge("description" => "A monthly heat pump's COP at ambient_temp_2_c.")),
          Fields.field("ambient_temp_2_c", TEMPERATURE.merge("description" => "A monthly heat pump's second rating " \
                                                                              "temperature.")),
          Fields.field("annual_energy_factor", POSITIVE.merge("description" => "An inside heat pump's annual energy " \
                                                                               "factor."))
        ])
        SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
        DEFAULTS = { "variant" => "electric", "percent_coverage" => 1.0, "in_conditioned_space" => true }.freeze

        KIND = Records::RecordKind.new(
          :id => KIND_ID, :label => "Hot Water Heater", :schema_version => 1, :id_prefix => "hwh", :fields => FIELDS,
          :validate => lambda { |values|
            Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) +
              Heaters.variant_problems(values)
          }
        )

        module_function

        # A new Heater's values over the defaults; a monthly heat pump takes honeybee-ph's COPs where none is given.
        def defaults(values)
          merged = DEFAULTS.merge(Fields.defaults(values))
          merged["variant"] == "heat_pump_monthly" ? MONTHLY_DEFAULTS.merge(merged) : merged
        end

        # Each of the variant's values that is missing, and each other variant's value that is present.
        def variant_problems(values)
          variant = values["variant"]
          return [] unless VARIANT_FIELDS.key?(variant)

          own = VARIANT_FIELDS.fetch(variant)
          missing = own.reject { |key| values[key].is_a?(Numeric) }
          foreign = (EFFICIENCY_FIELDS - own).select { |key| values.key?(key) }
          found = missing.empty? ? [] : ["A #{variant} heater needs #{missing.join(', ')}."]
          found << "A #{variant} heater takes no #{foreign.join(', ')}." unless foreign.empty?
          found
        end
      end
    end
  end
end
