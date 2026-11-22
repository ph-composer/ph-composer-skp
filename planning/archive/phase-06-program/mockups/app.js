"use strict";
/* Programs prototype: render, events, `do=` replay steps and start-up through the mockup kit. */
// ---------------------------------------------------------------- render + events
function render() {
  Mockup.strip(); renderTabs();
  var pane = document.getElementById("pane");
  pane.innerHTML = S.tab === "zones" ? renderZones() : renderPrograms();
  var rn = document.querySelector('[data-act="seg-rename"]'); if (rn) { rn.focus(); rn.select(); }
  if (S.notice) { Mockup.notice(S.notice); S.notice = null; }
}
function notify(t) { S.notice = t; }
function assignProgram(zs, value) {
  var p;
  if (value.indexOf("lib:") === 0) { var parts = value.split(":"); p = addFromLibrary(parts[1], parts.slice(2).join(":")); notify("Added " + p.name + " to this file and assigned it to " + zs.length + " Zone" + (zs.length > 1 ? "s" : "") + "."); }
  else { p = prog(value.slice(4)); notify(p.name + " assigned to " + zs.length + " Zone" + (zs.length > 1 ? "s" : "") + "."); }
  zs.forEach(function (z) { z.program = p.id === "pgm_default" ? null : p.id; });
}
function nextDwellingName() { return "Dwelling " + (S.dwellings.length + 1); }
function zn(n) { return n + " Zone" + (n === 1 ? "" : "s"); }
function assignDwelling(zs, v) {
  if (v === "none") { zs.forEach(function (z) { z.dwelling = null; z.beds = null; z.occ = null; }); notify((zs.length === 1 ? zs[0].name + " is" : zn(zs.length) + " are") + " no longer part of a dwelling."); }
  else if (v === "shared") { var d = { id: id("dw"), name: S.journey === 1 ? "House" : nextDwellingName(), units: 1 }; S.dwellings.push(d); zs.forEach(function (z) { z.dwelling = d.id; }); notify(zs.length > 1 ? zs.length + " Zones now make up one dwelling, " + d.name + "." : zs[0].name + " is now a dwelling, " + d.name + "."); }
  else if (v === "each") { zs.forEach(function (z) { var d = { id: id("dw"), name: z.name, units: 1 }; S.dwellings.push(d); z.dwelling = d.id; }); notify(zs.length + " dwellings, one per Zone."); }
  else if (v.indexOf("to:") === 0) { var t = dw(v.slice(3)); zs.forEach(function (z) { z.dwelling = t.id; }); notify((zs.length === 1 ? zs[0].name : zn(zs.length)) + " added to " + t.name + "."); }
  S.dwellings = S.dwellings.filter(function (d) { return S.zones.some(function (z) { return z.dwelling === d.id; }); });
}
// The Dwelling cell's bubble: which dwelling this Zone belongs to, then that dwelling's own values.
function dwellingBubble(zid, anchor) {
  var z = S.zones.filter(function (x) { return x.id === zid; })[0], r = anchor.getBoundingClientRect(), pr = document.getElementById("pane").getBoundingClientRect();
  var choose = '<label class="zp-dw-choose"><span>Dwelling of ' + esc(z.name) + '</span><select data-act="zone-dwelling" data-v="' + z.id + '" aria-label="Dwelling of ' + esc(z.name) + '">' +
    S.dwellings.map(function (o) { return '<option value="to:' + o.id + '"' + (z.dwelling === o.id ? " selected" : "") + '>' + esc(o.name) + '</option>'; }).join("") +
    '<option value="shared">New dwelling</option><option value="none"' + (z.dwelling ? "" : " selected") + '>Not a dwelling</option></select></label>';
  var pos = 'style="left:' + Math.min(r.left - pr.left, pr.width - 280) + 'px; top:' + (r.bottom - pr.top + 4) + 'px"';
  if (!z.dwelling) { S.bubble = { html: '<div class="zp-bubble" ' + pos + ' role="dialog" aria-label="Dwelling of ' + esc(z.name) + '">' + choose + '<p class="zp-muted" style="margin:8px 0 0">Not part of a dwelling: no bedrooms, occupants or Equipment Set.</p></div>' }; return; }
  var did = z.dwelling, d = dw(did), t = dwellingTotals(did);
  var html = '<div class="zp-bubble" ' + pos + ' role="dialog" aria-label="Dwelling of ' + esc(z.name) + '">' + choose + '<h3 class="zp-dw-head">' + svg("home", 13) + ' ' + esc(d.name) + '</h3><dl>' +
    '<dt>Units</dt><dd><input data-act="units" data-v="' + d.id + '" value="' + d.units + '" style="width:60px;text-align:right"></dd><dt>Zones</dt><dd>' + t.zones + '</dd><dt>Bedrooms</dt><dd>' + (d.beds !== null && d.beds !== undefined ? '<input data-act="dw-beds" data-v="' + d.id + '" value="' + d.beds + '" style="width:60px;text-align:right">' : t.beds) + '</dd>' +
    '<dt>Occupants</dt><dd>' + fmt(t.occ, 1) + (t.occRule ? ' <span class="zp-info" role="img" aria-label="Phius rule: bedrooms + units" data-tip="No occupants entered, so the Phius rule applies: bedrooms + 1 per unit.">' + svg("info", 13) + '</span>' : "") + '</dd><dt>iCFA</dt><dd>' + fmt(t.icfa, 1) + ' m²</dd></dl></div>';
  S.bubble = { html: html };
}

