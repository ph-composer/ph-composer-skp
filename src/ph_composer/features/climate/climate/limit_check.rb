# frozen_string_literal: true

module PhComposer
  module Climate
    # Phius's limits on how far a climate station may be from the site, worked out from the site and the
    # station each time and never stored, so a site change re-evaluates it. Pure: no SketchUp constant.
    #
    # Phius Certification Guidebook v25.1.0 (Phius 2024), section 1.4.4.2, pages 57 to 60: the dataset must
    # be "no more than 50 linear miles" from the project and have "no more than 400 ft difference in
    # elevation". Phius states the limits in miles and feet, so they are held here as their exact SI
    # conversions; at or inside both passes. New York City's exception is not modelled.
    module LimitCheck
      DISTANCE_LIMIT_KM = 80.4672 # 50 mi x 1.609344 km/mi
      ELEVATION_LIMIT_M = 121.92 # 400 ft x 0.3048 m/ft
      EARTH_RADIUS_KM = 6371.0088 # the mean radius

      module_function

      # The verdict for `site` (the site's latitude_deg, longitude_deg and elevation_m, any of them null) and
      # the climate's values: `{ verdict, reason, distance_km, elevation_difference_m, distance_ok,
      # elevation_ok }`. `not_checked` gives a reason and nulls: no_station_coordinates for a climate typed
      # without them, which no site can repair, else no_site.
      def call(site, climate)
        station = climate.values_at("station_latitude_deg", "station_longitude_deg")
        return not_checked("no_station_coordinates") if station.include?(nil)

        location = site.values_at("latitude_deg", "longitude_deg", "elevation_m")
        return not_checked("no_site") if location.include?(nil)

        distance = distance_km(location.fetch(0), location.fetch(1), station.fetch(0), station.fetch(1))
        compare(distance, (location.fetch(2) - climate.fetch("station_elevation_m")).abs)
      end

      # The verdict for a distance and an elevation difference already worked out.
      def compare(distance_km, elevation_difference_m)
        distance_ok = distance_km <= DISTANCE_LIMIT_KM
        elevation_ok = elevation_difference_m <= ELEVATION_LIMIT_M
        { "verdict" => distance_ok && elevation_ok ? "pass" : "fail", "reason" => nil,
          "distance_km" => distance_km, "elevation_difference_m" => elevation_difference_m,
          "distance_ok" => distance_ok, "elevation_ok" => elevation_ok }
      end

      def not_checked(reason)
        { "verdict" => "not_checked", "reason" => reason, "distance_km" => nil, "elevation_difference_m" => nil,
          "distance_ok" => nil, "elevation_ok" => nil }
      end

      # The great-circle distance between two points in decimal degrees, by the haversine formula on a sphere.
      def distance_km(latitude_a, longitude_a, latitude_b, longitude_b)
        phi_a = radians(latitude_a)
        phi_b = radians(latitude_b)
        half_dphi = (phi_b - phi_a) / 2
        half_dlambda = radians(longitude_b - longitude_a) / 2
        h = (Math.sin(half_dphi)**2) + (Math.cos(phi_a) * Math.cos(phi_b) * (Math.sin(half_dlambda)**2))
        2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt([h, 1.0].min))
      end

      def radians(degrees)
        degrees * Math::PI / 180
      end
    end
  end
end
