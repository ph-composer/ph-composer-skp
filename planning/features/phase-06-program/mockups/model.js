"use strict";
/* Programs prototype: the synthetic Model, its records and the derived values (illustrative). Plain
   globals shared with views.js and app.js; a throwaway planning page, not panel code. */
var svg = Mockup.svg, esc = Mockup.esc;
function iconBtn(n, label, act, extra) { return '<button type="button" class="phc-icon-button assembly-tool-icon" aria-label="' + esc(label) + '" data-tip="' + esc(label) + '"' + (act ? ' data-act="' + act + '"' : '') + (extra || "") + '>' + svg(n, 18) + '</button>'; }
function flag(text) { return '<span class="zp-cell-flag" role="img" aria-label="' + esc(text) + '" data-tip="' + esc(text) + '">' + svg("alert", 14) + '</span>'; }
function fmt(v, d) { if (v === null || v === undefined || isNaN(v)) return "—"; return Number(v).toLocaleString("en-US", { minimumFractionDigits: d || 0, maximumFractionDigits: d || 0 }); }

// ---------------------------------------------------------------- Phius library (values from PHIUS_programs.py)
// [name, people/m2, occ start, occ end, days/a, occ fraction, lighting W/m2, lighting h/d, equipment W/m2]
var PHIUS = {
  mf: [["Indoor Corridor", 0, 0, 24, 365, 1, 5.38, 24, 0], ["Indoor Stair", 0, 0, 24, 365, 0, 5.27, 24, 0], ["Common Laundry", 0.1125, 0, 24, 365, 1, 7.53, 24, 0],
    ["Common Mail", 0.1125, 6, 18, 365, 1, 30.14, 12, 0], ["Common Office", 0.0113, 7.5, 16.5, 365, 1, 10.76, 9, 42.3], ["Elevator", 0, 0, 24, 365, 1, 13.45, 24, 0],
    ["Multi-Purpose", 0.5382, 6, 18, 365, 1, 11.84, 12, 0], ["Storage/Equip Room", 0, 0, 1, 365, 1, 16.15, 1, 0], ["Workout Room", 0.3229, 6, 22, 365, 1, 9.69, 16, 12.04],
    ["Central Restroom", 0.0307, 11.2, 12.8, 365, 1, 9.69, 1.6, 0]],
  nr: [["Office Workspace Open", 0.0565, 7, 18, 250, 1, 6.57, 11, 7.64], ["Office Workspace Closed", 0.0511, 7, 18, 250, 0.7, 7.97, 11, 6.89], ["Office Meeting Room", 0.5382, 7, 18, 250, 0.5, 10.44, 11, 3.98],
    ["Hallway", 0, 7, 18, 250, 0.2, 5.38, 11, 0], ["Restroom Public", 0, 7, 18, 250, 0.1, 6.78, 11, 2.91], ["Classroom", 0.2691, 8, 15, 200, 0.75, 7.64, 7, 15.0],
    ["Canteen", 0.7535, 8, 15, 250, 1, 6.46, 7, 116.79], ["Gym", 0.2146, 8, 23, 300, 0.7, 9.69, 15, 18.62], ["Library Reading Room", 0.1076, 8, 20, 300, 1, 8.93, 12, 10.01],
    ["Hotel Bedroom", 0.0384, 21, 8, 365, 0.25, 4.41, 11, 6.75], ["Kitchen Commercial Cooking", 0.0538, 10, 23, 300, 1, 11.73, 13, 403.97], ["Server Room", 0, 0, 24, 365, 0.5, 4.63, 24, 2.91],
    ["Storage Archive", 0, 7, 18, 250, 0.02, 7.43, 11, 0], ["School Auditorium", 1.6146, 8, 18, 150, 0.75, 6.57, 12, 4.95], ["Restaurant", 0.7535, 10, 24, 300, 1, 6.46, 14, 64.93],
    ["Manufacturing Workshop", 0.0538, 7, 16, 250, 1, 14.32, 11, 43.06]]
};
var SOURCES = { mf: "Phius Multifamily", nr: "Phius Non-Residential" };

