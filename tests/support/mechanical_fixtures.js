"use strict";
/* The Mechanical tab's sections, in the shapes the Ruby registrations publish (features/mechanical/declarations/):
   the reference model's ERV-1 serving Zone A, ERV-2 serving Zone B in a Group, and ERV-3 serving nothing. */
var PREFIX = "ph_composer.mechanical.";
var SEGMENT = "bsg_AAAAAAAAAAAA";
function zoneRef(letter, path) { return { zone_id: "zon_" + letter.repeat(12), zone_path: path }; }
var ZONES = { A: zoneRef("A", [1000]), B: zoneRef("B", [8000, 2000]), C: zoneRef("C", [3000]),
  D: zoneRef("D", [4000]) };

function ventilator(id, name, values, zones, balance) {
  return { id: id, kind: PREFIX + "ventilator", schema_version: 1, user_data: {}, extension_data: {},
    extension_status: {}, export_ready: true, export_blockers: [], findings: [],
    values: Object.assign({ name: name, notes: "", datasheet_links: [], source: { kind: "manual" }, quantity: 1,
      sensible_heat_recovery: 0, latent_heat_recovery: 0, electric_efficiency_wh_m3: 0.55,
      frost_protection_reqd: true, temperature_below_defrost_used_c: -5, in_conditioned_space: true }, values),
    zones: zones.map(function (letter) {
      return { zone_id: ZONES[letter].zone_id, reference: ZONES[letter], name: "Zone " + letter };
    }), balance: balance };
}
/* `segment`: the Segment's id, null for No Building Segment, or { legacy } for a Zone not yet adopted. */
function servesRow(letter, item, segment) {
  var legacy = segment && segment.legacy;
  var id = segment === undefined ? SEGMENT : legacy ? null : segment;
  return { zone_id: ZONES[letter].zone_id, reference: ZONES[letter], name: "Zone " + letter,
    building_segment_id: id, building_segment: legacy || (id ? "Apartments" : null),
    slots: { ventilator_id: item ? item.id : null, hot_water_system_id: null },
    payload_status: item ? "understood" : null,
    items: item ? [{ slot: "ventilator_id", id: item.id, name: item.name }] : [], findings: [] };
}
var ERV1 = { id: "vnt_AAAAAAAAAAAA", name: "ERV-1" }, ERV2 = { id: "vnt_BBBBBBBBBBBB", name: "ERV-2" };
var ERV3 = { id: "vnt_CCCCCCCCCCCC", name: "ERV-3" };
/* Hot water: HWS-1 serves Zone C with 8 tap points and calculation method 2, which the pinned honeybee-ph cannot
   carry; HWS-2 serves nothing. H-E (electric) and H-HP (annual heat pump) name HWS-1, as do T1 (storage, tank 1),
   T3 (buffer, the buffer slot) and T4 (buffer, no slot left). */
