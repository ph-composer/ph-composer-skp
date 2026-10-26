"use strict";
/* The Thermal Bridges tab's sections and schedule read, in the shapes the Ruby registrations publish
   (features/thermal_bridges/declarations/). */
var PREFIX = "ph_composer.thermal_bridges.";
function type(id, name, values) {
  return { id: id, kind: PREFIX + "type", schema_version: 1, user_data: {}, extension_data: {}, findings: [],
    values: Object.assign({ name: name, notes: "", datasheet_links: [], psi_w_mk: null, group: "15-Ambient" }, values),
    display: { color: "#d9a23b" }, export_ready: true, export_blockers: [] };
}
var ZONE = { zone_id: "zon_AAAAAAAAAAAA", zone_path: [100], name: "Zone A", building_segment: "Building",
  level: null };
/* One selected Edge inside Zone A, with its assignment values as stored. */
function edge(id, values) {
  return { path: [100, id], reference: { zone_id: ZONE.zone_id, zone_path: [100], entity_path: [id],
    entity_id: values ? "tbe_" + id : null }, zone: ZONE, reason: null, values: values || {}, copied: false,
    record_problem: null, write_refusal: null };
}
function outside(id) {
  return { path: [id], reference: null, zone: null, reason: "outside_zone", values: {}, copied: false,
    record_problem: null, write_refusal: null };
}
function schedule() {
  var run = { identifier: "tb_aaaa", display_name: "Parapet 1",
    zone: { zone_id: ZONE.zone_id, zone_path: [100], name: "Zone A", building_segment: "Building" },
    type_id: "tbt_a", type_name: "Parapet", group: "15-Ambient", psi_w_mk: 0.12, quantity: 1, length_m: 18,
    heat_loss_w_k: 2.16, closed: true, points_m: [[0, 0, 3], [5, 0, 3], [5, 4, 3], [0, 4, 3], [0, 0, 3]],
    edge_paths: [[100, 101], [100, 102], [100, 103], [100, 104]], shared: false,
    findings: [{ code: "thermal_bridge.counted_twice", blocks_export: false,
      message: "1 Edge also assigned in another Zone, so the bridge is counted twice; clear one.",
      locate: { edge_paths: [[100, 101]] } }] };
  return { runs: [run], edge_findings: [], edge_finding_total: 0, unreadable: [], unreadable_total: 0,
    totals: { by_type: [{ type_id: "tbt_a", type_name: "Parapet", group: "15-Ambient", run_count: 1, edge_count: 4,
      length_m: 18, heat_loss_w_k: 2.16 }],
    by_group: [{ group: "15-Ambient", heat_loss_w_k: 2.16 }, { group: "16-Perimeter", heat_loss_w_k: 0 },
      { group: "17-FS/BC", heat_loss_w_k: 0 }], run_count: 1, heat_loss_w_k: 2.16 },
    units: { length_m: "m", psi_w_mk: "W/mK", heat_loss_w_k: "W/K" } };
}
function state(edges) {
  var types = [type("tbt_a", "Parapet", { psi_w_mk: 0.12, color: "#c8553d" }),
    type("tbt_b", "Slab edge", { psi_w_mk: -0.02, group: "17-FS/BC", datasheet_links: ["https://example.test/slab"] })];
  var sections = {};
  sections[PREFIX + "types"] = { status: "completed", value: { records: types, unreadable: [] } };
  sections[PREFIX + "edges.selected"] = { status: "completed",
    value: { edges: edges || [], ignored: [], ignored_total: 0 } };
  sections[PREFIX + "edge_tool"] = { status: "completed",
    value: { active: false, thermal_bridge_type_id: null, quantity: 1, gesture_limit: 250 } };
  return { session: "session", revision: 1, sections: sections,
    ui: { activeTab: "thermal_bridges", actionResult: null, viewResults: {}, queryResults: {} } };
}
module.exports = { PREFIX: PREFIX, state: state, edge: edge, outside: outside, schedule: schedule };