// ---------------------------------------------------------------- state
var S;
var uid = 0;
function id(p) { uid += 1; return p + uid; }
function sched(name, kind, ph, hourly, src) { return { id: id("sch"), name: name, kind: kind, ph: ph, hourly: hourly, source: src || "file" }; }
function profile(arr) { return arr; }
function ventSched(name, v, src) {
  var names = ["high", "standard", "basic", "minimum"];
  var x = sched(name, "Ventilation", null, null, src);
  x.vent = { periods: names.map(function (n, i) { return { name: n, hours: v[i * 2], frac: v[i * 2 + 1] }; }), days: 7, weeks: 52 };
  return x;
}

// ---------------------------------------------------------------- Equipment Set devices
// One entry per honeybee-ph PhEquipment type PHX reads (honeybee_grasshopper_ph create_elec_equip.py). `rq` lists
// the WUFI/METr reference quantity codes valid for the type; `demand` its energy demand; `extra` its own fields.
var REFQ = { 1: "PH-case occupants", 2: "Zone occupants", 3: "Bedrooms", 4: "PH-case units", 5: "User defined", 6: "PH-case floor area", 7: "Zone floor area", 8: "n.a." };
var WATER = ["DHW connection", "Cold water connection"];
var FRIDGE = { rq: [1, 2, 5], norms: ["Per day", "Per year"], demand: { label: "Energy demand (rated)", unit: "kWh", def: 1.0 }, perUse: { label: "Energy per day", unit: "kWh/d", def: 1.0 } };
var DEVICE_TYPES = [
  { id: "dishwasher", label: "Dishwasher", rq: [1, 2, 5], norms: ["Per year"], demand: { label: "Annual energy use rating", unit: "kWh/a", def: 269 }, perUse: { label: "Energy per use", unit: "kWh/use", def: 1.1 },
    extra: [{ k: "capacity_type", label: "Capacity, preselection", options: ["Standard"] }, { k: "capacity", label: "Capacity", unit: "place settings", def: 12 }, { k: "water", label: "Water connection", options: WATER }] },
  { id: "washer", label: "Clothes washer", rq: [1, 2, 5], norms: ["Per year"], demand: { label: "Annual energy use", unit: "kWh/a", def: 120 }, perUse: { label: "Energy per use", unit: "kWh/use", def: 1.1 },
    extra: [{ k: "capacity", label: "Capacity", unit: "m³", def: 0.1274 }, { k: "mef", label: "MEF, modified energy factor", unit: "", def: 2.7 }, { k: "util", label: "Utilization factor", unit: "", def: 1.0 }, { k: "water", label: "Water connection", options: WATER }] },
  { id: "dryer", label: "Clothes dryer", rq: [1, 2, 5], norms: ["CEF"], demand: { label: "CEF, combined energy factor", unit: "lb/kWh", def: 3.93 }, perUse: { label: "Energy per use", unit: "kWh/use", def: 3.5 },
    extra: [{ k: "dryer_type", label: "Dryer type", options: ["Clothes line", "Drying closet (cold)", "Drying closet (cold) in extract air", "Condensation dryer", "Electric exhaust air dryer", "Gas exhaust air dryer", "Heat pump dryer"], def: "Condensation dryer" },
      { k: "gas", label: "Gas consumption", unit: "kWh", def: 0, when: "Gas exhaust air dryer" }, { k: "gas_cef", label: "CEF, gas", unit: "", def: 2.67, when: "Gas exhaust air dryer" },
      { k: "fuf_type", label: "Field utilization factor, preselection", options: ["Timer controls", "Moisture sensing"] }, { k: "fuf", label: "Field utilization factor", unit: "", def: 1.18 }] },
  { id: "fridge", label: "Refrigerator", rq: FRIDGE.rq, norms: FRIDGE.norms, demand: FRIDGE.demand, perUse: FRIDGE.perUse },
  { id: "freezer", label: "Freezer", rq: FRIDGE.rq, norms: FRIDGE.norms, demand: FRIDGE.demand, perUse: FRIDGE.perUse },
  { id: "fridge_freezer", label: "Fridge-freezer", rq: FRIDGE.rq, norms: FRIDGE.norms, demand: FRIDGE.demand, perUse: FRIDGE.perUse },
  { id: "cooktop", label: "Cooktop", rq: [1, 2, 5], norms: ["Per use"], demand: { label: "Energy demand (rated)", unit: "kWh/use", def: 0.2 }, perUse: { label: "Energy per use", unit: "kWh/use", def: 0.25 },
    extra: [{ k: "fuel", label: "Cooktop type", options: ["Electricity", "Natural gas", "LPG"] }] },
  { id: "mel", label: "Phius MEL", rq: [3, 5], rule: "Phius rule: bedrooms and iCFA" },
  { id: "light_int", label: "Phius interior lighting", rq: [6, 7, 5], rule: "Phius rule: iCFA", extra: [{ k: "hef", label: "High-efficacy fraction", unit: "0 to 1", def: 1.0 }] },
  { id: "light_ext", label: "Phius exterior lighting", rq: [6, 7, 5], rule: "Phius rule: iCFA", extra: [{ k: "hef", label: "High-efficacy fraction", unit: "0 to 1", def: 1.0 }] },
  { id: "light_garage", label: "Phius garage lighting", rq: [8], rule: "Phius rule: per dwelling", extra: [{ k: "hef", label: "High-efficacy fraction", unit: "0 to 1", def: 1.0 }] },
  { id: "custom_elec", label: "Custom electric, annual", rq: [5], norms: ["Per year"], demand: { label: "Annual energy use", unit: "kWh/a", def: 100 } },
  { id: "custom_light", label: "Custom lighting, annual", rq: [5], norms: ["Per year"], demand: { label: "Annual energy use", unit: "kWh/a", def: 100 } },
  { id: "custom_mel", label: "Custom MEL, annual", rq: [5], norms: ["Per year"], demand: { label: "Annual energy use", unit: "kWh/a", def: 100 } }
];
function devType(id) { return DEVICE_TYPES.filter(function (d) { return d.id === id; })[0]; }
function newDevice(typeId, name) {
  var ty = devType(typeId), d = { type: typeId, name: name || ty.label, qty: 1, inside: !/ext|garage/.test(typeId), ref: ty.rq[0], norm: ty.norms ? ty.norms[0] : null, comment: "" };
  if (ty.demand) d.demand = ty.demand.def;
  if (ty.perUse) d.perUse = ty.perUse.def;
  (ty.extra || []).forEach(function (x) { d[x.k] = x.options ? (x.def || x.options[0]) : x.def; });
  return d;
}
function deviceDemand(d) {
  var ty = devType(d.type);
  if (ty.rule) return ty.rule;
  if (d.type === "dryer") return "CEF " + fmt(d.demand, 2) + " lb/kWh";
  if (ty.id === "cooktop") return fmt(d.demand, 2) + " kWh/use";
  if (/fridge|freezer/.test(ty.id)) return fmt(d.demand, 1) + (d.norm === "Per day" ? " kWh/d" : " kWh/a");
  return fmt(d.demand) + " kWh/a";
}

