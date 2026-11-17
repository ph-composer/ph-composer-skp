# frozen_string_literal: true

require_relative "../../core/model_settings"

module PhComposer
  module Climate
    # The site and the design temperatures: two Model settings dictionaries, one per public update, because a
    # settings proposal guards its whole dictionary and each update guards only its own fields. Every field is
    # nullable and starts null; reads never write.
    module Settings
      LOCATION_FIELDS = %w[latitude_deg longitude_deg elevation_m].freeze

      SITE_DEFAULTS = {
        "latitude_deg" => nil, "longitude_deg" => nil, "elevation_m" => nil, "climate_zone" => nil,
        "hours_from_utc" => nil
      }.freeze
      SITE_VALUES = SchemaShapes.object({
        "latitude_deg" => { "type" => %w[number null], "minimum" => -90, "maximum" => 90, "x-unit" => "deg",
                            "description" => "Decimal degrees, north positive; null until the site is set." },
        "longitude_deg" => { "type" => %w[number null], "minimum" => -180, "maximum" => 180, "x-unit" => "deg",
                             "description" => "Decimal degrees, east positive; null until the site is set." },
        "elevation_m" => { "type" => %w[number null], "x-unit" => "m",
                           "description" => "Elevation above sea level; null until the site is set." },
        "climate_zone" => { "type" => %w[integer null], "enum" => ClimateZones::CODES + [nil],
                            "description" => "The WUFI-Passive climate-zone code: 1 Not defined, 11 to 18 for " \
                                             "US zones 1 to 8, 141 for 4C; null when unset." },
        "hours_from_utc" => { "type" => %w[integer null], "minimum" => -12, "maximum" => 14, "x-unit" => "h",
                              "description" => "The offset from UTC as typed; never derived from longitude. Null " \
                                               "when unset." }
      }).freeze

      DESIGN_DEFAULTS = { "heating_99_c" => nil, "cooling_1_c" => nil, "design_temperature_source" => nil }.freeze
      DESIGN_VALUES = SchemaShapes.object({
        "heating_99_c" => { "type" => %w[number null], "x-unit" => "degC",
                            "description" => "The ASHRAE 99% heating dry bulb; null when unset." },
        "cooling_1_c" => { "type" => %w[number null], "x-unit" => "degC",
                           "description" => "The ASHRAE 1% cooling dry bulb; null when unset." },
        "design_temperature_source" => { "type" => %w[string null],
                                         "description" => "Where the two values come from, as free text; null " \
                                                          "when there is no note." }
      }).freeze
      CROSSED = "climate.heating_not_below_cooling"

      SITE = ModelSettings.new(:dictionary => "ph_composer.climate_site", :defaults => SITE_DEFAULTS,
                               :schema => SITE_VALUES, :label => "Site location", :step_name => "update_climate_site",
                               :affected => [{ "kind" => "climate_site", "id" => FEATURE_ID,
                                               "change" => "updated" }]) do |values|
        given = LOCATION_FIELDS.reject { |field| values[field].nil? }
        unless given.empty? || given.length == LOCATION_FIELDS.length
          "latitude, longitude and elevation are set together; only #{given.join(', ')} given"
        end
      end
      DESIGN_TEMPERATURES = ModelSettings.new(:dictionary => "ph_composer.climate_design_temperatures",
                                              :defaults => DESIGN_DEFAULTS, :schema => DESIGN_VALUES,
                                              :label => "Design temperatures",
                                              :step_name => "update_climate_design_temperatures",
                                              :affected => [{ "kind" => "climate_design_temperatures",
                                                              "id" => FEATURE_ID, "change" => "updated" }])

      module_function

      def site(model)
        describe_site(SITE.read(model))
      end

      def design_temperatures(model)
        describe_design_temperatures(DESIGN_TEMPERATURES.read(model))
      end

      # The five site fields, the zone's label and the site state: set when latitude, longitude and
      # elevation are all present, which validation makes the same as latitude being present.
      def describe_site(values)
        values.merge("climate_zone_label" => ClimateZones.label(values.fetch("climate_zone")),
                     "state" => values.fetch("latitude_deg").nil? ? "not_set" : "set")
      end

      # The two values, the note, the state (not_set, incomplete or set) and the warning code when heating
      # is at or above cooling, which still saves.
      def describe_design_temperatures(values)
        heating, cooling = values.values_at("heating_99_c", "cooling_1_c")
        given = [heating, cooling].compact.length
        values.merge("state" => %w[not_set incomplete set].fetch(given),
                     "warning" => given == 2 && heating >= cooling ? CROSSED : nil)
      end

      # Set Location: all five site fields together, guarded by the five last read.
      def propose_site(request, proposal, values:, expected_values:)
        describe_site(SITE.propose(request.model, proposal, :values => values, :expected_values => expected_values))
      end

      # Any of the three design-temperature fields; each field given is guarded by its expected value, and
      # the fields not given keep what is stored.
      def propose_design_temperatures(request, proposal, values:, expected_values:)
        model = request.model
        before = DESIGN_TEMPERATURES.read(model)
        unless values.keys.sort == expected_values.keys.sort && !values.empty?
          raise CodedError.new("validation.failed", "Design temperatures need at least one value, and " \
                                                    "expected_values must name the same fields. Nothing was written.")
        end
        unless expected_values.all? { |field, value| before.fetch(field) == value }
          raise CodedError.new("target.changed", "Design temperatures changed since they were read. Nothing was " \
                                                 "written.")
        end

        describe_design_temperatures(DESIGN_TEMPERATURES.propose(model, proposal, :values => before.merge(values),
                                                                                  :expected_values => before))
      rescue StandardError => error
        proposal.refuse(error)
        raise
      end
    end
  end
end
