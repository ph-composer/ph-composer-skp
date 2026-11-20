"use strict";

/* The synthetic reference model (planning ACCEPTANCE, "Synthetic reference model") as the `spaces` snapshot
   section reads it: Zone A holds 101 Living, 102 Bath and 103 Hall (two Volumes), each with one rate, so it uses
   detailed airflows; Zone B holds 201 Loft, with none, so it is By Program. `outside` adds a Space no Zone holds,
   with no Volume; `loft` gives Loft those rates; `noLoft` leaves Zone B with no Spaces; `stair` adds 202 Stair,
   with no rate, to Zone B; `bareA` takes Zone A's rates away, so it is By Program too. Numbers are the
   hand-computed ones, as the host publishes them. */

var ZONE_A = [100], ZONE_B = [200];
var AIRFLOW_KEYS = ["v_sup_m3h", "v_eta_m3h", "v_tran_m3h"];

function rated(item) {
  return AIRFLOW_KEYS.some(function (key) { return Object.prototype.hasOwnProperty.call(item.values, key); });
}

/* Each Space carries its Zone's mode, as the host publishes it: detailed once any Space in the Zone has a rate,
   a blank then 0; By Program otherwise, every rate null. A Space in no Zone reads its own rates. */
function applyModes(spaces) {
  spaces.forEach(function (item) {
    var zone = item.zone && item.zone.zone_id;
    var members = spaces.filter(function (other) {
      return zone ? other.zone && other.zone.zone_id === zone : other === item;
    });
    item.airflow_mode = members.some(rated) ? "detailed" : "by_program";
    AIRFLOW_KEYS.forEach(function (key) {
      item.airflows[key] = item.airflow_mode === "detailed" ? item.values[key] || 0 : null;
    });
  });
  return spaces;
}

function segment(path, name, area, factor) {
  return { id: "sfs_" + path.join("_"), weighting_band: String(factor),
    values: { display_name: name, weighting_factor: factor, net_area_factor: 1 },
    reference: { floor_segment_id: "sfs_" + path.join("_"), entity_path: path }, findings: [],
    metrics: { floor_area_m2: area, weighted_area_m2: area * factor, net_area_m2: area, horizontal: true } };
}

function volume(path, number, height, segments) {
  var area = segments.reduce(function (sum, item) { return sum + item.metrics.floor_area_m2; }, 0);
  var weighted = segments.reduce(function (sum, item) { return sum + item.metrics.weighted_area_m2; }, 0);
  return { id: "svl_" + path.join("_"), values: { number: number, display_name: "Volume " + number,
    avg_ceiling_height_m: height }, reference: { volume_id: "svl_" + path.join("_"), entity_path: path },
    nested: false, open: false, protected: true, moved: false, findings: [], floor_segments: segments,
    metrics: { floor_area_m2: area, weighted_area_m2: weighted, net_area_m2: area,
      net_volume_m3: height === null ? null : area * height } };
}

function space(path, zonePath, number, name, airflows, volumes) {
  var area = 0, weighted = 0, net = 0, heightArea = 0, heighted = 0;
  volumes.forEach(function (item) {
    area += item.metrics.floor_area_m2; weighted += item.metrics.weighted_area_m2;
    net += item.metrics.net_volume_m3 || 0;
    if (item.values.avg_ceiling_height_m !== null) {
      heightArea += item.metrics.floor_area_m2;
      heighted += item.metrics.floor_area_m2 * item.values.avg_ceiling_height_m;
    }
  });
  return { id: "spc_" + number, values: Object.assign({ name: name, number: number }, airflows),
    reference: { space_id: "spc_" + number, entity_path: path },
    zone: zonePath && { zone_id: zonePath === ZONE_A ? "zon_a" : "zon_b", zone_path: zonePath },
    state: "found", nested: false, findings: [], airflow_mode: null, airflows: {}, volumes: volumes,
    metrics: { floor_area_m2: area, weighted_area_m2: weighted, net_area_m2: area, net_volume_m3: net,
      average_height_m: heightArea ? heighted / heightArea : null } };
}

