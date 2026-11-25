# frozen_string_literal: true

module PhComposer
  module Mechanical
    HOT_WATER_SYSTEM_KIND = "#{FEATURE_ID}.hot_water_system".freeze

    # Hot water is three flat catalogs: Systems, the Heaters and the Tanks that each name their System. A System is
    # the one hot water record a Room is given; its Heaters and Tanks reach the Room through it. Each kind is a
    # definition only and names nothing it is used by.
    module HotWater
      # The Hot Water System: what honeybee-ph's PhHotWaterSystem carries of its own. Its recirculation temperature
      # and hours are not stored: honeybee-ph works them out from the recirculation piping, and gives 60 C and 24 h
      # with none. The piping calculation method is stored, and exported only once the pinned honeybee-ph carries
      # a field for it.
      module Systems
        KIND_ID = HOT_WATER_SYSTEM_KIND
        # Whether the pinned honeybee-ph writes a piping calculation method. Only the loaded Python class can say
        # (python/ph_composer_translation/mechanical_sections.py); this mirrors it for the System rows, and
        # tests/fixtures/mechanical/hot_water_method.json holds the two equal, so a wheel that gains the field
        # (honeybee_ph#135) fails tests/python/test_hot_water_sections.py until this flips.
        METHOD_EXPORTED = false
        FIELDS = Fields.with_source_snapshot(Fields.common + [
          Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when " \
                                                                                     "unknown." }),
          Fields.field("model", { "type" => %w[string null], "description" => "The maker's model; absent when " \
                                                                              "unknown." }),
          # At least 1: honeybee-ph takes 0 as unset and counts the piping's fixtures instead.
          Fields.field("number_tap_points", { "type" => %w[integer null], "minimum" => 1,
                                              "description" => "How many hot water tap points the System feeds; " \
                                                               "absent to let the piping count them." }),
          Fields.field("piping_calc_method", { "type" => %w[integer null], "minimum" => 1, "maximum" => 4,
                                               "description" => "The piping calculation method, 1 to 4; absent " \
                                                                "for none. Exported once honeybee-ph carries it." })
        ])
        SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)

        KIND = Records::RecordKind.new(
          :id => KIND_ID, :label => "Hot Water System", :schema_version => 1, :id_prefix => "hws", :fields => FIELDS,
          :validate => lambda { |values|
            Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA)
          }
        )

        module_function

        # A new System's values: the shared defaults. Tap points and the calculation method stay absent.
        def defaults(values)
          Fields.defaults(values)
        end

        # The message a System setting a calculation method the export cannot write carries, or nil.
        def method_not_exported(record)
          method = record["piping_calc_method"]
          return nil if method.nil? || METHOD_EXPORTED

          "#{record.fetch('name')} sets piping calculation method #{method}, and the pinned honeybee-ph has no " \
            "field for it, so the export leaves it out."
        end
      end
    end
  end
end
