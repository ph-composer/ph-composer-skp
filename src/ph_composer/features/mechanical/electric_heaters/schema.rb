# frozen_string_literal: true

module PhComposer
  module Mechanical
    ELECTRIC_HEATER_KIND = "#{FEATURE_ID}.electric_heater"

    # The Electric Heater: a Model-owned definition of direct electric resistance heating, the values honeybee-ph's
    # PhHeatingDirectElectric carries. Its coverage is the share of the heating load it covers, stored as a fraction.
    # It is a definition only: it names nothing it is used by.
    module ElectricHeaters
      KIND_ID = ELECTRIC_HEATER_KIND
      FIELDS = Fields.with_source_snapshot(Fields.common + [
        Fields.field("manufacturer", { "type" => %w[string null], "description" => "The maker; absent when unknown." }),
        Fields.field("model",
                     { "type" => %w[string null], "description" => "The maker's model; absent when unknown." }),
        Fields.field("percent_coverage", { "type" => "number", "minimum" => 0, "maximum" => 1,
                                           "x-unit" => "fraction",
                                           "description" => "The share of the heating load it covers, 0 to 1." },
                     :required => true)
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
      # A new Electric Heater covers the whole load, honeybee-ph's default.
      DEFAULTS = { "percent_coverage" => 1.0 }.freeze

      KIND = Records::RecordKind.new(
        :id => KIND_ID, :label => "Electric Heater", :schema_version => 1, :id_prefix => "ehr", :fields => FIELDS,
        :validate => ->(values) { Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) }
      )

      module_function

      def defaults(values)
        DEFAULTS.merge(Fields.defaults(values))
      end
    end
  end
end
