# frozen_string_literal: true

module PhComposer
  module Programs
    # PH-Composer's residential default Program and its Schedules, and the default Equipment Set, as frozen records
    # under reserved ids (context/CONTRACTS.md, "Programs, Schedules and Equipment Sets"). Until a write touches
    # one, reads answer it from here (Store). The values follow honeybee_grasshopper_ph's Set Residential Program
    # (`program/set_res_program.py` at 8967c64c) over the pinned honeybee-ph 1.33.68 schedules
    # (`honeybee_ph_standards/schedules/hbph_sfh_*.json`) and PHIUS equipment defaults
    # (`programtypes/default_elec_equip.py`):
    #
    # - People, Lighting and Service hot water follow their Phius rules, worked out per Dwelling at export.
    # - Electric and gas equipment carry 0 W/m²: every MEL comes through Equipment Set devices.
    # - Infiltration 0.0003 m³/s·m², ventilation 0.4 ACH at full flow all day, heating 20 °C, cooling 25 °C,
    #   dehumidifying at 60 %, hot water delivered at 43.3 °C.
    #
    # honeybee-ph's occupancy, lighting and hot water schedules are hourly profiles, and a fractional Schedule's PH
    # form holds two levels. Each is held here at its daily mean all day: PHX reads a schedule without operating
    # periods as 0 to 24 h at the mean of its hourly values, and the Phius People and lighting rules divide by
    # that mean, so WUFI-Passive, METr and the rules see the same values; EnergyPlus loses the hour-by-hour shape
    # until the hourly editor. The hourly profiles are kept below as the source of each mean.
    module DefaultProgram
      PROGRAM_ID = "pgm_PHCDEFAULT01"
      SOURCE = { "kind" => "ph_composer_default" }.freeze

      # The honeybee-ph hourly profiles, hour 0 first, expanded from each ScheduleDay's change points.
      PRESENCE = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 0.4, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.55, 0.9,
                  0.9, 0.9, 1.0, 1.0, 1.0].freeze
      LIGHTING = [0.008, 0.008, 0.008, 0.008, 0.024, 0.05, 0.056, 0.05, 0.022, 0.015, 0.015, 0.015, 0.015, 0.015, 0.026,
                  0.015, 0.056, 0.078, 0.105, 0.126, 0.128, 0.088, 0.049, 0.02].freeze
      HOT_WATER = [0.006, 0.003, 0.001, 0.001, 0.003, 0.022, 0.075, 0.079, 0.076, 0.067, 0.061, 0.048, 0.042, 0.037,
                   0.037, 0.033, 0.044, 0.058, 0.069, 0.065, 0.059, 0.048, 0.042, 0.023].freeze
      # hbph_sfh_Occupant_Activity, a constant.
      ACTIVITY_W = 112.53934481000194

      def self.mean(hours)
        hours.sum / hours.length
      end

      def self.constant(id, name, fraction)
        { "id" => id, "schema_version" => 1, "name" => name, "notes" => "", "datasheet_links" => [],
          "source" => SOURCE, "type" => "fractional", "days_per_week" => 7, "weeks_per_year" => 52,
          "start_h" => 0, "end_h" => 24, "fraction_on" => fraction, "fraction_off" => 0.0 }
      end

      SCHEDULES = [
        constant("sch_PHCDEFAULT01", "Residential occupancy", mean(PRESENCE)),
        { "id" => "sch_PHCDEFAULT02", "schema_version" => 1, "name" => "Residential activity", "notes" => "",
          "datasheet_links" => [], "source" => SOURCE, "type" => "activity", "days_per_week" => 7,
          "weeks_per_year" => 52, "start_h" => 0, "end_h" => 24, "watts_on" => ACTIVITY_W, "watts_off" => ACTIVITY_W },
        constant("sch_PHCDEFAULT03", "Residential lighting", mean(LIGHTING)),
        constant("sch_PHCDEFAULT04", "Residential hot water", mean(HOT_WATER)),
        constant("sch_PHCDEFAULT05", "Always on", 1.0),
        { "id" => "sch_PHCDEFAULT06", "schema_version" => 1, "name" => "Constant ventilation", "notes" => "",
          "datasheet_links" => [], "source" => SOURCE, "type" => "ventilation", "days_per_week" => 7,
          "weeks_per_year" => 52, "periods" => DeepCopy.call(Schedule::FORM_DEFAULTS.dig("ventilation", "periods")) }
      ].map { |record| DeepCopy.frozen(record) }.freeze
      OCCUPANCY, ACTIVITY, LIGHTS, WATER, ALWAYS_ON, VENTILATION = SCHEDULES.map { |record| record.fetch("id") }

      PROGRAM = DeepCopy.frozen(
        "id" => PROGRAM_ID, "schema_version" => 1, "name" => "Residential default",
        "notes" => "PH-Composer's residential default, after honeybee-ph's Set Residential Program.",
        "datasheet_links" => [], "source" => SOURCE,
        "people" => { "rule" => "phius_residential", "people_per_area" => nil, "occupancy_schedule_id" => OCCUPANCY,
                      "activity_schedule_id" => ACTIVITY, "radiant_fraction" => 0.3, "latent_fraction" => nil },
        "lighting" => { "rule" => "phius_interior", "watts_per_area" => nil, "high_efficacy_fraction" => 1.0,
                        "schedule_id" => LIGHTS, "return_air_fraction" => 0.0, "radiant_fraction" => 0.32,
                        "visible_fraction" => 0.25 },
        "electric_equipment" => { "watts_per_area" => 0.0, "schedule_id" => ALWAYS_ON, "radiant_fraction" => 0.0,
                                  "latent_fraction" => 0.0, "lost_fraction" => 0.0 },
        "gas_equipment" => { "watts_per_area" => 0.0, "schedule_id" => ALWAYS_ON, "radiant_fraction" => 0.0,
                             "latent_fraction" => 0.0, "lost_fraction" => 0.0 },
        "service_hot_water" => { "rule" => "building_america", "flow_per_area" => nil, "target_temperature_c" => 43.3,
                                 "schedule_id" => WATER, "sensible_fraction" => 0.2, "latent_fraction" => 0.05 },
        "infiltration" => { "flow_per_exterior_area" => 0.0003, "schedule_id" => ALWAYS_ON },
        "ventilation" => { "flow_per_person" => 0.0, "flow_per_area" => 0.0, "flow_per_zone" => 0.0,
                           "air_changes_per_hour" => 0.4, "schedule_id" => VENTILATION },
        "setpoint" => { "heating_c" => 20.0, "cooling_c" => 25.0, "heating_schedule_id" => nil,
                        "cooling_schedule_id" => nil, "dehumidify_rh" => 60.0, "humidify_rh" => nil }
      )
    end

    # The default Equipment Set: the eight Phius devices Set Residential Program adds to each dwelling
    # (`create_phius_default_equipment_set`), each with honeybee-ph's PHIUS defaults. Interior lighting is
    # not among them: it rides on the Program's Lighting load. honeybee-ph gives garage lighting a quantity of 0,
    # which PHX reads as 1; a device's quantity is at least 1, so it is 1 here.
    module DefaultEquipmentSet
      SET_ID = "eqs_PHCDEFAULT01"
      DEVICES = %w[fridge_freezer dishwasher clothes_washer clothes_dryer cooktop phius_lighting_exterior
                   phius_lighting_garage phius_mel].each_with_index.map do |type, index|
        EquipmentTypes.device(type, format("dev_PHCDEFAULT%02d", index + 1))
      end.freeze
      SET = DeepCopy.frozen(
        "id" => SET_ID, "schema_version" => 1, "name" => "Residential default devices",
        "notes" => "PH-Composer's default Equipment Set, the Phius single-family devices.",
        "datasheet_links" => [], "source" => DefaultProgram::SOURCE, "devices" => DEVICES
      )
    end
  end
end