document.addEventListener("click", function (e) {
  var el = e.target.closest("[data-act]"); if (!el) { if (S.bubble && !e.target.closest(".zp-bubble")) { S.bubble = null; render(); } return; }
  var a = el.getAttribute("data-act"), v = el.getAttribute("data-v");
  if (el.tagName === "SELECT" || el.tagName === "INPUT" && el.type !== "checkbox") return;
  if (a === "tab") { S.tab = v; S.bubble = null; }
  else if (a === "device-add") { deviceDialog(v, null); return; }
  else if (a === "device-edit") { deviceDialog(v, +el.getAttribute("data-i")); return; }
  else if (a === "device-delete") { confirmDeleteDevice(v, +el.getAttribute("data-i")); return; }
  else if (a === "card-toggle") { S.openCards[v] = !S.openCards[v]; }
  else if (a === "ztab") { S.ztab = v; S.checked = {}; S.bubble = null; }
  else if (a === "zone-reset") { var rz = S.zones.filter(function (z) { return z.id === v; })[0]; rz.spaces.forEach(function (sp) { sp.sup = sp.eta = sp.tran = null; }); notify(rz.name + " uses its Program's airflow again."); }
  else if (a === "ptab") { S.ptab = v; }
  else if (a === "check") { if (el.checked) S.checked[v] = 1; else delete S.checked[v]; }
  else if (a === "check-all") { S.checked = {}; if (el.checked) checkable().forEach(function (z) { S.checked[z.id] = 1; }); }
  else if (a === "clear-checked") { S.checked = {}; }
  else if (a === "sel-program") { S.selProgram = v; }
  else if (a === "sel-schedule") { S.selSchedule = v; }
  else if (a === "sel-set") { S.selSet = v; }
  else if (a === "lib-add") { var p = addFromLibrary(S.lib, v); S.selProgram = p.id; notify("Added " + p.name + " to this file."); }
  else if (a === "new-program") {
    var always = S.schedules.filter(function (x) { return x.name === "Always On"; })[0];
    var np = { id: id("pgm"), name: "Program " + (S.programs.length), source: "custom", people: { ppa: null, sched: null }, lighting: { wpa: null, sched: null }, equip: { wpa: null, sched: null }, gas: { wpa: 0, sched: always.id },
      shw: { lph: 0, temp: 60, sched: always.id }, infil: { flow: 0.0003, sched: always.id }, vent: { pp: null, pa: null, pz: 0, ach: 0, sched: always.id }, setpoint: { heat: 20, cool: 25, hs: null, cs: null, dehum: 60 } };
    S.programs.push(np); S.selProgram = np.id; notify(np.name + " created. Rename it from its title.");
  }
  else if (a === "dup-program") { var src = prog(S.selProgram), cp = JSON.parse(JSON.stringify(src)); cp.id = id("pgm"); cp.name = src.name + " (copy)"; cp.source = "custom"; S.programs.push(cp); S.selProgram = cp.id; notify("Duplicated as " + cp.name + "."); }
  else if (a === "new-schedule") { var ns = sched("Schedule " + S.schedules.length, "Fractional", { start: 8, end: 18, frac: 1, base: 0, days: 5, weeks: 52 }, null, "file"); S.schedules.push(ns); S.selSchedule = ns.id; }
  else if (a === "open-schedule") {
    if (!v) { var s2 = sched("Schedule " + S.schedules.length, "Fractional", { start: 8, end: 18, frac: 1, base: 0, days: 5, weeks: 52 }, null, "file"); S.schedules.push(s2); v = s2.id;
      var cur = prog(S.selProgram); var lbl = el.closest(".pgm-sched").textContent; var map = { Occupancy: "people", Lighting: "lighting", Equipment: "equip" }; Object.keys(map).forEach(function (k) { if (lbl.indexOf(k) === 0) cur[map[k]].sched = v; }); }
    S.ptab = "schedules"; S.selSchedule = v;
  }
  else if (a === "new-set") { var ns2 = { id: id("set"), name: "Equipment Set " + (S.sets.length + 1), devices: [] }; S.sets.push(ns2); S.selSet = ns2.id; }
  else if (a === "dwelling") { dwellingBubble(v, el); }
  else if (a === "lock-info") { lockBubble(v, el); }
  else if (a === "lock-settings") { S.bubble = null; render(); openSegSettings(v); return; }
  else if (a === "new-seg") { var ng = newSegment(); notify(ng.name + " created. Move Zones into it from the selection bar."); }
  else if (a === "seg-settings") { openSegSettings(v); return; }
  else if (a === "seg-delete") { if (el.getAttribute("aria-disabled") === "true") return; confirmDeleteSeg(v); return; }
  else return;
  render();
});
document.addEventListener("change", function (e) {
  var el = e.target, a = el.getAttribute("data-act"), v = el.getAttribute("data-v"); if (!a) return;
  if (a === "zone-program") assignProgram(S.zones.filter(function (z) { return z.id === v; }), el.value);
  else if (a === "bulk-program") assignProgram(S.zones.filter(function (z) { return S.checked[z.id]; }), el.value);
  else if (a === "sp-flow") {
    var hf = findSpace(v), was = zoneDetailed(hf.z);
    hf.sp[el.getAttribute("data-k")] = el.value === "" ? null : Math.max(0, parseFloat(el.value) || 0);
    var others = hf.z.spaces.filter(function (x) { return x !== hf.sp && !hasRate(x); }).length;
    if (!was && zoneDetailed(hf.z)) notify(hf.z.name + " now uses detailed airflows" + (others ? ": its other " + (others === 1 ? "Space exports" : others + " Spaces export") + " 0 until you enter " + (others === 1 ? "its rates." : "theirs.") : "."));
    else if (was && !zoneDetailed(hf.z)) notify(hf.z.name + " uses its Program's airflow again.");
  }
  else if (a === "zone-dwelling") { assignDwelling(S.zones.filter(function (z) { return z.id === v; }), el.value); S.bubble = null; }
  else if (a === "bulk-dwelling") assignDwelling(S.zones.filter(function (z) { return S.checked[z.id]; }), el.value);
  else if (a === "bulk-set") { var zs = S.zones.filter(function (z) { return S.checked[z.id]; }); zs.forEach(function (z) { z.set = el.value === "none" ? null : el.value; if (z.dwelling) dw(z.dwelling).set = z.set; }); notify("Equipment Set changed on " + zs.length + " Zones."); }
  else if (a === "zone-set") { var z = S.zones.filter(function (x) { return x.id === v; })[0]; z.set = el.value || null; if (z.dwelling) { dw(z.dwelling).set = z.set; zonesOfDwelling(z.dwelling).forEach(function (o) { o.set = z.set; }); } }
  else if (a === "beds" || a === "occ") { var zz = S.zones.filter(function (x) { return x.id === v; })[0]; zz[a] = el.value === "" ? null : parseFloat(el.value); }
  else if (a === "bulk-seg") { moveZones(S.zones.filter(function (z) { return S.checked[z.id]; }), el.value); }
  else if (a === "seg-rename") { if (S.renaming !== v) return; var nm = el.value.trim(); if (nm) seg(v).name = nm; S.renaming = null; }
  else if (a === "house-beds") { house(seg(v)).beds = el.value === "" ? null : parseFloat(el.value); }
  else if (a === "house-occ") { house(seg(v)).occ = el.value === "" ? null : parseFloat(el.value); }
  else if (a === "house-set") { house(seg(v)).set = el.value || null; }
  else if (a === "dw-beds") { dw(v).beds = el.value === "" ? null : parseFloat(el.value); S.bubble = null; }
  else if (a === "units") { dw(v).units = Math.max(1, parseInt(el.value, 10) || 1); S.bubble = null; }
  else if (a === "lib-source") { S.lib = el.value; }
  else if (a === "load-value") { var p = prog(S.selProgram); p[el.getAttribute("data-load")][el.getAttribute("data-key")] = el.value === "" || el.value === "?" ? null : parseFloat(el.value); }
  else if (a === "sched-value") { var sc = schedById(S.selSchedule); if (el.getAttribute("data-block") === "vent") sc.vent[el.getAttribute("data-key")] = parseFloat(el.value); else { sc.ph[el.getAttribute("data-key")] = parseFloat(el.value); if (el.getAttribute("data-key") === "days") sc.ph.daysYear = null; } }
  else if (a === "vent-period") { var vs = schedById(S.selSchedule); vs.vent.periods[+el.getAttribute("data-i")][el.getAttribute("data-k")] = Math.max(0, parseFloat(el.value) || 0); }
  else return;
  render();
});
document.addEventListener("input", function (e) {
  if (e.target.getAttribute("data-act") === "lib-search") { S.libQuery = e.target.value; var pos = e.target.selectionStart; render(); var i = document.querySelector('[data-act="lib-search"]'); i.focus(); i.setSelectionRange(pos, pos); }
});
document.addEventListener("keydown", function (e) {
  if (e.key === "Enter" && e.target.getAttribute("data-act") === "seg-rename") { e.target.blur(); return; }
  if (e.key === "Escape") { if (S.renaming) S.renaming = null; else if (S.bubble) S.bubble = null; else S.checked = {}; render(); }
});

