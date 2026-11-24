# frozen_string_literal: true

module PhComposer
  module Mechanical
    HOT_WATER_TANK_KIND = "#{FEATURE_ID}.hot_water_tank".freeze

    module HotWater
      # A Hot Water Tank: the values honeybee-ph's PhHvacHotWaterTank carries, on the System it names. Its `role`
      # says which of the System's four tank slots it can fill (Slotting): storage tanks the first two, a buffer
      # tank the buffer slot, a solar tank the solar slot.
      module Tanks
        KIND_ID = HOT_WATER_TANK_KIND
        ROLES = %w[storage buffer solar].freeze
        # honeybee-ph's tank types, as its enumeration reads them back.
        TANK_TYPES = ["0-NO STORAGE TANK", "1-DHW AND HEATING", "2-DHW ONLY"].freeze
        NON_NEGATIVE = { "type" => "number", "minimum" => 0 }.freeze
        SYSTEM_REFERENCE = Records::Reference.new(:key => "hot_water_system_id", :target_kind => HOT_WATER_SYSTEM_KIND,
                                                  :cardinality => "one", :required => true)
        FIELDS = Fields.with_source_snapshot(Fields.common + [
          Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when " \
                                                                                     "unknown." }),
          Fields.field("model", { "type" => %w[string null], "description" => "The maker's model; absent when " \
                                                                              "unknown." }),
          SYSTEM_REFERENCE,
          Fields.field("role", { "type" => "string", "enum" => ROLES,
                                 "description" => "Which of the System's tank slots it fills: storage the first " \
                                                  "two, buffer the buffer slot, solar the solar slot." },
                       :required => true),
          Fields.field("tank_type", { "type" => "string", "enum" => TANK_TYPES,
                                      "description" => "What the tank stores water for." }, :required => true),
          Fields.field("quantity", { "type" => "integer", "minimum" => 1,
                                     "description" => "How many identical tanks this record stands for." },
                       :required => true),
          Fields.field("in_conditioned_space", { "type" => "boolean", "description" => "Whether the tank sits " \
                                                                                       "inside the thermal " \
                                                                                       "envelope." },
                       :required => true),
          Fields.field("solar_connection", { "type" => "boolean", "description" => "Whether a solar thermal " \
                                                                                   "collector feeds it." },
                       :required => true),
          Fields.field("solar_losses_w", NON_NEGATIVE.merge("x-unit" => "W", "description" => "Solar thermal " \
                                                                                              "losses."),
                       :required => true),
          Fields.field("storage_loss_rate_w_k", NON_NEGATIVE.merge("x-unit" => "W/K",
                                                                   "description" => "Storage heat loss rate."),
                       :required => true),
          Fields.field("storage_capacity_l", NON_NEGATIVE.merge("x-unit" => "L", "description" => "Tank volume."),
                       :required => true),
          Fields.field("standby_losses_w_k", NON_NEGATIVE.merge("x-unit" => "W/K",
                                                                "description" => "Standby heat losses."),
                       :required => true),
          Fields.field("standby_fraction", { "type" => "number", "minimum" => 0, "maximum" => 1,
                                             "x-unit" => "fraction",
                                             "description" => "The share of standby losses that heat the space, " \
                                                              "0 to 1." }, :required => true),
          Fields.field("room_temp_c", { "type" => "number", "x-unit" => "C",
                                        "description" => "The temperature around the tank." }, :required => true),
          Fields.field("water_temp_c", { "type" => "number", "x-unit" => "C",
                                         "description" => "The stored water temperature." }, :required => true)
        ])
        SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
        # honeybee-ph's own defaults, and the storage role.
        DEFAULTS = { "role" => "storage", "tank_type" => "2-DHW ONLY", "quantity" => 1, "in_conditioned_space" => true,
                     "solar_connection" => false, "solar_losses_w" => 0.0, "storage_loss_rate_w_k" => 0.0,
                     "storage_capacity_l" => 300.0, "standby_losses_w_k" => 4.0, "standby_fraction" => 0.3,
                     "room_temp_c" => 20.0, "water_temp_c" => 60.0 }.freeze

        KIND = Records::RecordKind.new(
          :id => KIND_ID, :label => "Hot Water Tank", :schema_version => 1, :id_prefix => "hwt", :fields => FIELDS,
          :validate => lambda { |values|
            Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA)
          }
        )

        module_function

        def defaults(values)
          DEFAULTS.merge(Fields.defaults(values))
        end
      end
    end
  end
end
