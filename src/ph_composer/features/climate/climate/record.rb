# frozen_string_literal: true

module PhComposer
  module Climate
    # Builds the values of the climate record, with the provenance rewritten from them in the same step, so
    # the stored source type and list of edited values can never disagree with the values. Pure: no SketchUp
    # constant, and every value it returns is a separate object from what it was given.
    module Record
      # honeybee-ph's provenance fields the Model never fills: no version or conversion is known, and whether a
      # source is approved for certification is left unknown. Both data flags are true, since a Phius station
      # file and the typed grid carry monthly and peak-load values alike.
      PROVENANCE_DEFAULTS = {
        "dataset_name" => nil, "station_name" => nil, "state" => nil, "source_name" => nil,
        "source_version" => nil, "source_checksum" => nil, "conversion_method" => nil,
        "conversion_method_version" => nil, "is_certification_approved" => nil,
        "monthly_data_available" => true, "peak_load_data_available" => true
      }.freeze

      module_function

      # A station climate from a parsed Phius station file and where it came from. `parsed` holds name,
      # latitude_deg, longitude_deg, elevation_m, daily_temp_swing_k, monthly and peak_loads in the record's
      # shape, and wind_speed_january_m_s and wind_speed_july_m_s; `source` holds dataset_name, state and the
      # file's SHA-256 as checksum. The wind speed starts as the mean of January and July, and the values are
      # copied into `as_read` as separate objects.
      def from_station(parsed, source)
        read = {
          "station_elevation_m" => parsed.fetch("elevation_m"),
          "daily_temp_swing_k" => parsed.fetch("daily_temp_swing_k"),
          "monthly" => parsed.fetch("monthly"), "peak_loads" => parsed.fetch("peak_loads")
        }
        identity = {
          "dataset_name" => source.fetch("dataset_name"), "station_name" => parsed.fetch("name"),
          "state" => source.fetch("state"), "source_checksum" => source.fetch("checksum"),
          "source_name" => "#{source.fetch('dataset_name')}: #{parsed.fetch('name')}"
        }
        values = DeepCopy.call(read).merge(
          "name" => parsed.fetch("name"), "origin" => "station",
          "station_latitude_deg" => parsed.fetch("latitude_deg"),
          "station_longitude_deg" => parsed.fetch("longitude_deg"),
          "wind_speed_m_s" => mean(parsed.fetch("wind_speed_january_m_s"), parsed.fetch("wind_speed_july_m_s")),
          "as_read" => DeepCopy.call(read), "provenance" => PROVENANCE_DEFAULTS.merge(identity)
        )
        with_provenance(values)
      end

      # A climate entered by hand from the editable fields (Schema::EDITABLE): no file, so no as-read copy.
      def hand(editable)
        values = DeepCopy.call(editable).merge("origin" => "hand", "as_read" => nil,
                                               "provenance" => PROVENANCE_DEFAULTS.dup)
        with_provenance(values)
      end

      # `values` with the editable fields replaced; the origin, the as-read copy and the file's identity stay.
      def with_values(values, editable)
        with_provenance(DeepCopy.call(values).merge(DeepCopy.call(editable)))
      end

      # `values` with every value the file read copied back over it. Wind speed is not one of them.
      def restored(values)
        with_provenance(DeepCopy.call(values).merge(DeepCopy.call(values.fetch("as_read"))))
      end

      # The provenance as the values make it: a station is phius_approved until a value differs from its file,
      # and user_defined after; a climate entered by hand is user_defined and named as typed. The assumptions
      # carry what honeybee-ph's Climate has no field for: the station's coordinates and the edited values.
      def with_provenance(values)
        edited = Edits.cells(values)
        station = values.fetch("origin") == "station"
        provenance = values.fetch("provenance").merge(
          "source_type" => station && edited.empty? ? Schema::APPROVED : Schema::USER_DEFINED,
          "assumptions" => { "ph_composer" => {
            "station_latitude_deg" => values.fetch("station_latitude_deg"),
            "station_longitude_deg" => values.fetch("station_longitude_deg"), "edited_values" => edited
          } }
        )
        provenance["source_name"] = values.fetch("name") unless station
        values.merge("provenance" => provenance)
      end

      def mean(january, july)
        january.nil? || july.nil? ? nil : (january + july) / 2.0
      end
    end
  end
end
