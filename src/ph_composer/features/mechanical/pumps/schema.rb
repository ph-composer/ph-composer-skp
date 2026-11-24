# frozen_string_literal: true

module PhComposer
  module Mechanical
    PUMP_KIND = "#{FEATURE_ID}.pump"

    # The Pump: a Model-owned definition of one auxiliary pump, the values honeybee-ph's PhSupportiveDevice carries.
    # Its type is one of the four supportive device types; its internal heat gain lands in the usage profile the type
    # gives unless the record names another. It is a definition only: it names nothing it is used by.
    module Pumps
      KIND_ID = PUMP_KIND
      # honeybee-ph's supportive device types a Pump offers: heating circulation, hot water circulation, hot water
      # storage load and other.
      DEVICE_TYPES = [4, 6, 7, 10].freeze
      # The usage profile each type gives, honeybee-ph's `default_ihg_usage_profile`: 1 all year, 2 winter, 3 summer,
      # 4 none (the gain is booked in hot water distribution).
      DEFAULT_IHG_USAGE_PROFILE = { 4 => 2, 6 => 4, 7 => 4, 10 => 1 }.freeze
      FIELDS = Fields.with_source_snapshot(Fields.common + [
        Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when unknown." }),
        Fields.field("model",
                     { "type" => %w[string null], "description" => "The maker's model; absent when unknown." }),
        Fields.field("device_type", { "type" => "integer", "enum" => DEVICE_TYPES,
                                      "description" => "The supportive device type: 4 heating circulation, 6 hot " \
                                                       "water circulation, 7 hot water storage load, 10 other." },
                     :required => true),
        Fields.field("quantity", { "type" => "integer", "minimum" => 1,
                                   "description" => "How many identical pumps this record stands for." },
                     :required => true),
        Fields.field("in_conditioned_space", { "type" => "boolean", "description" => "Whether the pump sits " \
                                                                                     "inside the thermal envelope." },
                     :required => true),
        Fields.field("norm_energy_demand_w", { "type" => "number", "minimum" => 0, "x-unit" => "W",
                                               "description" => "Electrical power while it runs." },
                     :required => true),
        Fields.field("annual_period_operation_khrs", { "type" => "number", "minimum" => 0, "x-unit" => "kh",
                                                       "description" => "Thousands of hours it runs a year; 8.76 " \
                                                                        "is the whole year." },
                     :required => true),
        Fields.field("ihg_utilization_factor", { "type" => "number", "minimum" => 0, "maximum" => 1,
                                                 "x-unit" => "fraction",
                                                 "description" => "The share of its energy that becomes an " \
                                                                  "internal heat gain, 0 to 1." },
                     :required => true),
        Fields.field("ihg_usage_profile", { "type" => %w[integer null], "minimum" => 1, "maximum" => 4,
                                            "description" => "Where its internal heat gain lands: 1 all year, 2 " \
                                                             "winter, 3 summer, 4 none; absent to follow the device " \
                                                             "type." })
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
      # A new Pump: a hot water circulation pump running all year, inside the envelope, whose energy all becomes a
      # gain in the profile its type gives. It draws no power until one is entered (the Grasshopper component's
      # default).
      DEFAULTS = { "device_type" => 6, "quantity" => 1, "in_conditioned_space" => true,
                   "norm_energy_demand_w" => 0.0, "annual_period_operation_khrs" => 8.76,
                   "ihg_utilization_factor" => 1.0 }.freeze

      KIND = Records::RecordKind.new(
        :id => KIND_ID, :label => "Pump", :schema_version => 1, :id_prefix => "pmp", :fields => FIELDS,
        :validate => ->(values) { Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) }
      )

      module_function

      def defaults(values)
        DEFAULTS.merge(Fields.defaults(values))
      end

      # The usage profile a Pump's type gives.
      def default_ihg_usage_profile(device_type)
        DEFAULT_IHG_USAGE_PROFILE.fetch(device_type)
      end

      # The usage profile a Pump exports: the one it names, or else its type's, as honeybee-ph re-seeds it from the
      # type and the Grasshopper component reads a blank one.
      def ihg_usage_profile(values)
        values["ihg_usage_profile"] || default_ihg_usage_profile(values.fetch("device_type"))
      end
    end
  end
end