var HWS1 = { id: "hws_AAAAAAAAAAAA", name: "HWS-1" }, HWS2 = { id: "hws_BBBBBBBBBBBB", name: "HWS-2" };
var HE = { id: "hwh_AAAAAAAAAAAA", name: "H-E" }, HHP = { id: "hwh_BBBBBBBBBBBB", name: "H-HP" };
var T1 = { id: "hwt_AAAAAAAAAAAA", name: "T1" }, T3 = { id: "hwt_CCCCCCCCCCCC", name: "T3" };
var T4 = { id: "hwt_DDDDDDDDDDDD", name: "T4" };
function record(kind, item, values, extra) {
  return Object.assign({ id: item.id, kind: PREFIX + kind, schema_version: 1, user_data: {}, extension_data: {},
    extension_status: {}, export_ready: true, export_blockers: [], findings: [],
    values: Object.assign({ name: item.name, notes: "", datasheet_links: [], source: { kind: "manual" } }, values) },
  extra || {});
}
function finding(code, severity, message) {
  return { code: code, severity: severity, message: message, blocks_export: false };
}
function hotWater(sections) {
  sections[PREFIX + "hot_water_systems"] = { status: "completed", value: { unreadable: [], records: [
    record("hot_water_system", HWS1, { number_tap_points: 8, piping_calc_method: 2 }, { heater_count: 2,
      tank_count: 3,
      zones: [{ zone_id: ZONES.C.zone_id, reference: ZONES.C, name: "Zone C" }],
      findings: [finding("mechanical.method_not_exported", "info", "HWS-1 sets piping calculation method 2, and the " +
        "pinned honeybee-ph has no field for it, so the export leaves it out.")] }),
    record("hot_water_system", HWS2, {}, { heater_count: 0, tank_count: 0, zones: [],
      findings: [finding("mechanical.item_unserved", "warning",
        "HWS-2 serves no Zone, so nothing exports it.")] })] } };
  sections[PREFIX + "hot_water_heaters"] = { status: "completed", value: { unreadable: [], records: [
    record("hot_water_heater", HE, { hot_water_system_id: HWS1.id, variant: "electric", percent_coverage: 0.3,
      in_conditioned_space: true }),
    record("hot_water_heater", HHP, { hot_water_system_id: HWS1.id, variant: "heat_pump_annual",
      percent_coverage: 0.7, in_conditioned_space: false, total_system_perf_ratio: 2.5 })] } };
  function tank(item, role, slot, values, findings) {
    return record("hot_water_tank", item, Object.assign({ hot_water_system_id: HWS1.id, role: role,
      tank_type: "2-DHW ONLY", quantity: 1, in_conditioned_space: true, solar_connection: false, solar_losses_w: 0,
      storage_loss_rate_w_k: 0, storage_capacity_l: 300, standby_losses_w_k: 4, standby_fraction: 0.3, room_temp_c: 20,
      water_temp_c: 60 }, values), { slot: slot, findings: findings || [] });
  }
  sections[PREFIX + "hot_water_tanks"] = { status: "completed", value: { unreadable: [], records: [
    tank(T1, "storage", "tank_1"), tank(T3, "buffer", "tank_buffer", { storage_capacity_l: 80 }),
    tank(T4, "buffer", null, { storage_capacity_l: 80 }, [finding("mechanical.tank_unslotted", "warning",
      "T4 is a buffer tank with no free buffer slot on its System, so the export leaves it out.")])] } };
}

function state() {
  var sections = {};
  sections[PREFIX + "ventilators"] = { status: "completed", value: { records: [
    ventilator(ERV1.id, ERV1.name, { sensible_heat_recovery: 0.85, latent_heat_recovery: 0.6,
      electric_efficiency_wh_m3: 0.45, manufacturer: "Nordvent", model: "Q350" }, ["A"],
    { supply_m3h: 60, extract_m3h: 50, imbalanced: true, missing: null }),
    ventilator(ERV2.id, ERV2.name, { sensible_heat_recovery: 0.75, electric_efficiency_wh_m3: 0.35,
      frost_protection_reqd: false, in_conditioned_space: false, subsoil_heat_exchange_efficiency: 0.2 }, ["B"],
    { supply_m3h: 40, extract_m3h: 40, imbalanced: false, missing: null }),
    ventilator(ERV3.id, ERV3.name, {}, [], { supply_m3h: null, extract_m3h: null, imbalanced: false,
      missing: "It serves no Zone the export writes, so it moves no air." })], unreadable: [] } };
  sections[PREFIX + "serves"] = { status: "completed", value: { zones: [servesRow("A", ERV1), servesRow("B", ERV2),
    servesRow("C", null, null), servesRow("D", null, { legacy: "Old wing" })] } };
  var zoneC = sections[PREFIX + "serves"].value.zones[2];
  zoneC.slots.hot_water_system_id = HWS1.id;
  zoneC.payload_status = "understood";
  zoneC.items = [{ slot: "hot_water_system_id", id: HWS1.id, name: HWS1.name }];
  hotWater(sections);
  sections["ph_composer.zones.options"] = { status: "completed", value: { building_segments: [
    { id: SEGMENT, values: { name: "Apartments", colour: "#1F7478" } }], levels: [], default_segment_id: SEGMENT,
  adoption: { required: false, sources: [] } } };
  sections["ph_composer.colour_by.legend"] = { status: "completed", value: { mode: null, rows: [], modes: [
    { name: PREFIX + "by_ventilator", label: "Ventilator", entity_kind: "zone", group: null },
    { name: PREFIX + "by_hot_water_system", label: "Hot Water System", entity_kind: "zone", group: null }] } };
  return { session: "session", revision: 1, sections: sections,
    ui: { activeTab: "mechanical", actionResult: null, viewResults: {}, queryResults: {} } };
}
module.exports = { PREFIX: PREFIX, ZONES: ZONES, ERV1: ERV1, ERV2: ERV2, ERV3: ERV3, SEGMENT: SEGMENT,
  HWS1: HWS1, HWS2: HWS2, HE: HE, HHP: HHP, T1: T1, T3: T3, T4: T4, state: state };
