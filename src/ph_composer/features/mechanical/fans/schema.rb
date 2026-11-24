# frozen_string_literal: true

module PhComposer
  module Mechanical
    FAN_KIND = "#{FEATURE_ID}.fan"

    # The Fan: a Model-owned definition of one exhaust fan, the values honeybee-ph's exhaust ventilators carry (a
    # kitchen hood, a dryer or a user-defined exhaust), with an optional electric block. Power left blank means the
    # fan's electricity is not modelled; with Power, the fan also exports as a supportive device of type 10 whose
    # operation follows the fan's runtime unless the record names another. It is a definition only: it names nothing
    # it is used by.
    module Fans
      KIND_ID = FAN_KIND
      # honeybee-ph's three exhaust ventilator classes, by the names the record stores.
      EXHAUST_TYPES = %w[kitchen_hood dryer user_defined].freeze
      # Minutes in a thousand hours: the runtime in minutes a year over this is the operation in kilohours a year.
      MINUTES_PER_KILOHOUR = 60_000.0
      FIELDS = Fields.with_source_snapshot(Fields.common + [
        Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when unknown." }),
        Fields.field("model",
                     { "type" => %w[string null], "description" => "The maker's model; absent when unknown." }),
        Fields.field("exhaust_type", { "type" => "string", "enum" => EXHAUST_TYPES,
                                       "description" => "The exhaust ventilator it is: kitchen_hood, dryer or " \
                                                        "user_defined." },
                     :required => true),
        Fields.field("quantity", { "type" => "integer", "minimum" => 1,
                                   "description" => "How many identical fans this record stands for." },
                     :required => true),
        Fields.field("exhaust_flow_rate_m3h", { "type" => "number", "minimum" => 0, "x-unit" => "m3/h",
                                                "description" => "The air it exhausts while it runs." },
                     :required => true),
        Fields.field("annual_runtime_minutes", { "type" => "number", "minimum" => 0, "x-unit" => "min",
                                                 "description" => "Minutes it runs a year." },
                     :required => true),
        Fields.field("norm_energy_demand_w", { "type" => %w[number null], "minimum" => 0, "x-unit" => "W",
                                               "description" => "Electrical power while it runs; absent when its " \
                                                                "electricity is not modelled, so it exports no " \
                                                                "supportive device." }),
        Fields.field("in_conditioned_space", { "type" => "boolean", "description" => "Whether the fan sits " \
                                                                                     "inside the thermal envelope." },
                     :required => true),
        Fields.field("annual_period_operation_khrs", { "type" => %w[number null], "minimum" => 0, "x-unit" => "kh",
                                                       "description" => "Thousands of hours its supportive device " \
                                                                        "runs a year; absent to follow the runtime " \
                                                                        "(annual_runtime_minutes / 60,000)." })
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
      # A new Fan: one user-defined exhaust inside the envelope that moves no air and runs no minutes until they are
      # entered (honeybee-ph's and the Grasshopper component's defaults), with no Power, so no supportive device.
      DEFAULTS = { "exhaust_type" => "user_defined", "quantity" => 1, "exhaust_flow_rate_m3h" => 0.0,
                   "annual_runtime_minutes" => 0.0, "in_conditioned_space" => true }.freeze

      KIND = Records::RecordKind.new(
        :id => KIND_ID, :label => "Fan", :schema_version => 1, :id_prefix => "fan", :fields => FIELDS,
        :validate => ->(values) { Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) }
      )

      module_function

      def defaults(values)
        DEFAULTS.merge(Fields.defaults(values))
      end

      # The operation a Fan's runtime gives, in kilohours a year.
      def default_annual_period_operation_khrs(annual_runtime_minutes)
        annual_runtime_minutes / MINUTES_PER_KILOHOUR
      end

      # The operation a Fan's supportive device exports: the one it names, or else its runtime's.
      def annual_period_operation_khrs(values)
        values["annual_period_operation_khrs"] ||
          default_annual_period_operation_khrs(values.fetch("annual_runtime_minutes"))
      end
    end
  end
end
