/* Unit descriptors for stored fields: the quantity the units core formats and parses, and the unit the value
   is stored in. One frozen descriptor per stored unit; a screen adds its own label, dimension scope and blank
   or zero rules with `fields.with`. */
PhComposerUI.define("fields", [], function () {
  "use strict";
  function descriptor(quantity, unit) { return Object.freeze({ quantity: quantity, unit: unit }); }

  var FRACTION = descriptor("fraction", "1");
  var LENGTH_M = descriptor("length", "m");
  var LENGTH_MM = descriptor("length_mm", "mm");
  /* A length stored in metres but shown and entered in millimetres (a narrow width in a metre record). */
  var WIDTH_M_AS_MM = descriptor("length_mm", "m");
  var AREA_M2 = descriptor("area", "m2");
  var VOLUME_M3 = descriptor("volume", "m3");
  var AIRFLOW_M3H = descriptor("airflow", "m3_h");
  var U_VALUE = descriptor("u_value", "w_m2k");
  var R_VALUE = descriptor("thermal_resistance", "m2k_w");
  var CONDUCTIVITY = descriptor("conductivity", "w_mk");
  var LINEAR_PSI = descriptor("linear_psi", "w_mk");
  var HEAT_LOSS = descriptor("heat_loss_rate", "w_k");
  var DENSITY = descriptor("density", "kg_m3");
  var SPECIFIC_HEAT = descriptor("specific_heat", "j_kgk");
  var TEMPERATURE_C = descriptor("temperature", "c");
  var TEMPERATURE_DIFFERENCE_K = descriptor("temperature_difference", "k");
  var IRRADIATION_KWH_M2 = descriptor("irradiation", "kwh_m2");
  var IRRADIANCE_W_M2 = descriptor("irradiance", "w_m2");
  var WIND_SPEED_M_S = descriptor("wind_speed", "m_s");
  var DISTANCE_KM = descriptor("distance", "km");
  var ELECTRIC_EFFICIENCY = descriptor("electric_efficiency", "wh_m3");
  var VOLUME_L = descriptor("volume_l", "l");
  var POWER_W = descriptor("power", "w");
  /* A pump's electrical input in W and its operation in kilohours a year, unconverted under IP. */
  var ELECTRIC_POWER_W = descriptor("electric_power", "w");
  var KILOHOURS = descriptor("kilohours", "kh");
  /* A fan's runtime in minutes a year, unconverted under IP. */
  var ANNUAL_MINUTES = descriptor("annual_minutes", "min");
  /* A recirculation pipe's hours a day, unconverted under IP. */
  var HOURS_PER_DAY = descriptor("hours_per_day", "h_day");
  /* A fraction from 0 to 1, read and entered as a percentage. */
  var PERCENT = descriptor("percent", "1");
  /* A heat pump's rated capacity in kW, shown kBtu/h under IP. */
  var CAPACITY_KW = descriptor("capacity", "kw");

  /* A copy of a descriptor with a screen's own settings (label, scope, allowBlank, allowZero). */
  function withSettings(base, settings) {
    return Object.assign({ quantity: base.quantity, unit: base.unit }, settings);
  }

  return { FRACTION: FRACTION, LENGTH_M: LENGTH_M, LENGTH_MM: LENGTH_MM, WIDTH_M_AS_MM: WIDTH_M_AS_MM, AREA_M2: AREA_M2,
    VOLUME_M3: VOLUME_M3, AIRFLOW_M3H: AIRFLOW_M3H, U_VALUE: U_VALUE, R_VALUE: R_VALUE, CONDUCTIVITY: CONDUCTIVITY,
    LINEAR_PSI: LINEAR_PSI, HEAT_LOSS: HEAT_LOSS, DENSITY: DENSITY, SPECIFIC_HEAT: SPECIFIC_HEAT,
    TEMPERATURE_C: TEMPERATURE_C, TEMPERATURE_DIFFERENCE_K: TEMPERATURE_DIFFERENCE_K,
    IRRADIATION_KWH_M2: IRRADIATION_KWH_M2, IRRADIANCE_W_M2: IRRADIANCE_W_M2, WIND_SPEED_M_S: WIND_SPEED_M_S,
    DISTANCE_KM: DISTANCE_KM, ELECTRIC_EFFICIENCY: ELECTRIC_EFFICIENCY, VOLUME_L: VOLUME_L, POWER_W: POWER_W,
    PERCENT: PERCENT, CAPACITY_KW: CAPACITY_KW, ELECTRIC_POWER_W: ELECTRIC_POWER_W, KILOHOURS: KILOHOURS,
    ANNUAL_MINUTES: ANNUAL_MINUTES, HOURS_PER_DAY: HOURS_PER_DAY,
    with: withSettings };
});