function zoneSums(zonePath, name, spaces) {
  var own = spaces.filter(function (item) { return item.zone && item.zone.zone_path === zonePath; });
  var mode = own.some(function (item) { return item.airflow_mode === "detailed"; }) ? "detailed" : "by_program";
  var flows = {};
  AIRFLOW_KEYS.forEach(function (key) {
    flows[key] = mode === "detailed" ? own.reduce(function (sum, item) { return sum + item.airflows[key]; }, 0) : null;
  });
  function sum(key) { return own.reduce(function (total, item) { return total + item.metrics[key]; }, 0); }
  return { zone_id: zonePath === ZONE_A ? "zon_a" : "zon_b", zone_path: zonePath, name: name,
    space_count: own.length, floor_area_m2: sum("floor_area_m2"), weighted_area_m2: sum("weighted_area_m2"),
    net_volume_m3: sum("net_volume_m3"), airflow_mode: mode, airflows: flows };
}

function section(options) {
  var spaces = [
    space([100, 101], ZONE_A, "101", "Living", { v_sup_m3h: 60 },
      [volume([100, 101, 1], 1, 2.5, [segment([100, 101, 1, 1], "Segment 1", 12, 1)])]),
    space([100, 102], ZONE_A, "102", "Bath", { v_eta_m3h: 40 },
      [volume([100, 102, 1], 1, 2.4, [segment([100, 102, 1, 1], "Segment 1", 4, 1)])]),
    space([100, 103], ZONE_A, "103", "Hall", { v_tran_m3h: 20 },
      [volume([100, 103, 1], 1, 2.5, [segment([100, 103, 1, 1], "Segment 1", 4, 1)]),
        volume([100, 103, 2], 2, 5.0, [segment([100, 103, 2, 1], "Segment 1", 2, 0)])]),
    space([200, 201], ZONE_B, "201", "Loft", options && options.loft || {},
      [volume([200, 201, 1], 1, 3.0, [segment([200, 201, 1, 1], "Segment 1", 12, 1)])])
  ];
  if (options && options.noLoft) spaces.pop();
  if (options && options.bareA) {
    spaces.slice(0, 3).forEach(function (item) {
      AIRFLOW_KEYS.forEach(function (key) { delete item.values[key]; });
    });
  }
  if (options && options.stair) {
    spaces.push(space([200, 202], ZONE_B, "202", "Stair", {},
      [volume([200, 202, 1], 1, 2.5, [segment([200, 202, 1, 1], "Segment 1", 4, 1)])]));
  }
  if (options && options.outside) spaces.push(space([300], null, "301", "Shed", {}, []));
  applyModes(spaces);
  return { spaces: spaces, findings: [], units: { area: "m2", height: "m", volume: "m3", airflow: "m3/h" },
    zones: [zoneSums(ZONE_A, "Zone A", spaces), zoneSums(ZONE_B, "Zone B", spaces)] };
}

/* The Zones read for the same two Zones. */
function zones() {
  return [ZONE_A, ZONE_B].map(function (path, index) {
    var id = index ? "zon_b" : "zon_a";
    return { id: id, schema_version: 1, user_data: {}, extension_data: {}, reference: { zone_id: id, zone_path: path },
      state: "found", face_count: 0, face_area_m2: 0, unclassified_face_area_m2: 0,
      values: { name: index ? "Zone B" : "Zone A", building_segment: "house", level: null, ground_depth_mm: 0 } };
  });
}

/* Opens every row through the control row's one Collapse all / Expand all toggle. While anything is open it
   offers Collapse all, so a partly open table takes a second press. */
function expandAll(section) {
  for (var press = 0; press < 2; press += 1) {
    var toggle = section.querySelector(".phc-view-expansion");
    var expanding = toggle.getAttribute("aria-label") === "Expand all";
    toggle.listeners.click({ preventDefault: function () {} });
    if (expanding) return;
  }
}

module.exports = { section: section, zones: zones, expandAll: expandAll };