// A Building Segment and the settings its dialog edits. Field names follow honeybee-ph BldgSegment and PhiusCertification.
function segRecord(name, cat, air) {
  return { id: id("seg"), name: name, category: cat, air: air || { kind: "n50", value: null }, cert: "Phius 2021 CORE", use: cat === "res" ? "Residential" : "School",
    status: "In planning", type: "New construction", wind: "Several sides exposed, no screening", mechCool: false, mechRoom: 20, defProgram: null,
    single: false, house: null };
}
function baseState(j) {
  uid = 0;
  var s = { journey: j, ztab: "programs", openCards: {}, tab: "zones", ptab: "programs", selProgram: null, selSchedule: null, selSet: null, checked: {}, lib: "file", libQuery: "", notice: null, bubble: null,
    programs: [], schedules: [], sets: [], dwellings: [], segments: [], zones: [] };
  // honeybee-ph single-family schedules (hbph_sfh_*.json): hourly profiles, illustrative values here.
  var presence = sched("SFH occupant presence", "Fractional", null, profile([1, 1, 1, 1, 1, 1, .9, .6, .4, .3, .3, .3, .3, .3, .3, .4, .5, .7, .9, .9, .9, 1, 1, 1]), "hbph");
  var activity = sched("SFH occupant activity", "Activity level", null, profile([95, 95, 95, 95, 95, 95, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 95, 95]), "hbph");
  var lighting = sched("SFH lighting", "Fractional", null, profile([.05, .05, .05, .05, .05, .1, .3, .4, .2, .1, .1, .1, .1, .1, .1, .1, .2, .5, .8, .9, .8, .6, .3, .1]), "hbph");
  var hotwater = sched("SFH combined hot water", "Fractional", null, profile([.02, .01, .01, .01, .02, .1, .5, .7, .6, .4, .3, .3, .3, .2, .2, .2, .3, .5, .7, .6, .5, .4, .2, .1]), "hbph");
  var heat = sched("SFH heating setpoint", "Temperature", null, profile(new Array(24).fill(20)), "hbph");
  var cool = sched("SFH cooling setpoint", "Temperature", null, profile(new Array(24).fill(25)), "hbph");
  var always = sched("Always On", "Fractional", { start: 0, end: 24, frac: 1, base: 0, days: 7, weeks: 52 }, null, "builtin");
  // Q4a-33: a ventilation schedule is four named periods (PHX requires high, standard, basic, minimum).
  var ventRes = ventSched("SFH ventilation", [2, 1.0, 14, 0.77, 6, 0.54, 2, 0.4], "hbph");
  var ventConst = ventSched("Constant ventilation", [0, 1.0, 24, 1.0, 0, 0.5, 0, 0.3], "builtin");
  s.schedules.push(presence, activity, lighting, hotwater, heat, cool, always, ventRes, ventConst);
  s.programs.push({ id: "pgm_default", name: "Residential (default)", source: "default",
    people: { rule: true, sched: presence.id, act: activity.id }, lighting: { rule: true, hef: 1.0, sched: lighting.id },
    equip: { wpa: 0, sched: always.id }, gas: { wpa: 0, sched: always.id }, shw: { rule: true, temp: 43.3, sched: hotwater.id },
    infil: { flow: 0.0003, sched: always.id }, vent: { pp: 0, pa: 0, pz: 0, ach: 0.4, sched: ventRes.id },
    setpoint: { heat: 20, cool: 25, hs: heat.id, cs: cool.id, dehum: 60 } });
  s.sets.push({ id: "set_sfh", name: "Phius single-family default", devices: [newDevice("fridge_freezer"), newDevice("dishwasher"), newDevice("washer"), newDevice("dryer"),
    newDevice("cooktop"), newDevice("mel"), newDevice("light_ext"), newDevice("light_garage")] });
  s.selProgram = "pgm_default"; s.selSchedule = presence.id; s.selSet = "set_sfh";

  function seg(name, cat, air) { var g = segRecord(name, cat, air); if (!s.defaultSeg) s.defaultSeg = g.id; s.segments.push(g); return g.id; }
  function zone(name, segId, area, icfa) { s.zones.push({ id: id("zn"), name: name, seg: segId, area: area, icfa: icfa, program: null, dwelling: null, beds: null, occ: null, set: null }); }
  if (j === 1) {
    var h = seg("House", "res", { kind: "n50", value: 0.6 });
    zone("Living-Kitchen", h, 48, 45.6); zone("Bedroom 1", h, 14, 13.3); zone("Bedroom 2", h, 12, 11.4); zone("Bath", h, 7, 6.6); zone("Hall and stair", h, 10, 6.0);
    // Single dwelling is on: the switch makes every Zone one dwelling, House, with counts on the dwelling.
    s.dwellings.push({ id: "dw_house", name: "House", units: 1, beds: null, occ: null, set: null });
    s.zones.forEach(function (z) { z.dwelling = "dw_house"; });
    s.segments[0].single = true; s.segments[0].house = "dw_house";
  } else if (j === 2) {
    var b = seg("Building", "res", { kind: "q50", value: 1.1 });
    ["101", "102", "103", "104", "201", "202", "203", "204"].forEach(function (n, i) { zone("Apt " + n, b, [62, 78, 55, 81][i % 4], [58.9, 74.1, 52.3, 77.0][i % 4]); });
  } else if (j === 3) {
    var m = seg("Building", "res", { kind: "q50", value: 1.1 });
    ["101", "102", "103", "201", "202", "203"].forEach(function (n, i) { zone("Apt " + n, m, [62, 78, 55][i % 3], [58.9, 74.1, 52.3][i % 3]); });
    zone("Corridor L1", m, 36, 36); zone("Corridor L2", m, 36, 36); zone("Lobby and mail", m, 28, 28); zone("Stair A", m, 18, 9); zone("Super's office", m, 12, 12); zone("Fitness room", m, 24, 24); zone("Bike shed", m, 15, 0);
  } else if (j === 4) {
    var sc = seg("School", "nonres", { kind: "n50", value: 0.6 });
    zone("Classroom 101", sc, 70, 70); zone("Classroom 102", sc, 70, 70); zone("Classroom 103", sc, 70, 70); zone("Hallway", sc, 64, 64); zone("Restrooms", sc, 22, 22);
    zone("Admin office", sc, 30, 30); zone("Gym", sc, 180, 180); zone("Canteen", sc, 95, 95);
  } else {
    var lab = seg("Lab building", "nonres", { kind: "n50", value: 0.6 });
    zone("Wet lab", lab, 120, 120); zone("Write-up", lab, 60, 60); zone("Freezer farm", lab, 25, 25); zone("Corridor", lab, 40, 40);
  }
  addSpaces(s);
  return s;
}
// Synthetic Spaces per Zone: name and share of the Zone's floor area. The Bike shed has none.
function addSpaces(s) {
  s.zones.forEach(function (z, zi) {
    var parts;
    if (/^Apt/.test(z.name)) parts = [["Living", .4], ["Bedroom", .3], ["Kitchen", .15], ["Bath", .15]];
    else if (z.name === "Living-Kitchen") parts = [["Living", .62], ["Kitchen", .38]];
    else if (z.name === "Hall and stair") parts = [["Hall", .6], ["Stair", .4]];
    else if (z.name === "Bike shed") parts = [];
    else parts = [[z.name, 1]];
    z.spaces = parts.map(function (p, i) {
      var a = z.area * .94 * p[1];
      return { id: id("sp"), num: (zi + 1) + "." + ("0" + (i + 1)).slice(-2), name: p[0], area: a, icfa: z.icfa * p[1], vol: a * 2.5, sup: null, eta: null, tran: null };
    });
  });
}

