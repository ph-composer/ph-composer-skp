# frozen_string_literal: true

module PhComposer
  module Programs
    # The fourteen honeybee-ph PhEquipment types an Equipment Set's device may be, and what each carries. One table
    # drives the device schema, its validation, the device dialog (`equipment_sets.device_types`) and, at export,
    # the export to honeybee-ph's `PhEquipment` dicts.
    #
    # Sources: the pinned honeybee-ph 1.33.68 wheel (src/ph_composer/vendor/wheels), `honeybee_energy_ph/load/
    # ph_equipment.py` for each class and its `to_dict` keys, `_ph_equip_types.py` for the enumerations and
    # `honeybee_ph_standards/programtypes/default_elec_equip.py` for the Phius defaults; and honeybee_grasshopper_ph
    # at 8967c64c, `honeybee_ph_rhino/gh_compo_io/program/create_elec_equip.py`, for which inputs each type exposes
    # and the reference quantity codes and energy norms it allows.
    #
    # Every device carries the common fields. `energy_demand` is absent on the Phius-rule types and the clothes
    # dryer, whose demand WUFI-Passive and METr derive (from the reference quantity, or from the dryer's CEF);
    # `reference_energy_norm` and `energy_demand_per_use` (PHPP only) are absent where the component marks them
    # "not used". A type's own fields follow. Keys are PH-Composer's; `hbph` names the honeybee-ph attribute where
    # it differs, and an enumeration maps each stored value to honeybee-ph's string.
    module EquipmentTypes
      COMMON = %w[id type display_name quantity in_conditioned_space comment reference_quantity user_data].freeze
      WATER_CONNECTIONS = { "dhw" => "1-DHW CONNECTION", "cold_water" => "2-COLD WATER CONNECTION" }.freeze
      DRYER_TYPES = {
        "clothes_line" => "1-CLOTHES LINE", "drying_closet_cold" => "2-DRYING CLOSET (COLD!)",
        "drying_closet_cold_extract_air" => "3-DRYING CLOSET (COLD!) IN EXTRACT AIR",
        "condensation" => "4-CONDENSATION DRYER", "electric_exhaust_air" => "5-ELECTRIC EXHAUST AIR DRYER",
        "gas_exhaust_air" => "6-GAS EXHAUST AIR DRYER", "heat_pump" => "7-HEAT PUMP DRYER"
      }.freeze
      COOKTOP_TYPES = { "electricity" => "1-ELECTRICITY", "natural_gas" => "2-NATURAL GAS", "lpg" => "3-LPG" }.freeze

      # Each optional field a type may carry: its schema, and the honeybee-ph attribute and enumeration it maps to.
      FIELDS = {
        "reference_energy_norm" => { "schema" => { "type" => "integer",
                                                   "description" => "The period energy_demand is given for: 1 a " \
                                                                    "day or a use, 2 a year." } },
        "energy_demand" => { "schema" => { "type" => "number", "minimum" => 0, "x-unit" => "kWh",
                                           "description" => "Per unit, over reference_energy_norm's period." } },
        "energy_demand_per_use" => { "schema" => { "type" => "number", "minimum" => 0, "x-unit" => "kWh",
                                                   "description" => "PHPP only; WUFI-Passive and METr ignore it." } },
        "capacity_type" => { "schema" => { "type" => "integer", "enum" => [1],
                                           "description" => "1, standard." } },
        "capacity_place_settings" => { "schema" => { "type" => "number", "exclusiveMinimum" => 0 },
                                       "hbph" => "capacity" },
        "capacity_m3" => { "schema" => { "type" => "number", "exclusiveMinimum" => 0, "x-unit" => "m3" },
                           "hbph" => "capacity" },
        "modified_energy_factor" => { "schema" => { "type" => "number", "exclusiveMinimum" => 0 } },
        "utilization_factor" => { "schema" => { "type" => "number", "minimum" => 0 } },
        "water_connection" => { "schema" => { "type" => "string", "enum" => WATER_CONNECTIONS.keys },
                                "hbph" => "water_connection", "values" => WATER_CONNECTIONS },
        "dryer_type" => { "schema" => { "type" => "string", "enum" => DRYER_TYPES.keys },
                          "hbph" => "dryer_type", "values" => DRYER_TYPES },
        "combined_energy_factor" => { "schema" => { "type" => "number", "exclusiveMinimum" => 0,
                                                    "x-unit" => "lb/kWh" } },
        "gas_consumption" => { "schema" => { "type" => "number", "minimum" => 0 } },
        "gas_efficiency_factor" => { "schema" => { "type" => "number", "minimum" => 0 } },
        "field_utilization_factor_type" => { "schema" => { "type" => "integer", "enum" => [1],
                                                           "description" => "1, timer controls." } },
        "field_utilization_factor" => { "schema" => { "type" => "number", "minimum" => 0 } },
        "cooktop_type" => { "schema" => { "type" => "string", "enum" => COOKTOP_TYPES.keys },
                            "hbph" => "cooktop_type", "values" => COOKTOP_TYPES },
        "high_efficacy_fraction" => { "schema" => { "type" => "number", "minimum" => 0, "maximum" => 1,
                                                    "x-unit" => "fraction" },
                                      "hbph" => "frac_high_efficiency" }
      }.freeze

      APPLIANCE = %w[reference_energy_norm energy_demand energy_demand_per_use].freeze
      PHIUS_LIGHTING = %w[high_efficacy_fraction].freeze

      # Per type: the honeybee-ph class, a label, whether a Phius rule sets its demand, the reference quantity codes
      # and energy norms it allows, its optional fields in dialog order, and the values a new device takes
      # (honeybee-ph's PHIUS defaults where it has them). Reference quantity codes: 1 PH-case occupants, 2 Zone
      # occupants, 3 bedrooms, 4 PH-case units, 5 user defined, 6 PH-case floor area, 7 Zone floor area, 8 n.a.
      # Phius garage lighting allows 8 (the component) and 2 (the wheel's class and PHIUS default): the two
      # sources disagree, so both are accepted and the wheel's is the default.
      TYPES = {
        "dishwasher" => {
          "hbph_class" => "PhDishwasher", "label" => "Dishwasher", "phius_rule" => false,
          "reference_quantities" => [1, 2, 5], "energy_norms" => [2],
          "fields" => APPLIANCE + %w[capacity_type capacity_place_settings water_connection],
          "defaults" => { "display_name" => "Kitchen dishwasher", "reference_quantity" => 1,
                          "reference_energy_norm" => 2, "energy_demand" => 269.0, "energy_demand_per_use" => 0.0,
                          "capacity_type" => 1, "capacity_place_settings" => 12.0,
                          "water_connection" => "cold_water" }
        },
        "clothes_washer" => {
          "hbph_class" => "PhClothesWasher", "label" => "Clothes washer", "phius_rule" => false,
          "reference_quantities" => [1, 2, 5], "energy_norms" => [2],
          "fields" => APPLIANCE + %w[capacity_m3 modified_energy_factor water_connection utilization_factor],
          "defaults" => { "display_name" => "Laundry - washer", "reference_quantity" => 1,
                          "reference_energy_norm" => 2, "energy_demand" => 120.0, "energy_demand_per_use" => 0.0,
                          "capacity_m3" => 0.1274, "modified_energy_factor" => 2.7, "water_connection" => "cold_water",
                          "utilization_factor" => 1.0 }
        },
        "clothes_dryer" => {
          "hbph_class" => "PhClothesDryer", "label" => "Clothes dryer", "phius_rule" => false,
          "reference_quantities" => [1, 2, 5], "energy_norms" => [2],
          "fields" => %w[reference_energy_norm energy_demand_per_use dryer_type combined_energy_factor
                         gas_consumption gas_efficiency_factor field_utilization_factor_type
                         field_utilization_factor],
          "defaults" => { "display_name" => "Laundry - dryer", "reference_quantity" => 1,
                          "reference_energy_norm" => 2, "energy_demand_per_use" => 0.0,
                          "dryer_type" => "electric_exhaust_air", "combined_energy_factor" => 3.93,
                          "gas_consumption" => 0.0, "gas_efficiency_factor" => 2.67,
                          "field_utilization_factor_type" => 1, "field_utilization_factor" => 1.18 }
        },
        "refrigerator" => {
          "hbph_class" => "PhRefrigerator", "label" => "Refrigerator", "phius_rule" => false,
          "reference_quantities" => [4, 5], "energy_norms" => [1, 2], "fields" => APPLIANCE,
          "defaults" => { "display_name" => "Kitchen refrigerator", "reference_quantity" => 4,
                          "reference_energy_norm" => 1, "energy_demand" => 1.0, "energy_demand_per_use" => 0.0 }
        },
        "freezer" => {
          "hbph_class" => "PhFreezer", "label" => "Freezer", "phius_rule" => false,
          "reference_quantities" => [4, 5], "energy_norms" => [1, 2], "fields" => APPLIANCE,
          "defaults" => { "display_name" => "Kitchen freezer", "reference_quantity" => 4,
                          "reference_energy_norm" => 1, "energy_demand" => 1.0795, "energy_demand_per_use" => 0.0 }
        },
        "fridge_freezer" => {
          "hbph_class" => "PhFridgeFreezer", "label" => "Fridge-freezer", "phius_rule" => false,
          "reference_quantities" => [4, 5], "energy_norms" => [1, 2], "fields" => APPLIANCE,
          "defaults" => { "display_name" => "Kitchen fridge/freeze combo", "reference_quantity" => 4,
                          "reference_energy_norm" => 1, "energy_demand" => 1.22, "energy_demand_per_use" => 0.0 }
        },
        "cooktop" => {
          "hbph_class" => "PhCooktop", "label" => "Cooktop", "phius_rule" => false,
          "reference_quantities" => [1, 2, 5], "energy_norms" => [1], "fields" => APPLIANCE + %w[cooktop_type],
          "defaults" => { "display_name" => "Kitchen cooking", "reference_quantity" => 1,
                          "reference_energy_norm" => 1, "energy_demand" => 0.2, "energy_demand_per_use" => 0.0,
                          "cooktop_type" => "electricity" }
        },
        "phius_mel" => {
          "hbph_class" => "PhPhiusMEL", "label" => "Phius MEL", "phius_rule" => true,
          "reference_quantities" => [3, 5], "energy_norms" => [], "fields" => [],
          "defaults" => { "display_name" => "PHIUS+ MELS", "reference_quantity" => 3 }
        },
        "phius_lighting_interior" => {
          "hbph_class" => "PhPhiusLightingInterior", "label" => "Phius interior lighting", "phius_rule" => true,
          "reference_quantities" => [6, 7, 5], "energy_norms" => [], "fields" => PHIUS_LIGHTING,
          "defaults" => { "display_name" => "PHIUS+ Interior Lighting", "reference_quantity" => 6,
                          "high_efficacy_fraction" => 1.0 }
        },
        "phius_lighting_exterior" => {
          "hbph_class" => "PhPhiusLightingExterior", "label" => "Phius exterior lighting", "phius_rule" => true,
          "reference_quantities" => [6, 7, 5], "energy_norms" => [], "fields" => PHIUS_LIGHTING,
          "defaults" => { "display_name" => "PHIUS+ Exterior Lighting", "reference_quantity" => 6,
                          "in_conditioned_space" => false, "high_efficacy_fraction" => 1.0 }
        },
        "phius_lighting_garage" => {
          "hbph_class" => "PhPhiusLightingGarage", "label" => "Phius garage lighting", "phius_rule" => true,
          "reference_quantities" => [2, 8], "energy_norms" => [], "fields" => PHIUS_LIGHTING,
          "defaults" => { "display_name" => "PHIUS+ Garage Lighting", "reference_quantity" => 2,
                          "in_conditioned_space" => false, "high_efficacy_fraction" => 1.0 }
        },
        "custom_annual_electric" => {
          "hbph_class" => "PhCustomAnnualElectric", "label" => "Custom annual electric", "phius_rule" => false,
          "reference_quantities" => [5], "energy_norms" => [], "fields" => %w[energy_demand],
          "defaults" => { "display_name" => "User defined", "reference_quantity" => 5, "energy_demand" => 0.0 }
        },
        "custom_annual_lighting" => {
          "hbph_class" => "PhCustomAnnualLighting", "label" => "Custom annual lighting", "phius_rule" => false,
          "reference_quantities" => [5], "energy_norms" => [], "fields" => %w[energy_demand],
          "defaults" => { "display_name" => "User defined - lighting", "reference_quantity" => 5,
                          "energy_demand" => 0.0 }
        },
        "custom_annual_mel" => {
          "hbph_class" => "PhCustomAnnualMEL", "label" => "Custom annual MEL", "phius_rule" => false,
          "reference_quantities" => [5], "energy_norms" => [], "fields" => %w[energy_demand],
          "defaults" => { "display_name" => "User defined - Misc electric loads", "reference_quantity" => 5,
                          "energy_demand" => 0.0 }
        }
      }.freeze
      NAMES = TYPES.keys.freeze
      COMMON_DEFAULTS = { "quantity" => 1, "in_conditioned_space" => true, "comment" => "" }.freeze

      # One stored device: the common fields, then every optional field any type carries, each checked against the
      # device's own type by `problems`.
      DEVICE = SchemaShapes.object({
        "id" => SchemaShapes.id("dev", "This device's id, unique within its Equipment Set."),
        "type" => { "type" => "string", "enum" => NAMES, "description" => "The honeybee-ph type; fixed once added." },
        "display_name" => { "type" => "string", "minLength" => 1 },
        "quantity" => { "type" => "integer", "minimum" => 1 },
        "in_conditioned_space" => { "type" => "boolean" },
        "comment" => { "type" => "string" },
        "reference_quantity" => { "type" => "integer",
                                  "description" => "The WUFI-Passive and METr reference quantity code the type " \
                                                   "allows." },
        "user_data" => SchemaShapes::PART_USER_DATA
      }.merge(FIELDS.transform_values { |field| field.fetch("schema") }),
                                   :optional => ["user_data"] + FIELDS.keys).freeze

      module_function

      def fetch(type)
        TYPES.fetch(type)
      end

      # A new device of `type`: its defaults under `values`, with `id`.
      def device(type, id, values = {})
        { "id" => id, "type" => type }.merge(COMMON_DEFAULTS).merge(DeepCopy.call(fetch(type).fetch("defaults")))
                                      .merge(DeepCopy.call(values))
      end

      # Every reason `device` does not fit its type: a field the type does not carry, a required one missing, a
      # reference quantity or energy norm the type does not allow, or a non-blank display name.
      def problems(device)
        type = TYPES[device["type"]]
        return ["Device type #{device['type'].inspect} is unknown."] unless type

        label = "#{type.fetch('label')} #{device['id']}"
        allowed = COMMON + type.fetch("fields")
        found = (device.keys - allowed).sort.map { |key| "#{label} does not carry #{key}." }
        found.concat((allowed - device.keys - %w[user_data]).sort.map { |key| "#{label} needs #{key}." })
        unless type.fetch("reference_quantities").include?(device["reference_quantity"])
          found << "#{label} allows reference quantity #{type.fetch('reference_quantities').join(', ')}."
        end
        norm = device["reference_energy_norm"]
        if device.key?("reference_energy_norm") && !type.fetch("energy_norms").include?(norm)
          found << "#{label} allows energy norm #{type.fetch('energy_norms').join(', ')}."
        end
        found << "#{label} needs a display name." if device["display_name"].to_s.strip.empty?
        found
      end

      # The honeybee-ph class of `device` and the attributes the export sets on a new one, by honeybee-ph's names and
      # values, with `quantity` in place of the device's own. The translation sets each on the class's instance.
      def hbph(device, quantity)
        type = fetch(device.fetch("type"))
        attributes = { "display_name" => device.fetch("display_name"), "comment" => device.fetch("comment"),
                       "quantity" => quantity, "in_conditioned_space" => device.fetch("in_conditioned_space"),
                       "reference_quantity" => device.fetch("reference_quantity") }
        type.fetch("fields").each do |key|
          field = FIELDS.fetch(key)
          value = device.fetch(key)
          attributes[field.fetch("hbph", key)] = field["values"] ? field["values"].fetch(value) : value
        end
        { "class" => type.fetch("hbph_class"), "attributes" => attributes }
      end

      # What the device dialog and an agent read: each type with its label, rule flag, allowed codes, fields with
      # their schemas, and the values a new device takes.
      def catalog
        TYPES.map do |name, type|
          { "type" => name, "label" => type.fetch("label"), "hbph_class" => type.fetch("hbph_class"),
            "phius_rule" => type.fetch("phius_rule"), "reference_quantities" => type.fetch("reference_quantities"),
            "energy_norms" => type.fetch("energy_norms"),
            "fields" => type.fetch("fields").map { |key| { "key" => key, "schema" => FIELDS.fetch(key)["schema"] } },
            "defaults" => device(name, "dev_AAAAAAAAAAAA").reject { |key, _| %w[id type].include?(key) } }
        end
      end
    end
  end
end
