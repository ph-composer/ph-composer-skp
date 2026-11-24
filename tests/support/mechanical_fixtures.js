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
    slots: { ventilator_id: item ? item.id : null }, payload_status: item ? "understood" : null,
    items: item ? [{ slot: "ventilator_id", id: item.id, name: item.name }] : [], findings: [] };
}
var ERV1 = { id: "vnt_AAAAAAAAAAAA", name: "ERV-1" }, ERV2 = { id: "vnt_BBBBBBBBBBBB", name: "ERV-2" };
var ERV3 = { id: "vnt_CCCCCCCCCCCC", name: "ERV-3" };

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
  sections["ph_composer.zones.options"] = { status: "completed", value: { building_segments: [
    { id: SEGMENT, values: { name: "Apartments", colour: "#1F7478" } }], levels: [], default_segment_id: SEGMENT,
  adoption: { required: false, sources: [] } } };
  sections["ph_composer.colour_by.legend"] = { status: "completed", value: { mode: null, rows: [], modes: [
    { name: PREFIX + "by_ventilator", label: "Ventilator", entity_kind: "zone", group: null }] } };
  return { session: "session", revision: 1, sections: sections,
    ui: { activeTab: "mechanical", actionResult: null, viewResults: {}, queryResults: {} } };
}
module.exports = { PREFIX: PREFIX, ZONES: ZONES, ERV1: ERV1, ERV2: ERV2, ERV3: ERV3, SEGMENT: SEGMENT,
  state: state };