function phiusProgram(src, row) {
  var occ = sched(row[0] + " occupancy", "Fractional", { start: row[2], end: row[3], frac: row[5], base: 0, days: Math.min(7, Math.round(row[4] / 52)), weeks: 52, daysYear: row[4] }, null, "file");
  var lgt = sched(row[0] + " lighting", "Fractional", { start: Math.max(0, row[2]), end: Math.min(24, row[2] + row[7]), frac: 1, base: 0, days: Math.min(7, Math.round(row[4] / 52)), weeks: 52, daysYear: row[4] }, null, "file");
  S.schedules.push(occ, lgt);
  var always = S.schedules.filter(function (x) { return x.name === "Always On"; })[0];
  var vc = S.schedules.filter(function (x) { return x.name === "Constant ventilation"; })[0];
  if (src === "custom") return { id: id("pgm"), name: row[0], source: src, people: { ppa: row[1], sched: occ.id }, lighting: { wpa: row[6], sched: lgt.id },
    equip: { wpa: row[8], sched: occ.id }, gas: { wpa: 0, sched: always.id }, shw: { lph: null, temp: 60, sched: occ.id },
    infil: { flow: 0.0003, sched: always.id }, vent: { pp: null, pa: null, pz: 0, ach: null, sched: vc.id },
    setpoint: { heat: 20, cool: 25, hs: null, cs: null, dehum: null } };
  return { id: id("pgm"), name: row[0], source: src, base: src === "mf" ? "2019::MidriseApartment::Corridor" : "2019::SecondarySchool::Classroom",
    people: { ppa: row[1], sched: occ.id }, lighting: { wpa: row[6], sched: lgt.id },
    equip: { wpa: row[8], sched: occ.id }, gas: { wpa: 0, sched: always.id }, shw: { lph: 0.04, temp: 60, sched: occ.id, fromBase: true },
    infil: { flow: 0.0003, sched: always.id, fromBase: true }, vent: { pp: 18, pa: 1.08, pz: 0, ach: 0, sched: vc.id, fromBase: true },
    setpoint: { heat: 21.1, cool: 23.9, hs: null, cs: null, dehum: 60, fromBase: true } };
}
function programByName(name) { return S.programs.filter(function (p) { return p.name === name; })[0]; }
function addFromLibrary(src, name) {
  var have = programByName(name); if (have) return have;
  var row = PHIUS[src].filter(function (r) { return r[0] === name; })[0];
  var p = phiusProgram(src, row); S.programs.push(p); return p;
}
function prog(pid) { return S.programs.filter(function (p) { return p.id === pid; })[0]; }
function schedById(sid) { return S.schedules.filter(function (x) { return x.id === sid; })[0]; }
function seg(sid) { return S.segments.filter(function (g) { return g.id === sid; })[0]; }
function dw(did) { return S.dwellings.filter(function (d) { return d.id === did; })[0]; }
function setById(sid) { return S.sets.filter(function (x) { return x.id === sid; })[0]; }
function zonesOfDwelling(did) { return S.zones.filter(function (z) { return z.dwelling === did; }); }

