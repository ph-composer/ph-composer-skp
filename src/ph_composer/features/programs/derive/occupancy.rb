# frozen_string_literal: true

module PhComposer
  module Programs
    # Pure: what each Zone's occupancy works out to, from plain records in, SI values out (context/CONTRACTS.md,
    # "Occupancy"). The reads gather the inputs; the export carries these values, so the translation repeats no rule.
    module Derive
      FT2_PER_M2 = 1.0 / (0.3048 * 0.3048)
      HOURS_PER_YEAR = 8760.0

      # One Zone's inputs: its id, Segment id, assignment, and Spaces' sums (floor area, iCFA, net volume, the
      # airflow mode and its supply and extract sums, m³/h).
      Zone = Struct.new(:id, :segment_id, :assignment, :floor_area_m2, :icfa_m2, :net_volume_m3, :airflow_mode,
                        :supply_m3h, :extract_m3h, keyword_init: true)

      module_function

      # ---------------------------------------------------------------- assignment

      # The Program a Zone uses: the Model's default under Single dwelling, else its own, else its Segment's
      # default, else the Model's.
      def program_id(zone, segment, default_program_id)
        return default_program_id if segment&.single?

        zone.assignment["program_id"] || segment&.settings&.fetch("default_program_id") || default_program_id
      end

      # The Dwelling a Zone is in, as `{"key", "id", "name", "units", "bedrooms", "occupants", "equipment_set_id",
      # "single"}`, or nil: under Single dwelling the Segment's house (no record, so id null; key the Segment),
      # else the Dwelling its assignment names.
      def dwelling(zone, segment, dwellings)
        if segment&.single?
          settings = segment.settings
          return { "key" => "segment:#{segment.id}", "id" => nil, "name" => segment.name, "units" => 1,
                   "bedrooms" => settings["bedrooms"], "occupants" => settings["occupants"],
                   "equipment_set_id" => settings["equipment_set_id"], "single" => true }
        end
        record = dwellings[zone.assignment["dwelling_id"]]
        return nil unless record

        record.slice("id", "name", "units", "bedrooms", "occupants", "equipment_set_id")
              .merge("key" => record.fetch("id"), "single" => false)
      end

      # A Dwelling's bedrooms and occupants: its own when it holds them, else its Zones' summed; occupants with
      # neither by the Phius rule, bedrooms + units. `occupants_rule` says the rule gave them.
      # A single dwelling's house takes its counts from its Segment alone: its Zones' assignments are overridden.
      def counts(dwelling, zones)
        zones = [] if dwelling["single"]
        bedrooms = dwelling["bedrooms"] || sum(zones.map { |zone| zone.assignment["bedrooms"] })
        occupants = dwelling["occupants"] || sum(zones.map { |zone| zone.assignment["occupants"] })
        rule = occupants.nil? && !bedrooms.nil?
        { "bedrooms" => bedrooms, "occupants" => rule ? bedrooms + dwelling.fetch("units") : occupants,
          "occupants_rule" => rule }
      end

      def sum(values)
        values = values.compact
        values.empty? ? nil : values.sum
      end

      # ---------------------------------------------------------------- loads

      # The mean of a fractional Schedule's day, as honeybee-ph's `annual_average_operating_fraction` reads its
      # ruleset (the weighted hours over 24, whatever its days per week and weeks per year); nil without one.
      def mean(profile)
        daily = profile && profile["daily_full_load_hours"]
        daily && daily / 24.0
      end

      # Peak people in a Zone. The Phius residential rule shares its Dwelling's occupants over the presence
      # Schedule's mean by gross floor area, as honeybee-ph's Set Residential Occupancy does; any other People load
      # is people per m² × floor area. Nil while a value it needs is missing.
      def people(program, zone, dwelling_counts:, dwelling_area_m2:, presence_mean:)
        load = program.fetch("people")
        return per_area(load["people_per_area"], zone.floor_area_m2) unless load["rule"]

        occupants = dwelling_counts && dwelling_counts["occupants"]
        return nil if occupants.nil? || presence_mean.nil? || !presence_mean.positive? ||
                      !dwelling_area_m2&.positive?

        occupants / presence_mean * zone.floor_area_m2 / dwelling_area_m2
      end

      # Peak lighting in a Zone, W. The Phius interior rule (honeybee-ph `phius_residential.lighting_interior`)
      # gives each Dwelling's kWh a year over its iCFA and units, and the lighting Schedule's full-load hours turn it
      # into watts, shared by iCFA; any other Lighting load is W per m² × floor area.
      def lighting(program, zone, units:, dwelling_icfa_m2:, schedule_mean:)
        load = program.fetch("lighting")
        return per_area(load["watts_per_area"], zone.floor_area_m2) unless load["rule"]
        return nil if units.nil? || schedule_mean.nil? || !schedule_mean.positive? || !dwelling_icfa_m2&.positive?

        kwh = lighting_interior_kwh(dwelling_icfa_m2 * FT2_PER_M2, load.fetch("high_efficacy_fraction"), units)
        kwh * 1000.0 / (schedule_mean * HOURS_PER_YEAR) * zone.icfa_m2 / dwelling_icfa_m2
      end

      # honeybee-ph 1.33.68 `phius_residential.lighting_interior`: kWh a year.
      def lighting_interior_kwh(floor_area_ft2, high_efficacy_fraction, units)
        share = 0.2 + 0.8 * (4 - 3 * high_efficacy_fraction) / 3.7
        share * (455 * units + 0.8 * floor_area_ft2) * 0.8
      end

      # A Zone's ventilation, m³/h, and its source. Detailed: the larger of its Spaces' supply and extract sums.
      # By Program: the Program's four terms summed, per person over the peak people, per m² of floor, per Zone and
      # air changes over the net volume (F4a-10); nil when the Program sets none of them.
      def ventilation(program, zone, people:)
        if zone.airflow_mode == "detailed"
          return { "m3h" => [zone.supply_m3h.to_f, zone.extract_m3h.to_f].max, "source" => "detailed" }
        end

        load = program.fetch("ventilation")
        terms = %w[flow_per_person flow_per_area flow_per_zone air_changes_per_hour].map { |key| load[key] }
        return { "m3h" => nil, "source" => "by_program" } if terms.all?(&:nil?)

        per_person, per_area, per_zone, ach = terms.map(&:to_f)
        # A rate per person over people still unknown is unknown, not zero.
        return { "m3h" => nil, "source" => "by_program" } if people.nil? && per_person.positive?

        m3s = (per_person * people.to_f) + (per_area * zone.floor_area_m2) + per_zone +
              (ach * zone.net_volume_m3.to_f / 3600.0)
        { "m3h" => m3s * 3600.0, "source" => "by_program" }
      end

      def per_area(value, area_m2)
        value && value * area_m2
      end

      # ---------------------------------------------------------------- Segment

      # A Segment's heating and cooling set points, °C, from its Zones' Programs: each a constant or a temperature
      # Schedule's value. `agree` is false when the Zones' Programs give more than one pair.
      def set_points(programs, schedules)
        pairs = programs.map do |program|
          load = program.fetch("setpoint")
          %w[heating cooling].map do |side|
            schedule = schedules[load["#{side}_schedule_id"]]
            schedule ? schedule["value_c"] : load["#{side}_c"]
          end
        end.uniq
        heating, cooling = pairs.first || [nil, nil]
        { "heating_c" => heating, "cooling_c" => cooling, "agree" => pairs.length < 2 }
      end
    end
  end
end