// ---------------------------------------------------------------- replay steps for `do=` (scenes.js)
var STEPS = {
  checkall: function () { var all = S.zones; all.forEach(function (z) { S.checked[z.id] = 1; }); },
  house3: function () { house(S.segments[0]).beds = 3; },
  unsingle: function () { S.segments[0].single = false; },
  trysingle: function () { return function () { confirmSingle(S.segments[0], singleChanges(S.segments[0])); }; },
  adu: function () { var ag = newSegment(); ag.name = "ADU"; S.renaming = null; S.zones.push({ id: id("zn"), name: "ADU studio", seg: ag.id, area: 38, icfa: 35.2, program: null, dwelling: null, beds: null, occ: null, set: null }, { id: id("zn"), name: "ADU bath", seg: ag.id, area: 6, icfa: 5.6, program: null, dwelling: null, beds: null, occ: null, set: null }); applySingle(ag); house(ag).beds = 1; },
  shared: function () { var all = S.zones; assignDwelling(all, "shared"); S.checked = {}; },
  each: function () { var all = S.zones; assignDwelling(all.filter(function (z) { return /^Apt/.test(z.name); }), "each"); },
  beds: function () { var all = S.zones; all.forEach(function (z, i) { if (/^Bedroom/.test(z.name)) z.beds = 1; if (/^Apt/.test(z.name)) z.beds = [1, 2, 1, 2][i % 4]; }); },
  common: function () { var all = S.zones; assignProgram(all.filter(function (z) { return /Corridor/.test(z.name); }), "lib:mf:Indoor Corridor");
      assignProgram(all.filter(function (z) { return /Stair/.test(z.name); }), "lib:mf:Indoor Stair");
      assignProgram(all.filter(function (z) { return /Lobby/.test(z.name); }), "lib:mf:Common Mail");
      assignProgram(all.filter(function (z) { return /office/.test(z.name); }), "lib:mf:Common Office");
      assignProgram(all.filter(function (z) { return /Fitness/.test(z.name); }), "lib:mf:Workout Room"); },
  checkcorr: function () { var all = S.zones; all.forEach(function (z) { if (/Corridor/.test(z.name)) S.checked[z.id] = 1; }); },
  school: function () { var all = S.zones; assignProgram(all.filter(function (z) { return /Classroom/.test(z.name); }), "lib:nr:Classroom");
      assignProgram(all.filter(function (z) { return /Hallway/.test(z.name); }), "lib:nr:Hallway");
      assignProgram(all.filter(function (z) { return /Restroom/.test(z.name); }), "lib:nr:Restroom Public");
      assignProgram(all.filter(function (z) { return /office/.test(z.name); }), "lib:nr:Office Workspace Closed");
      assignProgram(all.filter(function (z) { return /Gym/.test(z.name); }), "lib:nr:Gym"); },
  libnr: function () { S.tab = "programs"; S.ptab = "programs"; S.lib = "nr"; var cl = programByName("Classroom"); if (cl) S.selProgram = cl.id; },
  custom: function () { S.tab = "programs"; S.ptab = "programs"; var cp = phiusProgram("custom", ["Wet lab", 0.05, 7, 19, 250, 0.8, 9, 12, 25]); cp.name = "Wet lab"; cp.vent = { pp: 30, pa: 3.6, pz: 0, ach: 0, sched: cp.people.sched }; S.programs.push(cp); S.selProgram = cp.id; },
  customsched: function () { S.ptab = "schedules"; S.selSchedule = prog(S.selProgram).people.sched; },
  pdefault: function () { S.tab = "programs"; S.ptab = "programs"; S.selProgram = "pgm_default"; },
  sets: function () { S.tab = "programs"; S.ptab = "sets"; },
  lockinfo: function () { return function () { var c = document.querySelector('.zp-locked'); if (c) { lockBubble(c.getAttribute("data-v"), c); render(); } }; },
  spaces: function () { S.ztab = "spaces"; },
  devedit: function () { return function () { deviceDialog("set_sfh", 3); }; },
  devadd: function () { return function () { deviceDialog("set_sfh", null); }; },
  cards: function () { S.openCards.people = true; S.openCards.vent = true; },
  ventsched: function () { S.tab = "programs"; S.ptab = "schedules"; S.selSchedule = S.schedules.filter(function (x) { return x.name === "SFH ventilation"; })[0].id; },
  cascade: function () { S.zones.forEach(function (z) {
      if (S.journey === 3 && z.name !== "Apt 101") return;
      z.spaces.forEach(function (sp) {
        if (sp.name === "Living") sp.sup = 40; else if (/^Bedroom/.test(sp.name)) sp.sup = 30;
        else if (sp.name === "Kitchen") sp.eta = 60; else if (sp.name === "Bath") sp.eta = 40; else if (sp.name === "Hall") sp.tran = 30;
      });
    }); },
  longname: function () { S.segments[0].name = "Elementary School, Building A (classrooms, gym and canteen)"; },
  moveshed: function () { S.zones.forEach(function (z) { if (z.name === "Bike shed") z.seg = null; }); },
  checkshed: function () { S.zones.forEach(function (z) { if (z.name === "Bike shed") S.checked[z.id] = 1; }); },
  newseg: function () { newSegment(); },
  segsettings: function () { return function () { openSegSettings(S.segments[0].id); }; },
  trydelete: function () { S.renaming = null; return function () { confirmDeleteSeg(S.segments[0].id); }; },
  bubble: function () { return function () { var b = document.querySelector('.zp-dwelling[data-act="dwelling"]:not(.is-none)'); if (b) { dwellingBubble(b.getAttribute("data-v"), b); render(); } }; }
};

Mockup.start({
  title: "Programs prototype",
  journeys: [1, 2, 3, 4, 5].map(function (k) { return JOURNEYS[k]; }),
  hint: function (j) { return S.tab === "zones" && S.ztab === "spaces" ? SPACES_HINT : JOURNEYS[j].hint; },
  init: function (j) { S = baseState(j); },
  render: render,
  steps: STEPS,
  scenes: SCENES
});