// ---------------------------------------------------------------- derived values (illustrative)
function schedMean(sc) {
  if (!sc) return 1;
  if (sc.hourly) { var t = 0; sc.hourly.forEach(function (v) { t += v; }); return t / 24; }
  if (sc.vent) { var tv = 0; sc.vent.periods.forEach(function (pd) { tv += pd.hours * pd.frac; }); return tv / 24; }
  var p = sc.ph, hrs = p.end > p.start ? p.end - p.start : 24 - p.start + p.end;
  return (hrs * p.frac + (24 - hrs) * p.base) / 24;
}
function segDefaultProgram(z) { var g = z.seg ? seg(z.seg) : null; return (g && g.defProgram) || "pgm_default"; }
function effectiveProgram(z) { return prog(z.program || segDefaultProgram(z)); }
function dwellingTotals(did) {
  var zs = zonesOfDwelling(did), d = dw(did), beds = 0, occSet = 0, anyOcc = false, area = 0, icfa = 0;
  zs.forEach(function (z) { beds += z.beds || 0; if (z.occ !== null) { anyOcc = true; occSet += z.occ; } area += z.area; icfa += z.icfa; });
  // Counts entered once on the dwelling (Single dwelling) replace the per-Zone sums.
  if (d.beds !== null && d.beds !== undefined) beds = d.beds;
  if (d.occ !== null && d.occ !== undefined) { anyOcc = true; occSet = d.occ; }
  var occ = anyOcc ? occSet : beds + d.units; // Phius: (bedrooms / units + 1) x units
  return { zones: zs.length, beds: beds, occ: occ, occRule: !anyOcc, area: area, icfa: icfa, units: d.units };
}
function derived(z) {
  var p = effectiveProgram(z), out = { people: null, lighting: null, vent: null, ventMissing: false };
  if (p.people.rule) {
    if (z.dwelling) {
      var t = dwellingTotals(z.dwelling), peak = t.occ / schedMean(schedById(p.people.sched));
      out.people = peak * z.area / t.area;
    } else out.people = null;
  } else out.people = p.people.ppa * z.area;
  if (p.lighting.rule) {
    var units = z.dwelling ? dwellingTotals(z.dwelling).units : 1, icfaDw = z.dwelling ? dwellingTotals(z.dwelling).icfa : z.icfa;
    var kwh = (0.2 + 0.8 * (4 - 3) / 3.7) * (455 * units + 0.8 * icfaDw * 10.764) * 0.8;
    out.lighting = kwh * 1000 / (schedMean(schedById(p.lighting.sched)) * 8760) * z.icfa / icfaDw;
  } else out.lighting = p.lighting.wpa * z.area;
  var v = p.vent;
  if (v.pa === null || v.pp === null || v.ach === null) out.ventMissing = true;
  else out.vent = (v.pp * (out.people || 0)) + v.pa * z.area + v.pz + v.ach * z.area * 2.7;
  // Detailed airflows (Zones → Spaces) replace the Program's flow; the larger of supply and extract is shown.
  if (zoneDetailed(z)) {
    var sup = 0, eta = 0; z.spaces.forEach(function (sp) { sup += sp.sup || 0; eta += sp.eta || 0; });
    out.vent = Math.max(sup, eta); out.ventMissing = false; out.ventDetailed = { sup: sup, eta: eta };
  }
  return out;
}
function zoneFindings(z) {
  var p = effectiveProgram(z), g = seg(z.seg), f = [];
  if (g.category === "res" && p.source !== "default" && p.equip.wpa > 0)
    f.push(p.name + "'s electric equipment, " + fmt(p.equip.wpa, 1) + " W/m², does not reach WUFI or METr in a residential Building Segment: PHX reads only Equipment Set devices there. Model it as a device instead.");
  if (g.category === "nonres" && !z.program) f.push("Uses the residential default in a non-residential Building Segment. Choose a Program.");
  return f;
}
function segFindings(g) {
  var zs = S.zones.filter(function (z) { return z.seg === g.id; }), anyDw = zs.some(function (z) { return z.dwelling; }), f = [];
  if (g.category === "nonres" && anyDw) f.push("Non-residential, but some of its Zones are dwellings.");
  if (g.category === "res" && !anyDw) f.push("Residential, but none of its Zones is a dwelling yet. PHX counts dwellings for the Phius targets.");
  return f;
}

