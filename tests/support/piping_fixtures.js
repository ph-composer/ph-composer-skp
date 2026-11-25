"use strict";
/* The piping sections and reads, in the shapes features/piping/declarations/ publishes, over the Mechanical
   fixtures: PT-1 (PEX 3/4 in) and PT-2 (Copper L 1/2 in, bare); Piping group "Riser" (500) linked to HWS-1 holding a
   trunk, a branch under it, a twig under that and a recirculation run; two selected lines in the group and one
   outside every Piping group. */
var mechanical = require("./mechanical_fixtures");
var PREFIX = "ph_composer.piping.";
var PT1 = "ppt_AAAAAAAAAAAA", PT2 = "ppt_BBBBBBBBBBBB", GROUP = "ppg_AAAAAAAAAAAA";

function type(id, name, values, used) {
  return { id: id, kind: PREFIX + "pipe_type", schema_version: 1, user_data: {}, extension_data: {},
    extension_status: {}, export_ready: true, export_blockers: [], display: { color: "#3b7ea1" },
    used_length_m: used, values: Object.assign({ name: name, notes: "", datasheet_links: [],
      source: { kind: "manual" }, insulation_reflective: true, insulation_quality: 1 }, values) };
}
function selected(id, values) {
  var path = [500, id];
  return { path: path, reference: { group_path: [500], entity_path: path, entity_id: values.role ? "ppe_" + id : null },
    group: { group_id: GROUP, group_path: [500], hot_water_system_id: mechanical.HWS1.id }, reason: null,
    values: values, copied: false, record_problem: null, write_refusal: null };
}
function systemRow(system, lengths, recirculation) {
  return Object.assign({ hot_water_system_id: system.id, name: system.name,
    distribution_length_m: lengths }, recirculation);
}
function systems() {
  return [systemRow(mechanical.HWS1, { trunk: 9, branch: 4, twig: 1.5 }, { recirculation_length_m: 11,
    recirculation_temperature_c: 54.09, recirculation_hours: 19, from_piping: true }),
  systemRow(mechanical.HWS2, { trunk: 0, branch: 0, twig: 0 }, { recirculation_length_m: 0,
    recirculation_temperature_c: 60, recirculation_hours: 24, from_piping: false })];
}
function run(identifier, role, parent, length, values, findings) {
  return { identifier: identifier, display_name: role[0].toUpperCase() + role.slice(1) + " 1", role: role,
    hot_water_system_id: mechanical.HWS1.id, hot_water_system_name: "HWS-1",
    group: { group_id: GROUP, group_path: [500], name: "Riser" }, parent: parent,
    parent_name: parent ? "Parent" : null, pipe_type_id: PT1, pipe_type_name: "PT-1", length_m: length,
    line_count: 2, values: values || {}, closed: false, edge_paths: [[500, identifier.length]], shared: false,
    findings: findings || [] };
}
function schedule() {
  return { runs: [run("pipe_trunk", "trunk", null, 9, { multiplier: 12, demand_recirculation: false }),
    run("pipe_recirc", "recirculation", null, 11, { water_temp_c: 55, daily_period: 18 }),
    run("pipe_twig", "twig", "pipe_branch", 1.5),
    run("pipe_branch", "branch", "pipe_trunk", 4, {}, [{ code: "piping.trunk_without_branches",
      message: "A finding.", blocks_export: true, locate: { edge_paths: [[500, 7]] } }])],
  totals: { by_role: [{ role: "trunk", run_count: 1, line_count: 2, length_m: 9 },
    { role: "branch", run_count: 1, line_count: 2, length_m: 4 },
    { role: "twig", run_count: 1, line_count: 2, length_m: 1.5 },
    { role: "recirculation", run_count: 1, line_count: 2, length_m: 11 }],
  run_count: 4, line_count: 8, distribution_length_m: 14.5, recirculation_length_m: 11 },
  systems: systems(), types: [], unreadable: [], unreadable_total: 0 };
}
function groups() {
  return [{ path: [500], reference: { group_id: GROUP, group_path: [500] }, name: "Riser",
    values: { hot_water_system_id: mechanical.HWS1.id }, pipe_count: 8, copied: false, findings: [],
    record_problem: null, write_refusal: null }];
}
function state() {
  var built = mechanical.state();
  built.sections[PREFIX + "pipe_types"] = { status: "completed", value: { unreadable: [], records: [
    type(PT1, "PT-1", { material: 6, diameter_mm: 19.05, insulation_thickness_mm: 12.7,
      insulation_conductivity_w_mk: 0.04 }, 9),
    type(PT2, "PT-2", { material: 2, diameter_mm: 12.7, insulation_thickness_mm: 0, insulation_reflective: false },
      0)] } };
  built.sections[PREFIX + "pipes.selected"] = { status: "completed", value: { ignored: [], ignored_total: 0, edges: [
    selected(601, {}), selected(602, { pipe_type_id: PT2, role: "twig" }),
    { path: [5], reference: null, group: null, reason: "outside_group", values: {}, copied: false,
      record_problem: null, write_refusal: null }] } };
  built.sections[PREFIX + "pipe_tool"] = { status: "completed", value: { active: false, pipe_type_id: null,
    role: "trunk", values: {}, gesture_limit: 250 } };
  built.sections[PREFIX + "piping_systems"] = { status: "completed", value: { systems: systems() } };
  return built;
}
module.exports = { PREFIX: PREFIX, PT1: PT1, PT2: PT2, GROUP: GROUP, state: state, schedule: schedule,
  groups: groups, mechanical: mechanical };
