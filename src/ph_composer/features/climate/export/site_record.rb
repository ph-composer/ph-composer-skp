# frozen_string_literal: true

module PhComposer
  module Climate
    # The one record the Site export section writes, and the findings that go with it, from the site, the
    # design temperatures and the climate's values (CONTRACTS section 7). Ruby decides everything here: the
    # Python section builds honeybee-ph objects from this record and computes nothing. Pure: no SketchUp
    # constant.
    #
    # A part the record does not carry is null, and honeybee-ph supplies its own default for it, as its
    # Grasshopper components do when nothing is connected (E1, E2):
    #
    #   the Model has                     location   climate    left out        finding
    #   no site, no climate               null       null       null            none
    #   a site, no climate                written    null       null            none for the climate
    #   a site, an incomplete climate     written    null       incomplete      climate.incomplete
    #   a site, a complete climate        written    written    null            none for the climate
    #   a climate, no site                null       null       site_not_set    climate.site_not_set
    module SiteRecord
      ID = "Site"
      # The climate-zone code a site writes when its zone is unset: Not defined (J8).
      ZONE_NOT_DEFINED = 1
      # The Model's own provenance fields, which honeybee-ph's ClimateProvenance does not have.
      MODEL_PROVENANCE = %w[dataset_name station_name state].freeze
      COOLING_2_NOTE = "repeats cooling_load_1"
      SITE_NOT_SET = Stations::Operations::SITE_NOT_SET
      INCOMPLETE = "climate.incomplete"
      ZONE_NOT_SET = "climate.zone_not_set"
      UTC_OFFSET_NOT_SET = "climate.utc_offset_not_set"
      OUTSIDE_LIMITS = "climate.outside_phius_limits"
      NOT_CHECKED = "climate.not_checked"
      CODES = {
        INCOMPLETE => "The climate has values missing, so it was left out of the HBJSON; the site location " \
                      "was still written. The message counts what is missing.",
        ZONE_NOT_SET => "The site's climate zone is not set. It is exported as Not defined.",
        UTC_OFFSET_NOT_SET => "The site's hours from UTC are not set. They are exported empty.",
        OUTSIDE_LIMITS => "The attached station is farther from the site than Phius allows, by distance, " \
                          "elevation or both.",
        NOT_CHECKED => "The climate was entered by hand without station coordinates, so the Phius limit check " \
                       "was not made."
      }.freeze

      module_function

      # The record for `site` and `design` (the two settings' values) and `climate` (the climate record's
      # values, or nil when the Model has none).
      def call(site, design, climate)
        located = !site.fetch("latitude_deg").nil?
        left_out = climate && left_out_reason(located, climate)
        written = climate && left_out.nil?
        { "id" => ID,
          "location" => located ? location(site) : nil,
          "climate" => written ? values(climate) : nil,
          "climate_left_out" => left_out,
          "provenance" => written ? provenance(climate) : nil,
          "report" => report(site, design, climate) }
      end

      # `[code, message]` for each finding, all non-blocking. A Model with no climate gives none about the
      # climate (E1, E2); a site that is written says which of its own values it writes as unset.
      def findings(site, climate)
        located = !site.fetch("latitude_deg").nil?
        rows = located ? site_findings(site) : []
        return rows unless climate

        rows + climate_findings(located, site, climate)
      end

      def left_out_reason(located, climate)
        return "site_not_set" unless located

        Completeness.complete?(climate) ? nil : "incomplete"
      end

      def location(site)
        { "latitude_deg" => site.fetch("latitude_deg"), "longitude_deg" => site.fetch("longitude_deg"),
          "elevation_m" => site.fetch("elevation_m"),
          "climate_zone" => site.fetch("climate_zone") || ZONE_NOT_DEFINED,
          "hours_from_utc" => site.fetch("hours_from_utc") }
      end

      # The values honeybee-ph's Climate takes, with Cooling 2 added as a copy of Cooling 1 (J8, R5): a Phius
      # file has one cooling case, and honeybee-ph would otherwise write zeros for the second.
      def values(climate)
        peak_loads = DeepCopy.call(climate.fetch("peak_loads"))
        peak_loads["cool_2"] = DeepCopy.call(peak_loads.fetch("cool_1"))
        DeepCopy.call(climate.slice("name", "station_elevation_m", "daily_temp_swing_k", "wind_speed_m_s",
                                    "monthly"))
                .merge("peak_loads" => peak_loads)
      end

      # The stored provenance in honeybee-ph's fields, passed through as stored, with the line that
      # says Cooling 2 repeats Cooling 1, since export adds that case.
      def provenance(climate)
        stored = DeepCopy.call(climate.fetch("provenance")).reject { |key, _| MODEL_PROVENANCE.include?(key) }
        stored.fetch("assumptions").fetch("ph_composer")["cooling_load_2"] = COOLING_2_NOTE
        stored
      end

      # What the Export report's climate section shows (board 18), which the Python section passes to the
      # result unchanged: the climate's identity even when it is left out, so the report can name what was
      # left out and why.
      def report(site, design, climate)
        { "climate" => climate && identity(climate),
          "missing_values" => climate ? missing_count(climate) : 0,
          "limit_check" => climate && LimitCheck.call(site, climate),
          "edited_cells" => climate ? Edits.cells(climate) : [],
          "design_temperatures" => design.slice("heating_99_c", "cooling_1_c"),
          "design_temperature_source" => design.fetch("design_temperature_source") }
      end

      def identity(climate)
        provenance = climate.fetch("provenance")
        { "name" => climate.fetch("name"), "origin" => climate.fetch("origin"),
          "dataset_name" => provenance.fetch("dataset_name"), "station_name" => provenance.fetch("station_name"),
          "state" => provenance.fetch("state") }
      end

      # Each missing value counted once: a row with no columns is a single value.
      def missing_count(climate)
        Completeness.missing(climate).sum { |row| [row.fetch("columns").length, 1].max }
      end

      def site_findings(site)
        rows = []
        if site.fetch("climate_zone").nil?
          rows << [ZONE_NOT_SET, "The site's climate zone is not set. It is exported as Not defined; set it " \
                                 "in Climate, Site location."]
        end
        if site.fetch("hours_from_utc").nil?
          rows << [UTC_OFFSET_NOT_SET, "Hours from UTC is not set. It is exported empty; set it in Climate, " \
                                       "Site location."]
        end
        rows
      end

      def climate_findings(located, site, climate)
        rows = []
        unless located
          rows << [SITE_NOT_SET, "The site's latitude, longitude and elevation are not set, so the climate " \
                                 "was left out of the HBJSON. Set the site location in Climate, then export " \
                                 "again."]
        end
        missing = missing_count(climate)
        unless missing.zero?
          rows << [INCOMPLETE, "The climate has #{missing} #{missing == 1 ? 'value' : 'values'} missing, so it " \
                               "was left out of the HBJSON. Complete it in Climate, then export again."]
        end
        rows + limit_findings(LimitCheck.call(site, climate))
      end

      def limit_findings(check)
        case check.fetch("verdict")
        when "fail"
          [[OUTSIDE_LIMITS, "The climate station is outside the Phius limits of 80 km (50 mi) and 122 m " \
                            "(400 ft) from the site."]]
        when "not_checked"
          return [] unless check.fetch("reason") == "no_station_coordinates"

          [[NOT_CHECKED, "Phius limit check: not checked, entered by hand without station coordinates."]]
        else []
        end
      end
    end
  end
end