// ---------------------------------------------------------------- journeys
var JOURNEYS = {
  1: { title: "Single-family home", hint: "The House Building Segment has <em>Single dwelling</em> on, as every new model does: all five Zones are one house with the residential default, so its rows are locked. <em>Type the bedrooms</em> on the Segment row. That is all. To assign per Zone, <em>click any locked cell</em> → Open settings and uncheck <em>Single dwelling</em>." },
  2: { title: "Apartments", hint: "Each Zone is one apartment. <em>Check every Zone</em> → Dwelling: <em>One dwelling each</em>. Then fill Bedrooms per row. Then open the Building's <em>settings</em> (hover its row) and check <em>Single dwelling</em> to see what it would replace." },
  3: { title: "Apartments + common areas", hint: "Make the six apartments <em>one dwelling each</em>. Then check the two corridors → Program: <em>Indoor Corridor</em> (Phius Multifamily, copied into the file on choice). Do the same for the stair, lobby, office and fitness room, and look at the amber flags. Then check the <em>Bike shed</em> → Building Segment: <em>No Building Segment</em>, and open a Segment's <em>settings</em> from its row." },
  4: { title: "Non-residential school", hint: "The Building Segment is non-residential, so every unassigned Zone is flagged. Check Zones and pick from <em>Phius Non-Residential</em> in the Program choice, or open the <em>Programs</em> tab and browse the library sidebar." },
  5: { title: "Custom lab programs", hint: "Nothing in the library fits. Open <em>Programs</em> → <em>+ New Program</em> in the sidebar to make one, set its loads, then open a load's schedule chip to edit the Schedule in the PH form. Assign it on Zones → Programs." }
};

