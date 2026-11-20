# frozen_string_literal: true

module PhComposer
  module Programs
    # A Program: the eight honeybee ProgramType loads, each one object so its values, its rule inputs and
    # its Schedule references move together. Values are in the honeybee unit the HBJSON field uses, so the export
    # writes them without conversion (honeybee-energy 1.123.23, `load/*.py`). A null value is a
    # value still missing.
    #
    # A rule load (People `phius_residential`, Lighting `phius_interior`, Service hot water `building_america`)
    # names its rule; its value is worked out per Dwelling at export by honeybee-ph's Phius formulas. Setting
    # `rule` to null switches the load to its fixed value and back again keeps both the value and the rule's inputs
    # (the lighting high-efficacy fraction). Ventilation sums its four terms. A set point is a constant or a
    # temperature Schedule, never both; two constants keep heating at or below cooling, and a pair naming a Schedule
    # is checked by the export preflight's set point findings. Any load may name `source`, the base program a
    # library value came from.
    module Program
      FRACTION = { "type" => "number", "minimum" => 0, "maximum" => 1, "x-unit" => "fraction" }.freeze
      SOURCE = { "type" => "string", "minLength" => 1,
                 "description" => "The base program this load's values came from, for a library Program." }.freeze

      def self.value(unit, description = nil)
        schema = { "type" => %w[number null], "minimum" => 0, "x-unit" => unit }
        description ? schema.merge("description" => description) : schema
      end

      def self.schedule(description)
        SchemaShapes.id("sch", description, :nullable => true)
      end

      def self.rule(name)
        { "type" => %w[string null], "enum" => [name, nil],
          "description" => "#{name} while the rule sets this load; null for the fixed value." }
      end

      def self.section(properties)
        SchemaShapes.object(properties.merge("source" => SOURCE), :optional => ["source"])
      end

      SECTIONS = {
        "people" => section(
          "rule" => rule("phius_residential"),
          "people_per_area" => value("people/m2", "Peak people per m² of floor."),
          "occupancy_schedule_id" => schedule("A fractional Schedule, of the peak."),
          "activity_schedule_id" => schedule("An activity Schedule, W per person."),
          "radiant_fraction" => FRACTION,
          "latent_fraction" => FRACTION.merge("type" => %w[number null],
                                              "description" => "Null for honeybee's autocalculate.")
        ),
        "lighting" => section(
          "rule" => rule("phius_interior"),
          "watts_per_area" => value("W/m2"),
          "high_efficacy_fraction" => SchemaShapes.described(FRACTION, "The Phius rule's input: the share of " \
                                                                       "high-efficacy lighting."),
          "schedule_id" => schedule("A fractional Schedule."),
          "return_air_fraction" => FRACTION, "radiant_fraction" => FRACTION, "visible_fraction" => FRACTION
        ),
        "electric_equipment" => section(
          "watts_per_area" => value("W/m2"), "schedule_id" => schedule("A fractional Schedule."),
          "radiant_fraction" => FRACTION, "latent_fraction" => FRACTION, "lost_fraction" => FRACTION
        ),
        "gas_equipment" => section(
          "watts_per_area" => value("W/m2"), "schedule_id" => schedule("A fractional Schedule."),
          "radiant_fraction" => FRACTION, "latent_fraction" => FRACTION, "lost_fraction" => FRACTION
        ),
        "service_hot_water" => section(
          "rule" => rule("building_america"),
          "flow_per_area" => value("L/h/m2", "Peak flow per m² of floor."),
          "target_temperature_c" => { "type" => "number", "exclusiveMinimum" => 0, "maximum" => 100, "x-unit" => "C" },
          "schedule_id" => schedule("A fractional Schedule."),
          "sensible_fraction" => FRACTION, "latent_fraction" => FRACTION
        ),
        "infiltration" => section(
          "flow_per_exterior_area" => value("m3/s/m2", "Per m² of exposed exterior area, at about 4 Pa."),
          "schedule_id" => schedule("A fractional Schedule.")
        ),
        "ventilation" => section(
          "flow_per_person" => value("m3/s/person"), "flow_per_area" => value("m3/s/m2"),
          "flow_per_zone" => value("m3/s"), "air_changes_per_hour" => value("1/h"),
          "schedule_id" => schedule("A ventilation Schedule.")
        ),
        "setpoint" => section(
          "heating_c" => { "type" => %w[number null], "x-unit" => "C" },
          "cooling_c" => { "type" => %w[number null], "x-unit" => "C" },
          "heating_schedule_id" => schedule("A temperature Schedule, in place of heating_c."),
          "cooling_schedule_id" => schedule("A temperature Schedule, in place of cooling_c."),
          "dehumidify_rh" => { "type" => %w[number null], "minimum" => 0, "maximum" => 100, "x-unit" => "%" },
          "humidify_rh" => { "type" => %w[number null], "minimum" => 0, "maximum" => 100, "x-unit" => "%" }
        )
      }.freeze
      NAMES = SECTIONS.keys.freeze

      # Each Schedule reference, by its dotted key, and the Schedule type it must name.
      SLOTS = {
        "people.occupancy_schedule_id" => "fractional", "people.activity_schedule_id" => "activity",
        "lighting.schedule_id" => "fractional", "electric_equipment.schedule_id" => "fractional",
        "gas_equipment.schedule_id" => "fractional", "service_hot_water.schedule_id" => "fractional",
        "infiltration.schedule_id" => "fractional", "ventilation.schedule_id" => "ventilation",
        "setpoint.heating_schedule_id" => "temperature", "setpoint.cooling_schedule_id" => "temperature"
      }.freeze
      REFERENCES = SLOTS.keys.map do |key|
        Records::Reference.new(:key => key, :target_kind => SCHEDULE_KIND, :cardinality => "one")
      end.freeze
      # Fraction groups honeybee caps at 1 together.
      CAPPED = {
        "lighting" => %w[return_air_fraction radiant_fraction visible_fraction],
        "electric_equipment" => %w[radiant_fraction latent_fraction lost_fraction],
        "gas_equipment" => %w[radiant_fraction latent_fraction lost_fraction],
        "people" => %w[radiant_fraction latent_fraction]
      }.freeze

      # A new Program's loads: nothing set but honeybee's own fractions and hot water temperature, and the full
      # share of high-efficacy lighting.
      EMPTY = {
        "people" => { "rule" => nil, "people_per_area" => nil, "occupancy_schedule_id" => nil,
                      "activity_schedule_id" => nil, "radiant_fraction" => 0.3, "latent_fraction" => nil },
        "lighting" => { "rule" => nil, "watts_per_area" => nil, "high_efficacy_fraction" => 1.0, "schedule_id" => nil,
                        "return_air_fraction" => 0.0, "radiant_fraction" => 0.32, "visible_fraction" => 0.25 },
        "electric_equipment" => { "watts_per_area" => nil, "schedule_id" => nil, "radiant_fraction" => 0.0,
                                  "latent_fraction" => 0.0, "lost_fraction" => 0.0 },
        "gas_equipment" => { "watts_per_area" => nil, "schedule_id" => nil, "radiant_fraction" => 0.0,
                             "latent_fraction" => 0.0, "lost_fraction" => 0.0 },
        "service_hot_water" => { "rule" => nil, "flow_per_area" => nil, "target_temperature_c" => 60.0,
                                 "schedule_id" => nil, "sensible_fraction" => 0.2, "latent_fraction" => 0.05 },
        "infiltration" => { "flow_per_exterior_area" => nil, "schedule_id" => nil },
        "ventilation" => { "flow_per_person" => nil, "flow_per_area" => nil, "flow_per_zone" => nil,
                           "air_changes_per_hour" => nil, "schedule_id" => nil },
        "setpoint" => { "heating_c" => nil, "cooling_c" => nil, "heating_schedule_id" => nil,
                        "cooling_schedule_id" => nil, "dehumidify_rh" => nil, "humidify_rh" => nil }
      }.freeze

      # A library file's form of each load (docs/LIBRARY_FILE_FORMAT.md): every value optional, as a library row
      # may leave one to its default, and each Schedule named by its record id in the same library.
      LIBRARY_SECTIONS = SECTIONS.to_h do |name, schema|
        properties = schema.fetch("properties").to_h do |key, field|
          reference = SLOTS.key?("#{name}.#{key}")
          [key, reference ? { "type" => %w[string null], "minLength" => 1,
                              "description" => "A Schedule, by its record id in the same library." } : field]
        end
        [name, SchemaShapes.object(properties, :optional => properties.keys)]
      end.freeze

      FIELDS = KindFields.with(SECTIONS.map { |name, schema| Fields.field(name, schema, :required => true) },
                               LIBRARY_SECTIONS)
      SNAPSHOT_SCHEMA = FIELDS.find { |field| field.key == "source" }.schema.dig("properties", "snapshot")

      module_function

      def problems(values)
        found = Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA)
        CAPPED.each do |name, keys|
          sum = keys.sum { |key| values.fetch(name)[key] || 0 }
          found << "The #{name} fractions #{keys.join(', ')} sum to more than 1." if sum > 1 + 1e-9
        end
        values.fetch("service_hot_water").then do |load|
          if load.fetch("sensible_fraction") + load.fetch("latent_fraction") > 1 + 1e-9
            found << "The service hot water sensible and latent fractions sum to more than 1."
          end
        end
        found.concat(setpoint_problems(values.fetch("setpoint")))
      end

      def setpoint_problems(setpoint)
        found = %w[heating cooling].filter_map do |side|
          next unless !setpoint["#{side}_c"].nil? && !setpoint["#{side}_schedule_id"].nil?

          "A #{side} set point is a constant or a Schedule, not both."
        end
        heating = setpoint["heating_c"]
        cooling = setpoint["cooling_c"]
        found << "The heating set point is above the cooling set point." if heating && cooling && heating > cooling
        found
      end

      def defaults(values)
        DeepCopy.call(EMPTY).merge(Fields.defaults(values))
      end

      KIND = Records::RecordKind.new(:id => PROGRAM_KIND, :label => "Program", :schema_version => 1,
                                     :id_prefix => "pgm", :fields => FIELDS, :references => REFERENCES,
                                     :validate => method(:problems))
    end

    # An Equipment Set: honeybee-ph PhEquipment devices, each a part with its own `user_data`,
    # laid out by its type (EquipmentTypes). A Set is assigned to a Dwelling or to a Zone that is not a dwelling.
    module EquipmentSet
      # A library file's device: no id, which each copy allocates, and no user_data; every value but the type
      # optional, the type's defaults filling the rest (docs/LIBRARY_FILE_FORMAT.md).
      LIBRARY_DEVICE = EquipmentTypes::DEVICE.fetch("properties").reject { |key, _| %w[id user_data].include?(key) }
                                             .then { |properties|
        SchemaShapes.object(properties,
                            :optional => properties.keys -
                                                                ["type"])
      }
                                             .freeze
      FIELDS = KindFields.with([
        Fields.field("devices", { "type" => "array", "items" => EquipmentTypes::DEVICE }, :required => true)
      ], "devices" => { "type" => "array", "items" => LIBRARY_DEVICE })
      SNAPSHOT_SCHEMA = FIELDS.find { |field| field.key == "source" }.schema.dig("properties", "snapshot")
      PARTS = [Records::Part.new(:label => "Device", :path => "devices[]")].freeze

      module_function

      def problems(values)
        Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) +
          values.fetch("devices").flat_map { |device| EquipmentTypes.problems(device) }
      end

      def defaults(values)
        { "devices" => [] }.merge(Fields.defaults(values))
      end

      KIND = Records::RecordKind.new(:id => EQUIPMENT_SET_KIND, :label => "Equipment Set", :schema_version => 1,
                                     :id_prefix => "eqs", :fields => FIELDS, :parts => PARTS,
                                     :validate => method(:problems))
    end
  end
end
