# frozen_string_literal: true

module PhComposer
  module Climate
    # What SketchUp reports for a Model's geolocation, read for Set Location's Read from SketchUp Geolocation.
    # It reads and never writes, to SketchUp or to the Model.
    #
    # Measured on SketchUp 2026 (owed check 4, context/SKETCHUP_HOST_BEHAVIOR.md, "Geolocation"): a Model never
    # geolocated still carries its template's location in ShadowInfo (Boulder, Colorado, in the default
    # template), so ShadowInfo alone cannot tell a real location from none. Model#georeferenced? can, so nothing
    # is read unless it answers true. It follows the GeoReference dictionary's UsesGeoReferencing flag; that Add
    # Location or a manual location sets that flag, and writes ShadowInfo's latitude and longitude, is not yet
    # measured on the host (the owed check's item 2 was an API stand-in). SketchUp exposes no elevation.
    # TZOffset is a Float that holds whatever was written to it, and what Add Location writes there is not yet
    # measured, so hours from UTC is not read: J2 forbids an offset that may be a guess from the longitude.
    module Geolocation
      NONE = { "geolocated" => false, "latitude_deg" => nil, "longitude_deg" => nil, "hours_from_utc" => nil }.freeze

      module_function

      def read(model)
        return NONE unless model.respond_to?(:georeferenced?) && model.georeferenced?

        shadow = model.shadow_info
        latitude = degrees(shadow["Latitude"], 90)
        longitude = degrees(shadow["Longitude"], 180)
        return NONE if latitude.nil? || longitude.nil?

        { "geolocated" => true, "latitude_deg" => latitude, "longitude_deg" => longitude, "hours_from_utc" => nil }
      end

      def degrees(value, limit)
        return nil unless value.is_a?(Numeric) && value.to_f.finite? && value.abs <= limit

        value.to_f
      end
    end
  end
end
