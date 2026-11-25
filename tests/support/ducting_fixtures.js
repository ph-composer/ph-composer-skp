"use strict";
/* The ducting sections and reads, in the shapes features/ducting/declarations/ publishes, over the Mechanical
   fixtures and the ERV ducting case: DT-1 (round, 160 mm) and DT-2 (rectangular, 200 by 100 mm); Ducting groups DG-1
   (600) linked to ERV-1 and DG-2 (700) linked to ERV-2; ERV-1's runs 2.500 and 1.800 m, ERV-2's 2.500 m and 1.500 m
   at quantity 2; two selected lines in DG-1 and one outside every Ducting group. */
var mechanical = require("./mechanical_fixtures");
var PREFIX = "ph_composer.ducting.";
var DT1 = "dct_AAAAAAAAAAAA", DT2 = "dct_BBBBBBBBBBBB", DG1 = "dcg_AAAAAAAAAAAA", DG2 = "dcg_BBBBBBBBBBBB";

function type(id, name, values, used) {
  return { id: id, kind: PREFIX + "duct_type", schema_version: 1, user_data: {}, extension_data: {},
    extension_status: {}, export_ready: true, export_blockers: [], display: { color: "#4a7fb5" },
    used_length_m: used, values: Object.assign({ name: name, notes: "", datasheet_links: [],
      source: { kind: "manual" }, insulation_reflective: true, insulation_thickness_mm: 25.4,
      insulation_conductivity_w_mk: 0.04 }, values) };
}
function selected(id, values) {
  var path = [600, id];
  return { path: path, reference: { group_path: [600], entity_path: path, entity_id: values.direction ? "dce_" + id :
    null }, group: { group_id: DG1, group_path: [600], ventilator_id: mechanical.ERV1.id }, reason: null,
  values: values, copied: false, record_problem: null, write_refusal: null };
}
function ventilators() {
  return [{ ventilator_id: mechanical.ERV1.id, name: "ERV-1", outdoor_air_length_m: 2.5, exhaust_air_length_m: 1.8 },
    { ventilator_id: mechanical.ERV2.id, name: "ERV-2", outdoor_air_length_m: 2.5, exhaust_air_length_m: 3 },
    { ventilator_id: mechanical.ERV3.id, name: "ERV-3", outdoor_air_length_m: 0, exhaust_air_length_m: 0 }];
}
function run(identifier, direction, ventilator, group, typeId, length, quantity, findings) {
  return { identifier: identifier, display_name: (direction === "outdoor_air" ? "Outdoor air" : "Exhaust air") + " 1",
    direction: direction, ventilator_id: ventilator.id, ventilator_name: ventilator.name,
    group: { group_id: group[0], group_path: [group[1]], name: group[2] }, duct_type_id: typeId,
    duct_type_name: typeId === DT1 ? "DT-1" : "DT-2", length_m: length, quantity: quantity, line_count: 2,
    edge_paths: [[group[1], identifier.length]], shared: false, findings: findings || [] };
}
function schedule() {
  var dg1 = [DG1, 600, "DG-1"], dg2 = [DG2, 700, "DG-2"];
  return { runs: [run("duct_dg1_oa", "outdoor_air", mechanical.ERV1, dg1, DT1, 2.5, 1),
    run("duct_dg1_ea", "exhaust_air", mechanical.ERV1, dg1, DT1, 1.8, 1),
    run("duct_dg2_oa", "outdoor_air", mechanical.ERV2, dg2, DT2, 2.5, 1),
    run("duct_dg2_ea", "exhaust_air", mechanical.ERV2, dg2, DT2, 1.5, 2, [{ code: "ducting.type_missing",
      message: "A finding.", blocks_export: true, locate: { edge_paths: [[700, 9]] } }])],
  totals: { by_direction: [{ direction: "outdoor_air", run_count: 2, line_count: 4, length_m: 5 },
    { direction: "exhaust_air", run_count: 2, line_count: 4, length_m: 4.8 }], run_count: 4, line_count: 8,
  length_m: 9.8 },
  ventilators: ventilators().map(function (row) {
    return Object.assign({ findings: row.name === "ERV-3" ? [{ code: "ducting.run_missing",
      message: "ERV-3 has no Outdoor air run.", blocks_export: false, locate: {} }] : [] }, row);
  }), types: [], unreadable: [], unreadable_total: 0 };
}
function groups() {
  return [{ path: [600], reference: { group_id: DG1, group_path: [600] }, name: "DG-1",
    values: { ventilator_id: mechanical.ERV1.id }, duct_count: 4, copied: false, findings: [], record_problem: null,
    write_refusal: null }];
}
function state() {
  var built = mechanical.state();
  built.sections[PREFIX + "duct_types"] = { status: "completed", value: { unreadable: [], records: [
    type(DT1, "DT-1", { shape: "round", diameter_mm: 160 }, 4.3),
    type(DT2, "DT-2", { shape: "rectangular", width_mm: 200, height_mm: 100, insulation_thickness_mm: 50.8,
      insulation_conductivity_w_mk: 0.035, insulation_reflective: false }, 5.5)] } };
  built.sections[PREFIX + "ducts.selected"] = { status: "completed", value: { ignored: [], ignored_total: 0, edges: [
    selected(601, {}), selected(602, { duct_type_id: DT2, direction: "exhaust_air", quantity: 2 }),
    { path: [5], reference: null, group: null, reason: "outside_group", values: {}, copied: false,
      record_problem: null, write_refusal: null }] } };
  built.sections[PREFIX + "ducting_ventilators"] = { status: "completed", value: { ventilators: ventilators() } };
  return built;
}
module.exports = { PREFIX: PREFIX, DT1: DT1, DT2: DT2, DG1: DG1, state: state, schedule: schedule, groups: groups,
  mechanical: mechanical };
