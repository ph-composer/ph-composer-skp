# frozen_string_literal: true

module PhComposer
  module Climate
    # Schema pieces the Climate declarations share: what a site read, a design-temperature read and the limit
    # check return.
    module Shapes
      extend SchemaShapes

      NONE = object({}).freeze
      ID = { "type" => "string" }.freeze
      SITE_STATE = { "type" => "string", "enum" => %w[not_set set],
                     "description" => "set when latitude, longitude and elevation are all present." }.freeze
      DESIGN_STATE = { "type" => "string", "enum" => %w[not_set incomplete set],
                       "description" => "incomplete when one of the two design temperatures is present." }.freeze
      WARNING = { "type" => %w[string null], "enum" => [Settings::CROSSED, nil],
                  "description" => "#{Settings::CROSSED} when heating is at or above cooling; the values still " \
                                   "save." }.freeze
      SITE = with(Settings::SITE_VALUES,
                  "climate_zone_label" => { "type" => %w[string null], "enum" => ClimateZones::LABELS.values + [nil],
                                            "description" => "The zone as the panel and the Export report show " \
                                                             "it; null when unset." },
                  "state" => SITE_STATE).freeze
      DESIGN_TEMPERATURES = with(Settings::DESIGN_VALUES,
                                 "state" => DESIGN_STATE,
                                 "warning" => WARNING).freeze
      VERDICT = { "type" => "string", "enum" => %w[pass fail not_checked],
                  "description" => "pass at or inside both Phius limits, 50 miles and 400 feet; not_checked " \
                                   "gives its reason." }.freeze
      LIMIT_CHECK = object({
        "verdict" => VERDICT,
        "reason" => { "type" => %w[string null], "enum" => ["no_site", "no_station_coordinates", nil],
                      "description" => "Why the check did not run; null when it did." },
        "distance_km" => { "type" => %w[number null], "x-unit" => "km",
                           "description" => "Great-circle distance from the site to the station." },
        "elevation_difference_m" => { "type" => %w[number null], "x-unit" => "m",
                                      "description" => "The site's elevation less the station's, as a magnitude." },
        "distance_ok" => { "type" => %w[boolean null] }, "elevation_ok" => { "type" => %w[boolean null] }
      }, :description => "The Phius limit check, worked out from the site and the station each time and never " \
                         "stored.").freeze
      LIMIT_CHECK_OR_NULL = LIMIT_CHECK.merge("type" => %w[object null],
                                              "description" => "The Phius limit check; null with no climate.")
                                       .freeze
      SITE_UPDATE = with(SITE, "limit_check" => LIMIT_CHECK_OR_NULL).freeze
      GEOLOCATION = object({
        "geolocated" => { "type" => "boolean",
                          "description" => "true when SketchUp reports the Model as geolocated " \
                                           "(Model#georeferenced?)." },
        "latitude_deg" => { "type" => %w[number null], "x-unit" => "deg",
                            "description" => "SketchUp's latitude; null when the Model is not geolocated." },
        "longitude_deg" => { "type" => %w[number null], "x-unit" => "deg",
                             "description" => "SketchUp's longitude; null when the Model is not geolocated." },
        "hours_from_utc" => { "type" => %w[integer null], "x-unit" => "h",
                              "description" => "Always null for now: what SketchUp's time zone offset holds after " \
                                               "Add Location is not yet measured, and it is never guessed from " \
                                               "the longitude." }
      }, :description => "What SketchUp reports for the Model's geolocation. There is no elevation: SketchUp " \
                         "exposes none.").freeze
      PROPOSED_SITE = object(Settings::SITE_VALUES.fetch("properties").slice(*Settings::LOCATION_FIELDS)).freeze
    end
  end
end
