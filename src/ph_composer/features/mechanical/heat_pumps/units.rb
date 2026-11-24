# frozen_string_literal: true

module PhComposer
  module Mechanical
    HP_OUTDOOR_UNIT_KIND = "#{FEATURE_ID}.hp_outdoor_unit".freeze
    HP_INDOOR_UNIT_KIND = "#{FEATURE_ID}.hp_indoor_unit".freeze

    module HeatPumps
      IDENTITY = [
        Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when " \
                                                                                   "unknown." }),
        Fields.field("model", { "type" => %w[string null], "description" => "The maker's model; absent when " \
                                                                            "unknown." })
      ].freeze
      QUANTITY = Fields.field("quantity", { "type" => "integer", "minimum" => 1,
                                            "description" => "How many identical units this record stands for." },
                              :required => true)

      # An installed outdoor unit: one or more of an outdoor model. Its quantity counts toward the blend.
      module OutdoorUnits
        KIND_ID = HP_OUTDOOR_UNIT_KIND
        EQUIPMENT_REFERENCE = Records::Reference.new(:key => "outdoor_equipment_id",
                                                     :target_kind => HP_OUTDOOR_EQUIPMENT_KIND,
                                                     :cardinality => "one", :required => true)
        FIELDS = Fields.with_source_snapshot(Fields.common + IDENTITY + [
          EQUIPMENT_REFERENCE, QUANTITY,
          Fields.field("in_conditioned_space", { "type" => "boolean", "description" => "Whether the unit sits " \
                                                                                       "inside the thermal " \
                                                                                       "envelope." },
                       :required => true)
        ])
        SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
        DEFAULTS = { "quantity" => 1, "in_conditioned_space" => false }.freeze

        KIND = Records::RecordKind.new(
          :id => KIND_ID, :label => "Heat Pump Outdoor Unit", :schema_version => 1, :id_prefix => "hou",
          :fields => FIELDS,
          :validate => lambda { |values|
            Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA)
          }
        )

        module_function

        def defaults(values)
          DEFAULTS.merge(Fields.defaults(values))
        end
      end

      # An installed indoor unit: one or more of an indoor model, on the outdoor unit that serves it. A Zone names
      # the indoor units serving it, so an outdoor unit reaches a Zone through the indoor units on it.
      module IndoorUnits
        KIND_ID = HP_INDOOR_UNIT_KIND
        EQUIPMENT_REFERENCE = Records::Reference.new(:key => "indoor_equipment_id",
                                                     :target_kind => HP_INDOOR_EQUIPMENT_KIND,
                                                     :cardinality => "one", :required => true)
        OUTDOOR_REFERENCE = Records::Reference.new(:key => "outdoor_unit_id", :target_kind => HP_OUTDOOR_UNIT_KIND,
                                                   :cardinality => "one", :required => true)
        FIELDS = Fields.with_source_snapshot(Fields.common + IDENTITY + [
          EQUIPMENT_REFERENCE, OUTDOOR_REFERENCE, QUANTITY,
          Fields.field("in_conditioned_space", { "type" => "boolean", "description" => "Whether the unit sits " \
                                                                                       "inside the thermal " \
                                                                                       "envelope." },
                       :required => true)
        ])
        SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
        DEFAULTS = { "quantity" => 1, "in_conditioned_space" => true }.freeze

        KIND = Records::RecordKind.new(
          :id => KIND_ID, :label => "Heat Pump Indoor Unit", :schema_version => 1, :id_prefix => "hiu",
          :fields => FIELDS,
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
