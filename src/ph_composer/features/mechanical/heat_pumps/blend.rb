# frozen_string_literal: true

module PhComposer
  module Mechanical
    module HeatPumps
      # One blended air-source heat pump from outdoor models and their unit counts, worked out as the Phius Heat Pump
      # Performance Estimator (v25.1.2) does, in pure Ruby over plain values. The estimator works in IP, so this does
      # too: capacities in kBtu/h, temperatures in F, airflow in cfm. `export` gives the SI values honeybee-ph's rated
      # monthly heat pump and its recirculation cooling take.
      #
      # Each row is one device type (one outdoor model) with the summed quantity of its outdoor units: the
      # estimator's "line items for each unique device type". Its SEER derating is not linear in the quantity, so
      # two rows of one model would not blend as one.
      #
      # The estimator's arithmetic is kept as it stands, so its result and this one agree, including where it reads
      # unusually. Each is noted where it happens:
      # - an HSPF row is weighted by its share of cooling capacity, not heating, and gives one value to both COPs;
      # - the HSPF derating's temperature term is linear, where FSEC-PF-413-04's form suggests a square;
      # - the SEER derating runs on the weighted SEER, choosing its branch by the rating as entered.
      # Fans and pumps tied to the heat pump are left out, so the monthly mean temperatures feed only the
      # Climate Information the estimator shows; the derating reads the two design temperatures.
      module Blend
        KBTUH_PER_KW = Units::BTU_H_PER_W
        M3H_PER_CFM = 60.0 / Units::FT3_PER_M3
        # The estimator's Btu/Wh, which turns an HSPF, EER or SEER into a COP.
        BTU_PER_WH = 3.412
        # The estimator's per-system cooling limit, which the estimator splits above; PH-Composer does not.
        SYSTEM_LIMIT_KBTUH = 682.0
        CFM_PER_TON = 300.0
        KBTUH_PER_TON = 12.0
        RATING_17F = 17.0
        RATING_47F = 47.0
        # honeybee-ph's rated monthly heat pump's two rating temperatures, 17 F and 47 F.
        AMBIENT_1_C = -8.333
        AMBIENT_2_C = 8.333
        # The cooling coil's minimum temperature PH-Composer writes, honeybee-ph's own default.
        MIN_COIL_TEMP_C = 12.0

        Row = Struct.new(:id, :name, :quantity, :equipment, keyword_init: true)
        # The Model's climate: twelve monthly mean air temperatures and the ASHRAE 99% heating and 1% cooling dry
        # bulbs, all C.
        Climate = Struct.new(:monthly_air_c, :heating_99_c, :cooling_1_c, keyword_init: true)

        module_function

        # The blend of `rows` (Row values, each one outdoor model) under `climate`, as one Hash: the climate as the
        # estimator reads it, the performance rows, the weighted values, the totals, the inputs for the energy model
        # and the SI values for export.
        def call(rows, climate)
          climate_f = climate_information(climate)
          devices = rows.map { |row| device(row) }
          weighted = weigh(devices, climate_f)
          totals = totals(devices, weighted)
          { "climate" => climate_f, "devices" => devices, "weighted" => weighted, "totals" => totals,
            "energy_model" => energy_model(totals), "export" => export(totals) }
        end

        # ------------------------------------------------------------------ climate

        def fahrenheit(celsius)
          (celsius * 1.8) + 32.0
        end

        # The design temperatures in F and the estimator's heating months: a month whose mean is at or below 47 F
        # heats, and the shares of those months at or below 17 F and between 17 F and 47 F.
        def climate_information(climate)
          monthly = climate.monthly_air_c.map { |value| fahrenheit(value) }
          below_17 = monthly.count { |value| value <= RATING_17F }
          below_47 = monthly.count { |value| value > RATING_17F && value <= RATING_47F }
          months = below_17 + below_47
          { "heating_99_f" => fahrenheit(climate.heating_99_c), "cooling_1_f" => fahrenheit(climate.cooling_1_c),
            "monthly_air_f" => monthly, "heating_months" => months,
            "share_below_17f" => months.zero? ? 0.0 : below_17.fdiv(months),
            "share_below_47f" => months.zero? ? 0.0 : below_47.fdiv(months) }
        end

        # ------------------------------------------------------------------ performance data

        # One row of the estimator's performance data, in its units and with its data type labels.
        def device(row)
          values = row.equipment
          cooling = values["cooling_rating_mode"]
          { "id" => row.id, "name" => row.name, "quantity" => row.quantity,
            "heating_data_type" => heating_type(values), "capacity_17f_kbtuh" => kbtuh(values["heating_cap_17f_kw"]),
            "capacity_47f_kbtuh" => kbtuh(values["heating_cap_47f_kw"]),
            "cop_17f" => cop_pair?(values) ? values["cop_17f"] : nil,
            "cop_47f" => cop_pair?(values) ? values["cop_47f"] : nil,
            "hspf" => cop_pair?(values) ? nil : values["hspf_value"],
            "cooling_data_type" => cooling_type(values),
            "capacity_95f_kbtuh" => cooling ? kbtuh(values["cooling_cap_95f_kw"]) : 0.0,
            "eer" => cooling == "eer_seer" ? values["eer"] : nil,
            "seer" => cooling == "eer_seer" ? values["seer"] : nil,
            "ieer" => cooling == "ieer" ? values["ieer"] : nil }
        end

        def cop_pair?(values)
          values.fetch("heating_rating_mode") == "cop_pair"
        end

        def heating_type(values)
          return "COPs" if cop_pair?(values)

          values.fetch("hspf_version") == "hspf2" ? "HSPF2" : "HSPF"
        end

        def cooling_type(values)
          case values["cooling_rating_mode"]
          when "eer_seer" then values.fetch("seer_version") == "seer2" ? "EER2/SEER2" : "EER/SEER"
          when "ieer" then "IEER"
          end
        end

        def kbtuh(kilowatts)
          kilowatts.to_f * KBTUH_PER_KW
        end

        # ------------------------------------------------------------------ weighted values

        # Each device's weighted values: its shares of cooling capacity and of heating capacity at 17 F and 47 F,
        # then its share of each weighted rating. The sums of the COP columns are the blend's COPs.
        def weigh(devices, climate)
          cooling = sum(devices) { |device| device.fetch("quantity") * device.fetch("capacity_95f_kbtuh") }
          heating_17 = sum(devices) { |device| device.fetch("quantity") * device.fetch("capacity_17f_kbtuh") }
          heating_47 = sum(devices) { |device| device.fetch("quantity") * device.fetch("capacity_47f_kbtuh") }
          devices.map do |device|
            quantity = device.fetch("quantity")
            shares = { "recirc" => share(quantity * device.fetch("capacity_95f_kbtuh"), cooling),
                       "capacity_17f" => share(quantity * device.fetch("capacity_17f_kbtuh"), heating_17),
                       "capacity_47f" => share(quantity * device.fetch("capacity_47f_kbtuh"), heating_47) }
            { "id" => device.fetch("id"), "name" => device.fetch("name") }.merge(shares)
                                                                          .merge(heating(device, shares, climate))
                                                                          .merge(cooling(device, shares, climate))
          end
        end

        def share(part, whole)
          whole.positive? ? part / whole : 0.0
        end

        def sum(items, &block)
          items.sum(0.0, &block)
        end

        # A COP pair weighs each COP by its share of heating capacity at its temperature. An HSPF (an HSPF2 first
        # converted, x 1.1236 to one decimal) is derated for the 99% heating design temperature, then weighted by
        # the device's share of cooling capacity, as the estimator does, and gives one value to both COPs.
        def heating(device, shares, climate)
          if device.fetch("heating_data_type") == "COPs"
            return { "cop_17f" => device.fetch("cop_17f") * shares.fetch("capacity_17f"),
                     "cop_47f" => device.fetch("cop_47f") * shares.fetch("capacity_47f"),
                     "hspf" => nil, "derated_hspf" => nil }
          end

          hspf = device.fetch("hspf")
          hspf = (hspf * 1.1236).round(1) if device.fetch("heating_data_type") == "HSPF2"
          derated = derate_hspf(hspf, climate.fetch("heating_99_f")) * shares.fetch("recirc")
          { "cop_17f" => derated / BTU_PER_WH, "cop_47f" => derated / BTU_PER_WH, "hspf" => hspf,
            "derated_hspf" => derated }
        end

        # FSEC-PF-413-04's HSPF derating as the estimator writes it: its temperature term multiplies the design
        # temperature twice over, linearly.
        def derate_hspf(hspf, heating_99_f)
          base, linear, second, slope = hspf < 8.5 ? [0.1392, -0.00846, -0.0001074, 0.0228] :
                                                     [0.1041, -0.008862, -0.0001153, 0.02817]
          (1 - (base + (linear * heating_99_f) + (second * heating_99_f) + (slope * hspf))) * hspf
        end

        # An EER and SEER (EER2 and SEER2 first converted, each to one decimal) are weighted by the device's share
        # of cooling capacity; the weighted SEER is derated for the 1% cooling design temperature. An IEER is
        # weighted and not derated. The device's cooling COP is the mean of its EER and derated SEER, or its IEER,
        # over 3.412.
        def cooling(device, shares, climate)
          recirc = shares.fetch("recirc")
          eer = seer = derated = ieer = 0.0
          case device.fetch("cooling_data_type")
          when "EER/SEER", "EER2/SEER2"
            raw_eer = device.fetch("eer")
            raw_seer = device.fetch("seer")
            if device.fetch("cooling_data_type") == "EER2/SEER2"
              raw_eer = ((raw_eer * 1.0432) - 0.0018).round(1)
              raw_seer = ((raw_seer * 1.047) - 0.0004).round(1)
            end
            eer = raw_eer * recirc
            seer = raw_seer * recirc
            derated = derate_seer(seer, device.fetch("seer"), climate.fetch("cooling_1_f"))
          when "IEER"
            ieer = device.fetch("ieer") * recirc
          end
          { "eer" => eer, "seer" => seer, "derated_seer" => derated, "ieer" => ieer,
            "cop" => (((eer + derated) / 2.0) + ieer) / BTU_PER_WH }
        end

        # FSEC-PF-413-04's SEER derating as the estimator writes it: on the weighted SEER, its branch chosen by the
        # SEER as entered.
        def derate_seer(weighted, entered, cooling_1_f)
          base, slope, factor = entered < 13.5 ? [-0.5655, 0.005414, 0.01039] : [-0.5864, 0.005668, 0.01029]
          (1 - (base + (slope * cooling_1_f) + (factor * weighted))) * weighted
        end

        # ------------------------------------------------------------------ totals and results

        # Total capacity and input power for cooling and for heating at 17 F and 47 F, and the blend's COPs: the
        # sums of the weighted COP columns. An input power is nil where its COP is not positive.
        def totals(devices, weighted)
          capacity = lambda do |key|
            sum(devices) { |device| device.fetch("quantity") * device.fetch(key) }
          end
          cops = { "cooling" => sum(weighted) { |row| row.fetch("cop") },
                   "heating_17f" => sum(weighted) { |row| row.fetch("cop_17f") },
                   "heating_47f" => sum(weighted) { |row| row.fetch("cop_47f") } }
          capacities = { "cooling" => capacity.call("capacity_95f_kbtuh"),
                         "heating_17f" => capacity.call("capacity_17f_kbtuh"),
                         "heating_47f" => capacity.call("capacity_47f_kbtuh") }
          capacities.to_h do |key, total|
            cop = cops.fetch(key)
            [key, { "capacity_kbtuh" => total, "cop" => cop, "input_kbtuh" => cop.positive? ? total / cop : nil }]
          end
        end

        # The estimator's Inputs for Energy Model. Above SYSTEM_LIMIT_KBTUH it would split cooling over several
        # systems; `systems_needed` says how many, and every other value is for the one system PH-Composer exports.
        def energy_model(totals)
          cooling = totals.fetch("cooling").fetch("capacity_kbtuh")
          systems = cooling.positive? ? [(cooling / SYSTEM_LIMIT_KBTUH).ceil, 1].max : nil
          { "systems_needed" => systems, "cooling_coverage" => cooling.positive? ? 1.0 : nil,
            "min_coil_temp_f" => fahrenheit(MIN_COIL_TEMP_C),
            "flow_rate_cfm" => cooling / KBTUH_PER_TON * CFM_PER_TON, "cooling_capacity_kbtuh" => cooling,
            "cooling_cop" => totals.fetch("cooling").fetch("cop"), "heating_coverage" => 1.0,
            "cop_1" => totals.fetch("heating_17f").fetch("cop"), "ambient_1_f" => RATING_17F,
            "cop_2" => totals.fetch("heating_47f").fetch("cop"), "ambient_2_f" => RATING_47F }
        end

        # What honeybee-ph's PhHeatPumpRatedMonthly and its PhHeatPumpCoolingParams_Recirculation take, in SI: COPs
        # at -8.333 C and 8.333 C, full heating coverage, and recirculation cooling with the whole blended capacity
        # in kW and its airflow in m3/h, used only when the blend cools.
        def export(totals)
          cooling = totals.fetch("cooling")
          kbtuh = cooling.fetch("capacity_kbtuh")
          { "percent_coverage" => 1.0, "cop_1" => totals.fetch("heating_17f").fetch("cop"),
            "ambient_temp_1_c" => AMBIENT_1_C, "cop_2" => totals.fetch("heating_47f").fetch("cop"),
            "ambient_temp_2_c" => AMBIENT_2_C,
            "cooling" => { "used" => kbtuh.positive? && cooling.fetch("cop").positive?,
                           "percent_coverage" => 1.0, "capacity_kw" => kbtuh / KBTUH_PER_KW,
                           "flow_rate_m3_hr" => kbtuh / KBTUH_PER_TON * CFM_PER_TON * M3H_PER_CFM,
                           "annual_cop" => cooling.fetch("cop"), "min_coil_temp_c" => MIN_COIL_TEMP_C,
                           "single_speed" => false, "flow_rate_variable" => true } }
        end
      end
    end
  end
end
