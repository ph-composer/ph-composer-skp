"use strict";
/* Programs prototype: the views. Each returns HTML for the state in S (model.js). */
function renderTabs() {
  var tabs = [["zones", "Zones"], ["", "Assemblies"], ["", "Window Types"], ["programs", "Programs"], ["", "Thermal Bridges"], ["", "Library"], ["", "Export"], ["", "Systems"]];
  document.getElementById("app-tabs").innerHTML = tabs.map(function (t) {
    var on = t[0] && t[0] === S.tab;
    return '<button type="button"' + (t[0] ? ' data-act="tab" data-v="' + t[0] + '"' : ' disabled') + ' aria-pressed="' + on + '"' + (on ? ' class="is-active" aria-selected="true"' : '') + '>' + t[1] + '</button>';
  }).join("");
}

// ---------------------------------------------------------------- Zones / Programs view
function programOptions(current, withDefault, mixed) {
  var h = mixed ? '<option value="" selected disabled>Mixed</option>' : "";
  h += '<optgroup label="In this file">';
  S.programs.forEach(function (p) {
    var label = p.id === "pgm_default" ? "Residential (default)" : p.name;
    h += '<option value="pgm:' + p.id + '"' + (!mixed && current === p.id ? " selected" : "") + '>' + esc(label) + '</option>';
  });
  h += '</optgroup>';
  ["mf", "nr"].forEach(function (src) {
    var rows = PHIUS[src].filter(function (r) { return !programByName(r[0]); });
    if (!rows.length) return;
    h += '<optgroup label="' + SOURCES[src] + ' (copies into this file)">' + rows.map(function (r) { return '<option value="lib:' + src + ':' + esc(r[0]) + '">' + esc(r[0]) + '</option>'; }).join("") + '</optgroup>';
  });
  return h;
}
function renderZones() {
  var h = '<div class="phc-heading"><h1>Zones</h1><div class="phc-heading-actions">' + iconBtn("settings", "Programs settings") + '</div></div>';
  h += '<nav class="phc-subtabs" role="tablist" aria-label="Zone views"><button type="button" role="tab" aria-selected="false" aria-pressed="false" disabled>Geometry</button>' + ["spaces", "programs"].map(function (k) { var on = S.ztab === k; return '<button type="button" role="tab" data-act="ztab" data-v="' + k + '" aria-selected="' + on + '" aria-pressed="' + on + '">' + (k === "spaces" ? "Spaces" : "Programs") + '</button>'; }).join("") + '</nav>';
  var nChecked = Object.keys(S.checked).length;
  h += '<div class="phc-inventory-controls">' +
    '<label class="phc-view-control"><input type="search" placeholder="Zone, Program or dwelling" aria-label="Filter Zones"></label>' +
    '<span class="phc-view-count">' + S.segments.length + ' Building Segment' + (S.segments.length > 1 ? "s" : "") + ' · ' + S.zones.length + ' Zones · ' + S.dwellings.length + ' dwellings</span>' +
    iconBtn("add", "New Building Segment", "new-seg") + '</div>';
  if (S.ztab === "spaces") return h + spacesTable() + (S.bubble ? S.bubble.html : "");
  var COLS = [["name", "Name", 140], ["program", "Program", 190], ["dwelling", "Dwelling", 120], ["beds", "Bedrooms", 72, 1], ["occ", "Occupants", 80, 1], ["set", "Equipment Set", 170],
    ["area", "Floor area m²", 84, 1], ["icfa", "iCFA m²", 70, 1], ["people", "People peak", 76, 1], ["light", "Lighting W", 80, 1], ["vent", "Ventilation m³/h", 96, 1]];
  var tips = { area: "Gross Zone floor area: the basis honeybee divides per-area loads by.", icfa: "Weighted Space floor area (iCFA): the basis of the Phius residential rules.",
    people: "Peak people. Residential default: the dwelling's occupants ÷ the presence schedule's mean, shared by gross floor area.", light: "Installed lighting. Per-area Programs: W/m² × gross floor area. Residential default: Phius interior lighting from iCFA and dwellings.",
    vent: "Each Zone's ventilation comes from one of two places: its Program, split by Space floor area, or, once any of its Spaces has a rate in Zones → Spaces, the Spaces' detailed airflows (the larger of supply and extract). The Program's schedule applies either way.", occ: "Average occupants (honeybee-ph number_people). Left empty, the dwelling uses the Phius rule: bedrooms + 1 per unit." };
  var width = 72 + COLS.reduce(function (a, c) { return a + c[2]; }, 0);
  h += '<div class="phc-table-mount" style="--row-actions-width:72px; position:relative"><table class="phc-table is-tree reveals-row-actions zp-table" style="min-width:' + width + 'px"><colgroup><col style="width:72px">' + COLS.map(function (c) { return '<col style="width:' + c[2] + 'px">'; }).join("") + '</colgroup><thead><tr>' +
    '<th class="col-actions"><span class="phc-header-label-row">' + '<input class="row-check" type="checkbox" data-act="check-all" aria-label="Check every Zone"' + (nChecked && nChecked === checkable().length ? " checked" : "") + '>' + '</span></th>' +
    COLS.map(function (c) { return '<th class="' + (c[3] ? "num" : "") + '"' + (tips[c[0]] ? ' data-tip="' + esc(tips[c[0]]) + '"' : "") + '><span class="phc-header-label-row"><span class="phc-th-label">' + c[1] + '</span></span></th>'; }).join("") + '</tr></thead><tbody>';
  S.segments.forEach(function (g) {
    var zs = S.zones.filter(function (z) { return z.seg === g.id; });
    var sum = { beds: 0, occ: 0, area: 0, icfa: 0, people: 0, light: 0, vent: 0, ventMissing: false };
    var seenDw = {};
    zs.forEach(function (z) {
      var d = derived(z); sum.area += z.area; sum.icfa += z.icfa; sum.people += d.people || 0; sum.light += d.lighting || 0; if (d.ventMissing) sum.ventMissing = true; else sum.vent += d.vent;
      if (z.dwelling && !seenDw[z.dwelling]) { seenDw[z.dwelling] = 1; var t = dwellingTotals(z.dwelling); sum.beds += t.beds; sum.occ += t.occ; }
    });
    var sf = segFindings(g);
    h += '<tr class="tier-0 zp-seg"><td class="col-actions">' + segActions(g) + '</td><td colspan="3">' + segHead(g, zs.length, sf) + '</td>' +
      (g.single ? houseCells(g) : '<td class="num">' + (Object.keys(seenDw).length ? fmt(sum.beds) : "") + '</td><td class="num">' + (Object.keys(seenDw).length ? fmt(sum.occ, 1) : "") + '</td><td></td>') +
      (zs.length ? '<td class="num">' + fmt(sum.area, 1) + '</td><td class="num">' + fmt(sum.icfa, 1) + '</td><td class="num">' + fmt(sum.people, 1) + '</td><td class="num">' + fmt(sum.light) + '</td><td class="num">' + (sum.ventMissing ? '<span class="zp-amber">?</span>' : fmt(sum.vent)) + '</td>' : '<td colspan="5"></td>') + '</tr>';
    zs.forEach(function (z) { h += g.single ? frozenRow(z) : zoneRow(z); });
  });
  var out = S.zones.filter(function (z) { return !z.seg; });
  if (out.length) {
    h += '<tr class="tier-0 zp-seg is-none"><td class="col-actions"></td><td colspan="' + COLS.length + '"><div class="zp-seg-name" data-tip="Zones in no Building Segment are left out of export, with their Spaces and thermal bridges. Planned: export them as shading.">No Building Segment<span class="zp-seg-count">' + out.length + ' Zone' + (out.length > 1 ? "s" : "") + ' · left out of export</span></div></td></tr>';
    out.forEach(function (z) {
      var c = !!S.checked[z.id];
      h += '<tr class="tier-1 zp-out' + (c ? " is-checked" : "") + '"><td class="col-actions"><input class="row-check" type="checkbox" data-act="check" data-v="' + z.id + '"' + (c ? " checked" : "") + ' aria-label="Check ' + esc(z.name) + '"></td><td>' + esc(z.name) + '</td><td colspan="5">Not exported</td><td class="num">' + fmt(z.area, 1) + '</td><td class="num">' + fmt(z.icfa, 1) + '</td><td colspan="3"></td></tr>';
    });
  }
  h += '</tbody></table></div>';
  if (nChecked) h += selectionBar(nChecked);
  if (S.bubble) h += S.bubble.html;
  return h;
}
// The Building Segment heading: the name alone on the first line (Delete on hover; rename in settings), then a
// second line with the Default tag and Single dwelling. Its actions sit in the
// row's Actions cell, revealed on hover as in Geometry and Spaces.
function segActions(g) {
  var only = S.segments.length === 1;
  return '<button type="button" class="phc-icon-button row-icon" data-row-action="settings" data-act="seg-settings" data-v="' + g.id + '" aria-label="Building Segment settings" data-tip="Building Segment settings">' + svg("settings", 16) + '</button>' +
    '<button type="button" class="phc-icon-button row-icon row-delete" data-row-action="delete" data-act="seg-delete" data-v="' + g.id + '" aria-label="Delete ' + esc(g.name) + '"' +
    (only ? ' aria-disabled="true" data-tip="A model keeps at least one Building Segment."' : ' data-tip="Delete ' + esc(g.name) + '"') + '>' + svg("del", 16) + '</button>';
}
function segHead(g, n, sf) {
  var name = S.renaming === g.id ? '<input class="zp-seg-rename" data-act="seg-rename" data-v="' + g.id + '" value="' + esc(g.name) + '" aria-label="Building Segment name">' : esc(g.name);
  return '<div class="zp-seg-head"><div class="zp-seg-line1">' +
    (S.renaming === g.id ? name : '<span class="zp-seg-title" data-tip="' + esc(g.name) + '">' + name + '</span>') + (sf.length ? flag(sf.join(" ")) : "") + '</div>' +
    (g.id === S.defaultSeg || g.single ? '<div class="zp-seg-line2">' +
      (g.id === S.defaultSeg ? '<span class="zp-seg-tag" data-tip="New Zones join this Building Segment. Change it in Settings.">Default</span>' : "") +
      (g.single ? '<button type="button" class="zp-seg-tag zp-lock-tag" data-act="lock-info" data-v="' + g.id + '">' + svg("lock", 11) + 'Single dwelling</button>' : "") + '</div>' : "") + '</div>';
}
// A locked value in a Single dwelling Segment: muted, and a click explains the lock and opens the Segment's settings.
function locked(text, g, extraClass) { return '<button type="button" class="zp-frozen zp-locked' + (extraClass ? " " + extraClass : "") + '" data-act="lock-info" data-v="' + g.id + '">' + text + '</button>'; }
function lockBubble(gid, anchor) {
  var g = seg(gid), r = anchor.getBoundingClientRect(), pr = document.getElementById("pane").getBoundingClientRect();
  var left = Math.min(r.left - pr.left, pr.width - 290);
  S.bubble = { html: '<div class="zp-bubble zp-lock-bubble" style="left:' + left + 'px; top:' + (r.bottom - pr.top + 4) + 'px" role="dialog" aria-label="' + esc(g.name) + ' is a single dwelling">' +
    '<h3>' + svg("home", 13) + ' ' + esc(g.name) + ' is a single dwelling</h3>' +
    '<p>Its Zones are one dwelling with the residential default Program. Bedrooms, occupants and the Equipment Set are entered once, on the Segment row.</p>' +
    '<div class="zp-bubble-actions"><button type="button" class="primary" data-act="lock-settings" data-v="' + g.id + '">Open settings</button></div></div>' };
}
// Zones a check can select: those in a Single dwelling Segment are locked.
function checkable() { return S.zones.filter(function (z) { return !(z.seg && seg(z.seg).single); }); }
function freeSegName() { var n = S.segments.length + 1, nm; do { nm = "Building Segment " + n; n += 1; } while (S.segments.some(function (g) { return g.name === nm; })); return nm; }
function newSegment() { var g = segRecord(freeSegName(), "res"); S.segments.push(g); S.renaming = g.id; return g; }
function moveZones(zs, v) {
  var target = v === "new" ? newSegment() : v === "none" ? null : seg(v);
  zs.forEach(function (z) {
    var from = z.seg ? seg(z.seg) : null;
    if (from && from.single && from !== target) { z.dwelling = null; }
    z.seg = target ? target.id : null;
    if (target && target.single) { z.dwelling = target.house; z.program = null; z.set = null; z.beds = null; z.occ = null; }
  });
  S.dwellings = S.dwellings.filter(function (d) { return S.zones.some(function (z) { return z.dwelling === d.id; }); });
  S.checked = {};
  notify(zs.length + " Zone" + (zs.length > 1 ? "s" : "") + (target ? " moved to " + target.name + "." : (zs.length > 1 ? " are" : " is") + " now in no Building Segment and left out of export."));
}
function opt(v, cur, label) { return '<option value="' + esc(v) + '"' + (v === cur ? " selected" : "") + '>' + esc(label || v) + '</option>'; }
function row(label, control) { return '<span>' + label + '</span><span>' + control + '</span>'; }
function openSegSettings(gid) {
  var g = seg(gid), zs = S.zones.filter(function (z) { return z.seg === gid; }), units = 0, seen = {};
  zs.forEach(function (z) { if (z.dwelling && !seen[z.dwelling]) { seen[z.dwelling] = 1; units += dw(z.dwelling).units; } });
  var isDefault = g.id === S.defaultSeg, hd = g.single ? house(g) : null;
  var progOpts = S.programs.map(function (p) { return opt(p.id, g.defProgram || "pgm_default", p.name); }).join("");
  var winds = ["Several sides exposed, no screening", "Several sides exposed, moderate screening", "Several sides exposed, high screening", "One side exposed, no screening", "One side exposed, moderate screening", "One side exposed, high screening", "User defined"];
  var dlg = document.createElement("dialog");
  dlg.className = "phc-dialog zp-segdlg";
  dlg.innerHTML = '<button type="button" class="phc-dialog-close" aria-label="Close" data-dlg="cancel">' + svg("clear", 18) + '</button><h2>Building Segment settings</h2>' +
    '<div class="zp-segdlg-body">' +
    '<section><h3>General</h3><div class="zp-grid">' +
      row("Name", '<input name="name" value="' + esc(g.name) + '">') +
      row("New Zones join this Segment", '<input type="checkbox" name="isDefault"' + (isDefault ? " checked disabled" : "") + '>' + (isDefault ? ' <span class="zp-muted">To change it, make another Segment the default.</span>' : "")) +
      row("Zones", zs.length + (zs.length ? "" : ' <span class="zp-amber">: left out of export</span>')) + '</div></section>' +
    '<section><h3>Occupancy</h3><div class="zp-grid">' +
      row("Single dwelling", '<input type="checkbox" name="single"' + (g.single ? " checked" : "") + (g.category === "nonres" && !g.single ? ' disabled' : "") + '> <span class="zp-muted">' +
        (g.category === "nonres" && !g.single ? "Residential Building Segments only." : "Its Zones are one dwelling with the residential default.") + '</span>') +
      row("Default Program for its Zones", '<select name="defProgram"' + (g.single ? ' disabled data-tip="Single dwelling uses the residential default."' : ' data-tip="Zones with no Program of their own use this one."') + '>' + progOpts + '</select>') +
      (hd ? row("Bedrooms in " + esc(hd.name), '<input class="zp-num" name="beds" value="' + (hd.beds === null ? "" : hd.beds) + '" placeholder="?">') +
            row("Occupants", '<input class="zp-num" name="occ" value="' + (hd.occ === null ? "" : hd.occ) + '" placeholder="Phius rule">') +
            row("Equipment Set", '<select name="set">' + opt("", hd.set || "", "Phius single-family default") + S.sets.filter(function (x) { return x.id !== "set_sfh"; }).map(function (x) { return opt(x.id, hd.set || "", x.name); }).join("") + '</select>')
          : row("Bedrooms and appliances", '<span class="zp-muted">Per dwelling, in the Zones table.</span>')) +
      row("Dwelling units", '<span data-tip="Counted from the dwellings its Zones make up (num_dwelling_units).">' + units + '</span>') + '</div></section>' +
    '<section><h3>Phius certification</h3><div class="zp-grid">' +
      row("Building category", '<select name="category"' + (g.single ? ' disabled data-tip="Residential: set by Single dwelling."' : "") + '>' + opt("res", g.category, "Residential") + opt("nonres", g.category, "Non-residential") + '</select>') +
      row("Certification program", '<select name="cert">' + ["Phius 2021 CORE", "Phius 2021 ZERO", "Phius 2018 CORE", "Phius 2018 ZERO"].map(function (x) { return opt(x, g.cert); }).join("") + '</select>') +
      row("Building use", '<select name="use">' + ["Residential", "Office / administrative", "School", "Other"].map(function (x) { return opt(x, g.use); }).join("") + '</select>') +
      row("Building status", '<select name="status">' + ["In planning", "Under construction", "Complete"].map(function (x) { return opt(x, g.status); }).join("") + '</select>') +
      row("Building type", '<select name="type">' + ["New construction", "Retrofit", "Mixed"].map(function (x) { return opt(x, g.type); }).join("") + '</select>') + '</div></section>' +
    '<section><h3>Airtightness</h3><div class="zp-grid">' +
      row("Test result", '<select name="airKind" style="width:70px">' + opt("n50", g.air.kind) + opt("q50", g.air.kind) + '</select> <input class="zp-num" name="airValue" value="' + (g.air.value === null ? "" : g.air.value) + '" placeholder="?"> <span class="zp-muted">' + (g.air.kind === "n50" ? "1/h" : "m³/h·m²") + '</span>') +
      row("Wind exposure", '<select name="wind">' + winds.map(function (x) { return opt(x, g.wind); }).join("") + '</select>') + '</div>' +
      '<p class="zp-later" style="margin:8px 0 0">Converted at export into each Zone\'s Infiltration, replacing the Program\'s value.</p></section>' +
    '<section><h3>Comfort</h3><div class="zp-grid">' +
      row("Set points, winter / summer", (zs.length ? setpointsFor(g) : "—") + ' <span class="zp-muted">from the Zones\' Programs</span>') +
      row("Mechanical cooling", '<input type="checkbox" name="mechCool"' + (g.mechCool ? " checked" : "") + '>') +
      row("Mechanical room temperature [°C]", '<input class="zp-num" name="mechRoom" value="' + g.mechRoom + '">') + '</div></section>' +
    '<section><h3>Planned</h3><div class="zp-grid">' +
      row("Floor levels", '<span class="zp-later">Counted from Levels</span>') +
      row("Site and climate", '<span class="zp-later">Phase 5.1</span>') +
      row("Summer ventilation", '<span class="zp-later">Phase 4</span>') +
      row("Source energy and CO₂ factors", '<span class="zp-later">Not scheduled</span>') + '</div></section>' +
    '</div><div class="phc-dialog-actions"><button type="button" data-dlg="cancel">Cancel</button><button type="button" class="primary" data-dlg="ok">Save</button></div>';
  document.body.appendChild(dlg);
  function val(n) { var el = dlg.querySelector('[name="' + n + '"]'); return el ? (el.type === "checkbox" ? el.checked : el.value) : undefined; }
  dlg.addEventListener("click", function (e) {
    var b = e.target.closest("[data-dlg]"); if (!b) return;
    if (b.getAttribute("data-dlg") === "ok") {
      g.name = val("name").trim() || g.name;
      if (val("isDefault")) S.defaultSeg = g.id;
      if (!g.single) { g.category = val("category"); g.defProgram = val("defProgram") === "pgm_default" ? null : val("defProgram"); }
      g.cert = val("cert"); g.use = val("use"); g.status = val("status"); g.type = val("type"); g.wind = val("wind"); g.mechCool = val("mechCool");
      g.air = { kind: val("airKind"), value: val("airValue") === "" ? null : parseFloat(val("airValue")) };
      g.mechRoom = parseFloat(val("mechRoom")) || g.mechRoom;
      if (hd) { hd.beds = val("beds") === "" ? null : parseFloat(val("beds")); hd.occ = val("occ") === "" ? null : parseFloat(val("occ")); hd.set = val("set") || null; }
      notify(g.name + " saved.");
      var wantSingle = val("single");
      if (wantSingle === false && g.single) { g.single = false; notify(g.name + " saved. Single dwelling is off; its dwelling and the residential default stay."); }
      else if (wantSingle === true && !g.single) {
        var ch = singleChanges(g); dlg.close(); dlg.remove();
        if (ch.length) { render(); confirmSingle(g, ch); return; }
        applySingle(g); render(); return;
      }
    }
    dlg.close(); dlg.remove(); render();
  });
  dlg.addEventListener("cancel", function () { dlg.remove(); render(); });
  dlg.showModal();
}
function deviceDialog(setId, idx) {
  var x = setById(setId), adding = idx === null, d = adding ? newDevice("dishwasher") : JSON.parse(JSON.stringify(x.devices[idx]));
  var dlg = document.createElement("dialog");
  dlg.className = "phc-dialog zp-segdlg zp-devdlg";
  function num(k, label, unit, v, tip) { return row(label + (unit ? " [" + unit + "]" : ""), '<input class="zp-num" name="' + k + '" value="' + (v === undefined || v === null ? "" : v) + '"' + (tip ? ' data-tip="' + esc(tip) + '"' : "") + '>'); }
  function sel(k, label, opts, v) { return row(label, '<select name="' + k + '">' + opts.map(function (o) { var val = typeof o === "object" ? o[0] : o, lab = typeof o === "object" ? o[1] : o; return '<option value="' + esc(val) + '"' + (String(val) === String(v) ? " selected" : "") + '>' + esc(lab) + '</option>'; }).join("") + '</select>'); }
  function body() {
    var ty = devType(d.type);
    var h = '<section><h3>Device</h3><div class="zp-grid">' +
      (adding ? sel("type", "Type", DEVICE_TYPES.map(function (y) { return [y.id, y.label]; }), d.type) : row("Type", esc(ty.label) + ' <span class="zp-muted">To change the type, delete and add.</span>')) +
      row("Name", '<input name="name" value="' + esc(d.name) + '">') +
      num("qty", "Quantity", "", d.qty, "The number of units; the energy demand is for one unit.") +
      row("In conditioned space", '<input type="checkbox" name="inside"' + (d.inside ? " checked" : "") + '> <span class="zp-muted">Its waste heat counts as an internal gain.</span>') +
      row("Comment", '<input name="comment" value="' + esc(d.comment || "") + '" placeholder="Shown in WUFI-Passive and METr">') + '</div></section>';
    h += '<section><h3>Energy</h3><div class="zp-grid">' +
      sel("ref", "Reference quantity", ty.rq.map(function (c) { return [c, REFQ[c]]; }), d.ref);
    if (ty.rule) h += row("Energy demand", '<span style="color:#0b5360">' + svg("sigma", 12) + ' ' + esc(ty.rule) + '</span> <span class="zp-muted">Calculated by WUFI-Passive and METr from the reference quantity.</span>');
    else {
      if (ty.norms && ty.norms.length > 1) h += sel("norm", "Energy demand per", ty.norms, d.norm);
      h += num("demand", ty.demand.label, /fridge|freezer/.test(ty.id) ? (d.norm === "Per day" ? "kWh/d" : "kWh/a") : ty.demand.unit, d.demand);
    }
    h += '</div></section>';
    var extra = (ty.extra || []).filter(function (e) { return !e.when || d.dryer_type === e.when; });
    if (extra.length) h += '<section><h3>' + esc(ty.label) + '</h3><div class="zp-grid">' + extra.map(function (e) { return e.options ? sel(e.k, e.label, e.options, d[e.k]) : num(e.k, e.label, e.unit, d[e.k]); }).join("") + '</div></section>';
    if (ty.perUse) h += '<section><h3>PHPP only</h3><div class="zp-grid">' + num("perUse", ty.perUse.label, ty.perUse.unit, d.perUse, "PHPP reads this; WUFI-Passive and METr ignore it.") + '</div></section>';
    return h;
  }
  function paint() {
    dlg.innerHTML = '<button type="button" class="phc-dialog-close" aria-label="Close" data-dlg="cancel">' + svg("clear", 18) + '</button><h2>' + (adding ? "Add device to " + esc(x.name) : "Edit " + esc(d.name)) + '</h2>' +
      '<div class="zp-segdlg-body">' + body() + '</div><p class="cell-error zp-devdlg-error" role="status"></p><div class="phc-dialog-actions"><button type="button" data-dlg="cancel">Cancel</button><button type="button" class="primary" data-dlg="ok">' + (adding ? "Add device" : "Save") + '</button></div>';
  }
  function read() {
    var q = function (n) { return dlg.querySelector('[name="' + n + '"]'); };
    Array.prototype.forEach.call(dlg.querySelectorAll("[name]"), function (el) {
      var n = el.getAttribute("name"); if (n === "type") return;
      if (el.type === "checkbox") d.inside = el.checked;
      else if (el.tagName === "SELECT") d[n] = n === "ref" ? +el.value : el.value;
      else if (n === "name" || n === "comment") d[n] = el.value;
      else d[n] = el.value === "" ? null : parseFloat(el.value);
    });
    return q;
  }
  paint();
  document.body.appendChild(dlg);
  dlg.addEventListener("change", function (e) {
    var n = e.target.getAttribute("name");
    if (n === "type") { var nm = d.name; var was = devType(d.type).label; d = newDevice(e.target.value); if (nm && nm !== was) d.name = nm; paint(); }
    else if (n === "norm" || n === "dryer_type") { read(); paint(); }
  });
  dlg.addEventListener("click", function (e) {
    var b = e.target.closest("[data-dlg]"); if (!b) return;
    if (b.getAttribute("data-dlg") === "ok") {
      read();
      var bad = !d.name.trim() ? "Enter a name." : !(d.qty >= 1) ? "Quantity is a whole number of at least 1." : (d.demand !== undefined && !(d.demand >= 0)) ? "Enter the energy demand." : null;
      if (bad) { dlg.querySelector(".zp-devdlg-error").textContent = bad; return; }
      d.qty = Math.round(d.qty);
      if (adding) x.devices.push(d); else x.devices[idx] = d;
      notify((adding ? "Added " : "Saved ") + d.name + (adding ? " to " + x.name + "." : "."));
    }
    dlg.close(); dlg.remove(); render();
  });
  dlg.addEventListener("cancel", function () { dlg.remove(); render(); });
  dlg.showModal();
}
function confirmDeleteDevice(setId, idx) {
  var x = setById(setId), d = x.devices[idx], users = S.dwellings.filter(function (w) { return w.set === setId; }).length;
  var dlg = document.createElement("dialog");
  dlg.className = "phc-dialog phc-confirm-dialog zp-confirm";
  dlg.innerHTML = '<button type="button" class="phc-dialog-close" aria-label="Close" data-dlg="cancel">' + svg("clear", 18) + '</button><h2>Delete ' + esc(d.name) + '?</h2>' +
    '<p>It is removed from ' + esc(x.name) + (users ? ", and from the " + users + " dwelling" + (users > 1 ? "s" : "") + " that use it" : "") + '.</p>' +
    '<div class="phc-dialog-actions"><button type="button" data-dlg="cancel">Cancel</button><button type="button" class="primary" data-dlg="ok">Delete</button></div>';
  document.body.appendChild(dlg);
  dlg.addEventListener("click", function (e) {
    var b = e.target.closest("[data-dlg]"); if (!b) return;
    if (b.getAttribute("data-dlg") === "ok") { x.devices.splice(idx, 1); notify("Deleted " + d.name + " from " + x.name + "."); }
    dlg.close(); dlg.remove(); render();
  });
  dlg.addEventListener("cancel", function () { dlg.remove(); render(); });
  dlg.showModal();
}
function confirmDeleteSeg(gid) {
  var g = seg(gid), zs = S.zones.filter(function (z) { return z.seg === gid; }), others = S.segments.filter(function (o) { return o.id !== gid; });
  var pick = (S.defaultSeg !== gid ? S.defaultSeg : others[0].id);
  var dlg = document.createElement("dialog");
  dlg.className = "phc-dialog phc-confirm-dialog zp-confirm";
  dlg.innerHTML = '<button type="button" class="phc-dialog-close" aria-label="Close" data-dlg="cancel">' + svg("clear", 18) + '</button><h2>Delete ' + esc(g.name) + '?</h2>' +
    (zs.length ? '<p><label>Its ' + zs.length + ' Zone' + (zs.length > 1 ? "s move" : " moves") + ' to <select name="to">' + others.map(function (o) { return opt(o.id, pick, o.name); }).join("") + '<option value="none">No Building Segment (left out of export)</option></select></label></p>' : '<p>It holds no Zones.</p>') +
    '<p class="zp-muted">Its settings go with it: certification, airtightness and comfort values.' + (g.id === S.defaultSeg ? " New Zones will join the Segment its Zones move to." : "") + '</p>' +
    '<div class="phc-dialog-actions"><button type="button" data-dlg="cancel">Cancel</button><button type="button" class="primary" data-dlg="ok">Delete</button></div>';
  document.body.appendChild(dlg);
  dlg.addEventListener("click", function (e) {
    var b = e.target.closest("[data-dlg]"); if (!b) return;
    if (b.getAttribute("data-dlg") === "ok") {
      var sel = dlg.querySelector('[name="to"]'), to = sel ? sel.value : pick;
      zs.forEach(function (z) { z.seg = to === "none" ? null : to; });
      S.segments = others;
      if (S.defaultSeg === gid) S.defaultSeg = to !== "none" ? to : others[0].id;
      notify(g.name + " deleted." + (zs.length ? " Its Zones moved to " + (to === "none" ? "no Building Segment." : seg(to).name + ".") : ""));
    }
    dlg.close(); dlg.remove(); render();
  });
  dlg.addEventListener("cancel", function () { dlg.remove(); render(); });
  dlg.showModal();
}
// ---------------------------------------------------------------- Zones / Spaces view: airflow per Space
// Q4a-29/30: a Zone is By Program until any of its Spaces has a rate; then it uses detailed airflows and every
// Space exports its own rates, 0 where blank. The words in the cells show the mode; no Airflow column.
function hasRate(sp) { return !(sp.sup === null && sp.eta === null && sp.tran === null); }
function zoneDetailed(z) { return (z.spaces || []).some(hasRate); }
function findSpace(spid) { var hit = null; S.zones.forEach(function (z) { (z.spaces || []).forEach(function (sp) { if (sp.id === spid) hit = { z: z, sp: sp }; }); }); return hit; }
var SPACES_HINT = "<em>Spaces</em>: airflows read <em>By Program</em> until you <em>type a rate</em> on any Space. Its Zone then uses detailed airflows: every Space in it exports its own rates, 0 where blank. Hover that Zone for <em>From Program</em>.";
function spacesTable() {
  var COLS = [["name", "Name", 220], ["area", "Floor area m²", 96, 1], ["icfa", "iCFA m²", 80, 1], ["vol", "Net volume m³", 100, 1], ["sup", "Supply m³/h", 100, 1], ["eta", "Extract m³/h", 100, 1], ["tran", "Transfer m³/h", 104, 1]];
  var tips = { sup: "By Program until a Space in the Zone has a rate; then each Space's own rate, 0 where blank.", tran: "Transfer air reaches PHPP only. WUFI-Passive and METr receive supply and extract." };
  var width = 72 + COLS.reduce(function (a, c) { return a + c[2]; }, 0);
  var h = '<div class="phc-table-mount" style="--row-actions-width:72px; position:relative"><table class="phc-table is-tree reveals-row-actions zp-table zp-spaces" style="min-width:' + width + 'px"><colgroup><col style="width:72px">' + COLS.map(function (c) { return '<col style="width:' + c[2] + 'px">'; }).join("") + '</colgroup><thead><tr><th class="col-actions"></th>' +
    COLS.map(function (c) { return '<th class="' + (c[3] ? "num" : "") + '"' + (tips[c[0]] ? ' data-tip="' + esc(tips[c[0]]) + '"' : "") + '><span class="phc-header-label-row"><span class="phc-th-label">' + c[1] + '</span></span></th>'; }).join("") + '</tr></thead><tbody>';
  var DASH = function (tip) { return '<span class="zp-muted" data-tip="' + esc(tip) + '">—</span>'; };
  function sums(zs) {
    var o = { area: 0, icfa: 0, vol: 0, sup: 0, eta: 0, tran: 0, byProgram: false };
    zs.forEach(function (z) { if (z.spaces.length && !zoneDetailed(z)) o.byProgram = true; z.spaces.forEach(function (sp) { o.area += sp.area; o.icfa += sp.icfa; o.vol += sp.vol; o.sup += sp.sup || 0; o.eta += sp.eta || 0; o.tran += sp.tran || 0; }); });
    return o;
  }
  function numCells(o, tip) {
    var flow = function (v) { return o.byProgram ? DASH(tip) : fmt(v); };
    return '<td class="num">' + fmt(o.area, 1) + '</td><td class="num">' + fmt(o.icfa, 1) + '</td><td class="num">' + fmt(o.vol, 1) + '</td><td class="num">' + flow(o.sup) + '</td><td class="num">' + flow(o.eta) + '</td><td class="num">' + flow(o.tran) + '</td>';
  }
  function zoneRows(z, exported) {
    var p = effectiveProgram(z), detailed = zoneDetailed(z), out = '';
    out += '<tr class="tier-1 zp-zone-row' + (exported ? "" : " zp-out") + '"><td class="col-actions">' + (exported && detailed ? '<button type="button" class="phc-icon-button row-icon" data-row-action="reset" data-act="zone-reset" data-v="' + z.id + '" aria-label="From Program: clear every Space\'s rates in ' + esc(z.name) + '" data-tip="From Program: clear every Space\'s rates">' + svg("reset", 16) + '</button>' : "") + '</td>' +
      '<td>' + esc(z.name) + '</td>' + numCells(sums([z]), "By Program: " + p.name + "'s ventilation, split by Space floor area. Zones → Programs shows its total.") + '</tr>';
    if (!z.spaces.length) out += '<tr class="tier-2 zp-nospace"><td class="col-actions"></td><td colspan="' + COLS.length + '"><span class="zp-sp-name">' + flag("No Spaces: this Zone exports its geometry to WUFI-Passive and METr with no iCFA, net volume or ventilation. Allowed, with an export warning (Q4a-32). Add Spaces before calculating.") + ' No Spaces</span></td></tr>';
    z.spaces.forEach(function (sp) {
      function cell(k) {
        if (!exported) return '<td class="num zp-muted">—</td>';
        if (!detailed) return '<td class="num phc-editable-cell"><input class="phc-cell-input zp-flow is-inherit" data-act="sp-flow" data-v="' + sp.id + '" data-k="' + k + '" value="" placeholder="By Program" aria-label="' + esc(sp.name) + ' ' + k + '" data-tip="' + esc("By " + p.name + ": its ventilation split by floor area, with its schedule. Type a rate and " + z.name + " switches to detailed airflows: every Space exports its own rates, 0 where blank.") + '"></td>';
        return '<td class="num phc-editable-cell"><input class="phc-cell-input zp-flow" data-act="sp-flow" data-v="' + sp.id + '" data-k="' + k + '" value="' + (sp[k] === null ? "" : sp[k]) + '" placeholder="0" aria-label="' + esc(sp.name) + ' ' + k + '"' + (sp[k] === null ? ' data-tip="Blank exports 0: ' + esc(z.name) + ' uses detailed airflows."' : "") + '></td>';
      }
      out += '<tr class="tier-2"><td class="col-actions"></td><td><span class="zp-sp-name">' + sp.num + ' ' + esc(sp.name) + '</span></td>' +
        '<td class="num">' + fmt(sp.area, 1) + '</td><td class="num">' + fmt(sp.icfa, 1) + '</td><td class="num">' + fmt(sp.vol, 1) + '</td>' + cell("sup") + cell("eta") + cell("tran") + '</tr>';
    });
    return out;
  }
  S.segments.forEach(function (g) {
    var zs = S.zones.filter(function (z) { return z.seg === g.id; });
    h += '<tr class="tier-0 zp-seg"><td class="col-actions">' + segActions(g) + '</td><td>' + segHead(g, zs.length, []) + '</td>' + (zs.length ? numCells(sums(zs), "Some Zones here are By Program. Zones → Programs shows their ventilation.") : '<td colspan="6"></td>') + '</tr>';
    zs.forEach(function (z) { h += zoneRows(z, true); });
  });
  var outZ = S.zones.filter(function (z) { return !z.seg; });
  if (outZ.length) {
    h += '<tr class="tier-0 zp-seg is-none"><td class="col-actions"></td><td colspan="' + COLS.length + '"><div class="zp-seg-name" data-tip="Zones in no Building Segment are left out of export.">No Building Segment<span class="zp-seg-count">' + outZ.length + ' Zone' + (outZ.length > 1 ? "s" : "") + ' · left out of export</span></div></td></tr>';
    outZ.forEach(function (z) { h += zoneRows(z, false); });
  }
  return h + '</tbody></table></div>';
}
// Single dwelling: the Building Segment row is the house row. Its Bedrooms, Occupants and Equipment Set
// cells are the only inputs on the page.
function house(g) { return dw(g.house); }
function houseCells(g) {
  var d = house(g), t = dwellingTotals(d.id);
  var setOpts = '<option value="">Phius single-family default</option>' + S.sets.filter(function (x) { return x.id !== "set_sfh"; }).map(function (x) { return '<option value="' + x.id + '"' + (d.set === x.id ? " selected" : "") + '>' + esc(x.name) + '</option>'; }).join("");
  return '<td class="num phc-editable-cell"><input class="phc-cell-input' + (d.beds === null ? " zp-need" : "") + '" data-act="house-beds" data-v="' + g.id + '" value="' + (d.beds === null ? "" : d.beds) + '" placeholder="?" aria-label="Bedrooms in ' + esc(d.name) + '" data-tip="' + (d.beds === null ? "Set the number of bedrooms in the house." : "Bedrooms in the whole house.") + '"></td>' +
    '<td class="num phc-editable-cell"><input class="phc-cell-input" data-act="house-occ" data-v="' + g.id + '" value="' + (d.occ === null ? "" : d.occ) + '" placeholder="' + fmt(t.occ, 1) + '" aria-label="Occupants in ' + esc(d.name) + '" data-tip="Average occupants. Left empty: the Phius rule, bedrooms + 1."></td>' +
    '<td class="phc-editable-cell"><select class="phc-enum-cell" data-act="house-set" data-v="' + g.id + '" aria-label="Equipment Set for ' + esc(d.name) + '" data-tip="The house\'s appliances and Phius devices. Edit the devices in Programs → Equipment Sets.">' + setOpts + '</select></td>';
}
// A Zone's ventilation comes from its Program or from its Spaces' detailed airflows; the tooltip says which.
function ventCell(d, p) {
  if (d.ventMissing) return '<span class="zp-amber" data-tip="The Program has no ventilation rates yet.">?</span>';
  if (d.ventDetailed) return '<span data-tip="Detailed airflows from Zones → Spaces: supply ' + fmt(d.ventDetailed.sup) + ', extract ' + fmt(d.ventDetailed.eta) + ' m³/h. The larger is shown.">' + fmt(d.vent) + '</span>';
  return '<span data-tip="From ' + esc(p.name) + ', split by Space floor area.">' + fmt(d.vent) + '</span>';
}
function frozen(text, tipText) { return '<span class="zp-frozen" data-tip="' + esc(tipText) + '">' + text + '</span>'; }
function frozenRow(z) {
  var d = derived(z), g = seg(z.seg), hd = house(g);
  var setName = hd.set ? setById(hd.set).name : "Phius single-family default";
  return '<tr class="tier-1"><td class="col-actions"></td><td>' + esc(z.name) + '</td>' +
    '<td>' + locked("Residential (default)", g) + '</td>' +
    '<td>' + locked(svg("home", 12) + " " + esc(hd.name), g) + '</td>' +
    '<td class="num">' + locked("—", g, "is-num") + '</td>' +
    '<td class="num">' + locked("—", g, "is-num") + '</td>' +
    '<td>' + locked(esc(setName), g) + '</td>' +
    '<td class="num">' + fmt(z.area, 1) + '</td><td class="num">' + fmt(z.icfa, 1) + '</td>' +
    '<td class="num">' + fmt(d.people, 2) + '</td><td class="num">' + fmt(d.lighting) + '</td><td class="num">' + ventCell(d, effectiveProgram(z)) + '</td></tr>';
}
function singleChanges(g) {
  var zs = S.zones.filter(function (z) { return z.seg === g.id; }), out = [], assigned = zs.filter(function (z) { return z.program; });
  if (assigned.length) {
    var names = {}; assigned.forEach(function (z) { names[prog(z.program).name] = 1; });
    out.push("Program choices on " + assigned.length + " Zone" + (assigned.length > 1 ? "s" : "") + " (" + Object.keys(names).join(", ") + ") give way to the residential default.");
  }
  var dws = {}; zs.forEach(function (z) { if (z.dwelling) dws[z.dwelling] = 1; });
  var nDw = Object.keys(dws).length, loose = zs.filter(function (z) { return !z.dwelling; }).length;
  if (nDw > 1) out.push(nDw + " dwellings become one, " + g.name + ".");
  else if (loose && nDw) out.push(loose + " Zones that are not dwellings join " + dw(Object.keys(dws)[0]).name + ".");
  if (g.category !== "res") out.push(g.name + " becomes Residential.");
  if (g.defProgram) out.push("Its default Program, " + prog(g.defProgram).name + ", gives way to the residential default.");
  if (zs.some(function (z) { return z.set; }) && nDw > 1) out.push("Per-dwelling Equipment Sets give way to one Set for the dwelling.");
  return out;
}
// Single dwelling on one Building Segment: its Zones become one dwelling, named for the Segment.
function applySingle(g) {
  var zs = S.zones.filter(function (z) { return z.seg === g.id; }), beds = 0, any = false, dws = {};
  zs.forEach(function (z) { if (z.beds !== null) { beds += z.beds; any = true; } if (z.dwelling) dws[z.dwelling] = 1; });
  Object.keys(dws).forEach(function (k) { var d = dw(k); if (d.beds !== null && d.beds !== undefined) { beds += d.beds; any = true; } });
  var keep = Object.keys(dws).length === 1 && zonesOfDwelling(Object.keys(dws)[0]).every(function (z) { return z.seg === g.id; }) ? dw(Object.keys(dws)[0]) : null;
  var h = keep || { id: id("dw"), name: g.name, units: 1, set: null };
  if (!keep) S.dwellings.push(h);
  h.units = 1; h.beds = any ? beds : null; h.occ = null;
  zs.forEach(function (z) { z.dwelling = h.id; z.program = null; z.set = null; z.beds = null; z.occ = null; delete S.checked[z.id]; });
  S.dwellings = S.dwellings.filter(function (d) { return S.zones.some(function (z) { return z.dwelling === d.id; }); });
  g.category = "res"; g.defProgram = null; g.single = true; g.house = h.id; S.bubble = null;
  notify(g.name + " is a single dwelling: its Zones are one dwelling, " + h.name + ", with the residential default." + (any ? " Bedrooms moved to it: " + beds + "." : ""));
}
function confirmSingle(g, changes) {
  var dlg = document.createElement("dialog");
  dlg.className = "phc-dialog phc-confirm-dialog zp-confirm";
  dlg.innerHTML = '<button type="button" class="phc-dialog-close" aria-label="Close" data-dlg="cancel">' + svg("clear", 18) + '</button><h2>Make ' + esc(g.name) + ' a single dwelling?</h2>' +
    '<p>This replaces what you assigned per Zone:</p><ul>' + changes.map(function (c) { return '<li>' + esc(c) + '</li>'; }).join("") + '</ul>' +
    '<p class="zp-muted">Bedrooms entered per Zone are added up for the dwelling. Undo restores the rest.</p>' +
    '<div class="phc-dialog-actions"><button type="button" data-dlg="cancel">Cancel</button><button type="button" class="primary" data-dlg="ok">Make single dwelling</button></div>';
  document.body.appendChild(dlg);
  dlg.addEventListener("click", function (e) {
    var b = e.target.closest("[data-dlg]"); if (!b) return;
    if (b.getAttribute("data-dlg") === "ok") applySingle(g);
    dlg.close(); dlg.remove(); render();
  });
  dlg.addEventListener("cancel", function () { dlg.remove(); render(); });
  dlg.showModal();
}
function setpointsFor(g) {
  var zs = S.zones.filter(function (z) { return z.seg === g.id; }), heats = {}, cools = {};
  zs.forEach(function (z) { var p = effectiveProgram(z); heats[p.setpoint.heat] = 1; cools[p.setpoint.cool] = 1; });
  var hk = Object.keys(heats), ck = Object.keys(cools);
  var txt = hk.join("/") + " / " + ck.join("/") + " °C";
  if (hk.length > 1 || ck.length > 1) return '<span class="zp-amber">' + txt + '</span>' + flag("The Zones in this Building Segment use Programs with different setpoints. PHX takes one winter and one summer value per Segment.");
  return '<span data-tip="Written from the Zones\' Program setpoints at export (Q4a-04).">' + txt + '</span>';
}
function zoneRow(z) {
  var p = effectiveProgram(z), d = derived(z), f = zoneFindings(z), checked = !!S.checked[z.id];
  var progCell = '<select class="phc-enum-cell' + (z.program ? "" : " is-default") + '" data-act="zone-program" data-v="' + z.id + '" aria-label="Program for ' + esc(z.name) + '"' +
    (z.program ? "" : ' data-tip="Unassigned: uses its Building Segment\'s default Program."') + '>' + programOptions(z.program || segDefaultProgram(z)) + '</select>' + (f.length ? flag(f.join(" ")) : "");
  var dwl = z.dwelling ? dw(z.dwelling) : null;
  var dwCell = dwl ? '<button type="button" class="zp-dwelling" data-act="dwelling" data-v="' + z.id + '">' + svg("home", 12) + esc(dwl.name) + (dwl.units > 1 ? " ×" + dwl.units : "") + '</button>'
    : '<button type="button" class="zp-dwelling is-none" data-act="dwelling" data-v="' + z.id + '">None</button>';
  var occTip = z.dwelling ? "Empty: the dwelling uses the Phius rule, bedrooms + 1 per unit." : "Only dwellings carry occupants.";
  var shared = dwl && zonesOfDwelling(dwl.id).length > 1;
  var setVal = z.set || (z.dwelling ? (dwl.set || null) : null);
  var setDefault = !setVal && p.source === "default" && z.dwelling;
  var setCell;
  if (seg(z.seg).category === "nonres") setCell = '<span class="zp-muted" data-tip="Non-residential Building Segment: PHX reads the Program\'s equipment watts and drops Equipment Set devices.">—</span>';
  else if (!z.dwelling) setCell = '<span class="zp-muted" data-tip="Equipment Sets apply per dwelling in a residential Building Segment. Common-area devices: assign a Set here once Zones without dwellings can carry one (open question).">—</span>';
  else {
    var opts = '<option value="">' + (setDefault ? "Phius single-family default" : "None") + '</option>' + S.sets.map(function (x) { return '<option value="' + x.id + '"' + (setVal === x.id ? " selected" : "") + '>' + esc(x.name) + '</option>'; }).join("");
    setCell = '<select class="phc-enum-cell' + (setVal ? "" : " is-default") + '" data-act="zone-set" data-v="' + z.id + '" aria-label="Equipment Set for ' + esc(z.name) + '"' +
      (shared ? ' data-tip="Shared by the dwelling ' + esc(dwl.name) + ': one Set per dwelling, not per Zone."' : (setDefault ? ' data-tip="The residential default brings the Phius single-family device set."' : "")) + '>' + opts + '</select>';
  }
  return '<tr class="tier-1' + (checked ? " is-checked" : "") + '"' + (checked ? ' aria-selected="true"' : "") + '><td class="col-actions"><input class="row-check" type="checkbox" data-act="check" data-v="' + z.id + '"' + (checked ? " checked" : "") + ' aria-label="Check ' + esc(z.name) + '"></td>' +
    '<td>' + esc(z.name) + '</td><td class="phc-editable-cell"><div class="zp-cellflex">' + progCell + '</div></td><td>' + dwCell + '</td>' +
    '<td class="num phc-editable-cell">' + (dwl && dwl.beds !== null && dwl.beds !== undefined ? frozen("in " + esc(dwl.name), "Entered once for the whole dwelling. Open " + dwl.name + " to change it.") : z.dwelling ? '<input class="phc-cell-input" data-act="beds" data-v="' + z.id + '" value="' + (z.beds === null ? "" : z.beds) + '" placeholder="0" aria-label="Bedrooms in ' + esc(z.name) + '">' : '<span class="zp-muted">—</span>') + '</td>' +
    '<td class="num phc-editable-cell"' + (z.dwelling ? ' data-tip="' + occTip + '"' : "") + '>' + (dwl && dwl.occ !== null && dwl.occ !== undefined ? frozen("in " + esc(dwl.name), "Entered once for the whole dwelling.") : z.dwelling ? '<input class="phc-cell-input" data-act="occ" data-v="' + z.id + '" value="' + (z.occ === null ? "" : z.occ) + '" placeholder="—" aria-label="Occupants in ' + esc(z.name) + '">' : '<span class="zp-muted">—</span>') + '</td>' +
    '<td class="phc-editable-cell">' + setCell + '</td>' +
    '<td class="num">' + fmt(z.area, 1) + '</td><td class="num">' + fmt(z.icfa, 1) + '</td>' +
    '<td class="num">' + (d.people === null ? '<span class="zp-amber" data-tip="The residential default derives people from the dwelling. Make this Zone part of a dwelling.">?</span>' : fmt(d.people, 2)) + '</td>' +
    '<td class="num">' + fmt(d.lighting) + '</td>' +
    '<td class="num">' + ventCell(d, p) + '</td></tr>';
}
function selectionBar(n) {
  var ids = Object.keys(S.checked), zs = S.zones.filter(function (z) { return S.checked[z.id]; });
  var progs = {}; zs.forEach(function (z) { progs[z.program || "pgm_default"] = 1; });
  var pk = Object.keys(progs);
  var dws = {}; zs.forEach(function (z) { dws[z.dwelling || "none"] = 1; });
  var dwOpts = '<option value="" selected disabled>' + (Object.keys(dws).length > 1 ? "Mixed" : (zs[0].dwelling ? dw(zs[0].dwelling).name : "Not a dwelling")) + '</option>' +
    '<option value="shared">One shared dwelling</option><option value="each">One dwelling each</option><option value="none">Not a dwelling</option>' +
    (S.dwellings.length ? '<optgroup label="Add to">' + S.dwellings.map(function (d) { return '<option value="to:' + d.id + '">' + esc(d.name) + '</option>'; }).join("") + '</optgroup>' : "");
  var segs = {}; zs.forEach(function (z) { segs[z.seg || "none"] = 1; });
  var segOpts = '<option value="" selected disabled>' + (Object.keys(segs).length > 1 ? "Mixed" : (zs[0].seg ? seg(zs[0].seg).name : "No Building Segment")) + '</option>' +
    S.segments.map(function (g) { return '<option value="' + g.id + '">' + esc(g.name) + '</option>'; }).join("") + '<option value="new">New Building Segment</option><option value="none">No Building Segment</option>';
  var setOpts = '<option value="" selected disabled>Choose…</option><option value="none">None</option>' + S.sets.map(function (x) { return '<option value="' + x.id + '">' + esc(x.name) + '</option>'; }).join("");
  return '<div class="phc-selection-bar" role="region" aria-label="Checked Zones" style="position:fixed; bottom:44px"><span class="phc-selection-bar-count">' + n + ' Zone' + (n > 1 ? "s" : "") + ' selected</span><div class="phc-selection-bar-controls">' +
    '<label class="phc-selection-field"><span>Building Segment</span><select data-act="bulk-seg" aria-label="Building Segment for checked Zones">' + segOpts + '</select></label>' +
    '<label class="phc-selection-field"><span>Program</span><select data-act="bulk-program" aria-label="Program for checked Zones">' + programOptions(pk.length === 1 ? pk[0] : null, false, pk.length > 1) + '</select></label>' +
    '<label class="phc-selection-field"><span>Dwelling</span><select data-act="bulk-dwelling" aria-label="Dwelling for checked Zones">' + dwOpts + '</select></label>' +
    '<label class="phc-selection-field"><span>Equipment Set</span><select data-act="bulk-set" aria-label="Equipment Set for checked Zones">' + setOpts + '</select></label></div>' +
    iconBtn("clear", "Clear selection", "clear-checked", ' style="width:28px;height:28px"') + '</div>';
}

// ---------------------------------------------------------------- Programs tab
function renderPrograms() {
  var h = '<section class="window-workspace"><div class="phc-heading phc-context-heading"><h1>Programs</h1><div class="phc-heading-actions"></div></div>';
  h += '<nav class="phc-subtabs" role="tablist" aria-label="Programs sections">' + [["programs", "Programs"], ["schedules", "Schedules"], ["sets", "Equipment Sets"]].map(function (t) {
    return '<button type="button" role="tab" data-act="ptab" data-v="' + t[0] + '" aria-selected="' + (S.ptab === t[0]) + '" aria-pressed="' + (S.ptab === t[0]) + '">' + t[1] + '</button>'; }).join("") + '</nav>';
  if (S.ptab === "programs") h += programsSurface();
  else if (S.ptab === "schedules") h += schedulesSurface();
  else h += setsSurface();
  return h + '</section>';
}
function usedBy(pid) { return S.zones.filter(function (z) { return (z.program || "pgm_default") === pid; }).length; }
function programsSurface() {
  var h = '<div class="pgm-layout"><div class="pgm-main">' + programEditor(prog(S.selProgram)) + '</div>' + librarySidebar() + '</div>';
  return h;
}
function programEditor(p) {
  var src = p.source === "default" ? '<span class="pgm-badge">' + svg("home", 11) + 'Unassigned Zones use this</span>' : (SOURCES[p.source] ? '<span class="pgm-badge is-lib">From ' + SOURCES[p.source] + '</span>' : "");
  var h = '<div class="pgm-head"><div><h2>' + esc(p.name) + src + '</h2><div class="pgm-metrics">' +
    metric("Used by", usedBy(p.id) + " Zones") +
    (p.people.rule ? metric("People", "Phius rule") : metric("People [ppl/m²]", fmt(p.people.ppa, 3))) +
    (p.lighting.rule ? metric("Lighting", "Phius rule") : metric("Lighting [W/m²]", fmt(p.lighting.wpa, 2))) +
    metric("Equipment [W/m²]", fmt(p.equip.wpa, 2)) + '</div></div><div class="pgm-tools">' +
    iconBtn("pencil", "Rename " + p.name, "noop") + iconBtn("duplicate", "Duplicate " + p.name, "dup-program") + iconBtn("more", "More Program actions", "noop") + '</div></div>';
  var segInfo = S.segments[0], air = segInfo.air && segInfo.air.value !== null ? segInfo.air : null;
  var base = p.base ? '<div class="pgm-src">From the paired ' + esc(p.base) + ' base program (Q4a-25).</div>' : "";
  function sched1(sid) { var sc = schedById(sid); return sc ? sc.name : "no schedule"; }
  function miss(v) { return v === null || v === undefined; }
  h += '<div class="pgm-loads">';
  h += card(p, "people", "users", "Occupancy", "",
    p.people.rule ? "Phius rule · " + sched1(p.people.sched) : (miss(p.people.ppa) ? "?" : fmt(p.people.ppa, 3) + " ppl/m²") + " · " + sched1(p.people.sched),
    p.people.rule ? rule("Phius residential rule", "Average occupants come from each dwelling (bedrooms + 1 per unit, or the Zone's Occupants). Peak people = occupants ÷ the presence schedule's mean, shared across the dwelling's Zones by gross floor area.")
      : num(p, "people", "ppa", "People per area", "ppl/m²", 4),
    schedRow(p.people.sched, "Occupancy") + (p.people.act ? schedRow(p.people.act, "Activity") : "") + more("Radiant and latent fractions"));
  h += card(p, "lighting", "light", "Lighting", "",
    p.lighting.rule ? "Phius rule · " + sched1(p.lighting.sched) : (miss(p.lighting.wpa) ? "?" : fmt(p.lighting.wpa, 2) + " W/m²") + " · " + sched1(p.lighting.sched),
    p.lighting.rule ? rule("Phius RESNET interior lighting", "(0.2 + 0.8 × (4 − 3 × high-efficacy fraction) / 3.7) × (455 × units + 0.8 × iCFA ft²) × 0.8 kWh/a per dwelling (honeybee-ph phius_residential.lighting_interior), as a peak W/m² over the lighting schedule.") + num(p, "lighting", "hef", "High-efficacy fraction", "–", 2)
      : num(p, "lighting", "wpa", "Lighting power", "W/m²", 2),
    schedRow(p.lighting.sched, "Lighting") + more("Return air, radiant and visible fractions"));
  var v = p.vent, vMiss = miss(v.pp) || miss(v.pa) || miss(v.ach);
  var vParts = []; if (v.pp) vParts.push(fmt(v.pp, 1) + " m³/h·p"); if (v.pa) vParts.push(fmt(v.pa, 2) + " m³/h·m²"); if (v.pz) vParts.push(fmt(v.pz) + " m³/h"); if (v.ach) vParts.push(fmt(v.ach, 2) + " ACH");
  h += card(p, "vent", "wind", "Ventilation", '<span class="pgm-tag" data-tip="PHX sums the four terms, so the method is fixed to Sum (Q4a-15).">Sum of terms</span>',
    (vMiss ? "?" : (vParts.join(" + ") || "0")) + " · " + sched1(v.sched),
    num(p, "vent", "pp", "Per person", "m³/h·person", 1) + num(p, "vent", "pa", "Per floor area", "m³/h·m²", 2) + num(p, "vent", "pz", "Per Zone", "m³/h", 0) + num(p, "vent", "ach", "Air changes", "1/h", 2) + (v.fromBase ? base : ""),
    schedRow(v.sched, "Ventilation") + '<div class="pgm-more">Detailed Space airflows replace the flow, not the schedule.</div>');
  h += card(p, "equip", "plug", "Electric equipment", p.source === "default" ? '<span class="pgm-tag is-note">Devices come from the Equipment Set</span>' : "",
    (miss(p.equip.wpa) ? "?" : fmt(p.equip.wpa, 2) + " W/m²") + " · " + sched1(p.equip.sched),
    num(p, "equip", "wpa", "Equipment power", "W/m²", 2), schedRow(p.equip.sched, "Equipment") + more("Radiant, latent and lost fractions"));
  h += card(p, "setpoint", "thermo", "Setpoint", '<span class="pgm-tag is-note" data-tip="Export writes each Building Segment\'s set points from its Zones\' Programs (Q4a-04).">Sets the Segment</span>',
    fmt(p.setpoint.heat, 1) + " / " + fmt(p.setpoint.cool, 1) + " °C",
    num(p, "setpoint", "heat", "Heating", "°C", 1) + num(p, "setpoint", "cool", "Cooling", "°C", 1) + num(p, "setpoint", "dehum", "Dehumidify above", "% RH", 0) + (p.setpoint.fromBase ? base : ""),
    (p.setpoint.hs ? schedRow(p.setpoint.hs, "Heating") + schedRow(p.setpoint.cs, "Cooling") : '<div class="pgm-more">Constant set points. Choose schedules for setbacks.</div>'));
  h += card(p, "infil", "waves", "Infiltration", "",
    air ? "Replaced by the Segment's test result, " + air.kind + " " + fmt(air.value, 2) : fmt(p.infil.flow, 5) + " m³/s·m² at 4 Pa",
    num(p, "infil", "flow", "Flow per exterior area at 4 Pa", "m³/s·m²", 5) + (air ? '<div class="pgm-replaced">Replaced at export: Building Segment ' + esc(segInfo.name) + ' has a test result, ' + air.kind + " " + fmt(air.value, 2) + '.</div>' : "") + (p.infil.fromBase ? base : ""),
    schedRow(p.infil.sched, "Infiltration"));
  h += '<div class="pgm-group" data-tip="WUFI-Passive, METr and PHPP do not read these (F4a-11). They export for EnergyPlus.">EnergyPlus only</div>';
  h += card(p, "gas", "flame", "Gas equipment", "", fmt(p.gas.wpa, 2) + " W/m²", num(p, "gas", "wpa", "Gas power", "W/m²", 2), schedRow(p.gas.sched, "Gas"));
  h += card(p, "shw", "droplet", "Hot water", "",
    p.shw.rule ? "Building America rule · " + fmt(p.shw.temp, 1) + " °C" : (miss(p.shw.lph) ? "?" : fmt(p.shw.lph, 4) + " L/h·m²") + " · " + fmt(p.shw.temp, 1) + " °C",
    (p.shw.rule ? rule("Building America by bedrooms", "Daily gallons from the dwelling's bedrooms (Building America 2014, Table 11), as L/h per m² of floor.") : num(p, "shw", "lph", "Flow per area", "L/h·m²", 4)) + num(p, "shw", "temp", "Target temperature", "°C", 1) + (p.shw.fromBase ? base : ""),
    schedRow(p.shw.sched, "Hot water"));
  return h + '</div>';
}
function metric(l, v) { return '<div class="pgm-metric"><small>' + l + '</small><strong>' + v + '</strong></div>'; }
// A load card: one full-width accordion row. Closed, it shows its values and schedule in one line; open, the
// load's values on the left and its schedules on the right.
function card(p, key, icon, title, tag, summary, loads, scheds) {
  var open = !!S.openCards[key], missing = /\?/.test(summary);
  return '<section class="pgm-card' + (open ? " is-open" : "") + '"><button type="button" class="pgm-card-head" data-act="card-toggle" data-v="' + key + '" aria-expanded="' + open + '">' +
    '<span class="pgm-chev">' + svg("chev", 14) + '</span>' + svg(icon, 16) + '<strong>' + title + '</strong>' + tag +
    '<span class="pgm-sum">' + (missing ? flag("A value is missing") + " " : "") + esc(summary) + '</span></button>' +
    (open ? '<div class="pgm-card-body"><div class="pgm-col"><div class="pgm-col-head">Load</div><div class="pgm-rows">' + loads + '</div></div><div class="pgm-col"><div class="pgm-col-head">Schedules</div>' + scheds + '</div></div>' : "") + '</section>';
}
function rule(title, text) { return '<div class="pgm-rule">' + svg("sigma", 15) + '<div><b>' + title + '</b><br>' + text + '</div></div>'; }
function more(text) { return '<div class="pgm-more">More: ' + text + '</div>'; }
function num(p, load, key, label, unit, d) {
  var v = p[load][key], missing = v === null || v === undefined;
  return '<div class="pgm-row' + (missing ? " is-missing" : "") + '"><span>' + label + '<span class="unit">' + unit + '</span>' + (missing ? flag("Set " + label.toLowerCase() + ": not in the library data") : "") + '</span><div><input data-act="load-value" data-load="' + load + '" data-key="' + key + '" value="' + (missing ? "?" : fmt(v, d).replace(/,/g, "")) + '" aria-label="' + label + '"></div></div>';
}
function schedRow(sid, label) {
  var sc = schedById(sid);
  return '<div class="pgm-sched">' + svg("calendar", 14) + label + ' schedule <button type="button" data-act="open-schedule" data-v="' + (sc ? sc.id : "") + '">' + (sc ? esc(sc.name) : "Choose…") + ' ▾</button></div>';
}
// The right sidebar, as in the Assembly and Window Type Builders: its source select starts with this file's
// records, then each added library. Choosing a record in this file opens it in the editor.
function fileRow(label, idv, act, selected, note) {
  return '<div class="library-sidebar-row' + (selected ? " is-selected" : "") + '"><button type="button" class="library-sidebar-row-button" data-act="' + act + '" data-v="' + idv + '"' + (selected ? ' aria-pressed="true"' : "") + '><span class="library-sidebar-name">' + esc(label) + '</span>' + (note !== undefined && note !== "" ? '<span class="lib-meta" data-tip="Zones using it">' + note + '</span>' : "") + '</button></div>';
}
function caption(text, n) { return '<div class="lib-group-caption"><span>' + text + '</span><span>' + n + '</span></div>'; }
function sidebarFrame(title, selectHtml, body) {
  return '<aside class="library-sidebar-root pgm-library" aria-label="' + title + '"><div class="library-sidebar-heading"><button type="button" class="library-sidebar-toggle" aria-expanded="true">' + title + '</button>' + iconBtn("settings", "Library setup…", "noop") + '</div><div class="library-sidebar-content">' + selectHtml + body + '</div></aside>';
}
function simpleSidebar(title, fileLabel, newAct, newLabel, groupsHtml, count) {
  return sidebarFrame(title, '<select class="library-sidebar-source" aria-label="Source" data-tip="No added library holds these yet. Library Programs bring their Schedules with them."><option>' + fileLabel + '</option></select>',
    '<button type="button" class="lib-new" data-act="' + newAct + '">+ ' + newLabel + '</button><input type="search" placeholder="Search" aria-label="Search">' +
    '<small class="muted">' + count + ' in this file</small><div class="library-sidebar-list">' + groupsHtml + '</div>');
}
function librarySidebar() {
  var h = '<aside class="library-sidebar-root pgm-library" aria-label="Program Library"><div class="library-sidebar-heading"><button type="button" class="library-sidebar-toggle" aria-expanded="true">Program Library</button>' + iconBtn("settings", "Library setup…", "noop") + '</div><div class="library-sidebar-content">';
  h += '<select class="library-sidebar-source" data-act="lib-source" aria-label="Library source">' +
    '<option value="file"' + (S.lib === "file" ? " selected" : "") + '>Programs in this file</option>' +
    '<option value="mf"' + (S.lib === "mf" ? " selected" : "") + '>Phius Multifamily · phius-multifamily.json</option>' +
    '<option value="nr"' + (S.lib === "nr" ? " selected" : "") + '>Phius Non-Residential · phius-non-residential.json</option>' +
    '<option value="hbe"' + (S.lib === "hbe" ? " selected" : "") + '>honeybee-energy standards (not added)</option></select>';
  if (S.lib === "hbe") return h + '<div class="lib-unavailable"><b>Not added.</b> An optional library file from ph-composer-standards, generated from the DOE reference programs: office, school, hotel and retail programs by vintage. Add it in Library setup, like any other library file. <br><br><button type="button" data-act="noop">Library setup…</button></div></div></aside>';
  if (S.lib === "file") {
    var others = S.programs.filter(function (p) { return p.id !== "pgm_default"; });
    h += '<button type="button" class="lib-new" data-act="new-program">+ New Program</button><input type="search" placeholder="Search Programs" aria-label="Search Programs in this file">' +
      '<small class="muted">' + S.programs.length + ' in this file</small><div class="library-sidebar-list">' + caption("Default", 1) +
      fileRow("Residential (default)", "pgm_default", "sel-program", S.selProgram === "pgm_default", usedBy("pgm_default")) + caption("In this file", others.length) +
      (others.length ? others.map(function (p) { return fileRow(p.name, p.id, "sel-program", S.selProgram === p.id, usedBy(p.id)); }).join("") : '<div class="pgm-row-note" style="padding:6px 0">No other Programs yet. Choose + New Program, or a library above.</div>') + '</div>';
    return h + '</div></aside>';
  }
  h += '<input type="search" data-act="lib-search" value="' + esc(S.libQuery) + '" placeholder="Search Programs" aria-label="Search Program library">';
  var rows = PHIUS[S.lib].filter(function (r) { return r[0].toLowerCase().indexOf(S.libQuery.toLowerCase()) >= 0; });
  h += '<small class="muted">' + rows.length + ' shown · from ph-composer-standards, generated from honeybee-ph</small><div class="library-sidebar-list"><section class="library-sidebar-group">';
  rows.forEach(function (r) {
    var inFile = !!programByName(r[0]);
    var local = programByName(r[0]);
    h += '<div class="library-sidebar-row' + (local && S.selProgram === local.id ? " is-selected" : "") + '"><button type="button" class="library-sidebar-row-button"' + (local ? ' data-act="sel-program" data-v="' + local.id + '"' : "") + ' data-tip="' + esc(r[0] + ": " + fmt(r[1], 3) + " ppl/m², lighting " + fmt(r[6], 1) + " W/m², equipment " + fmt(r[8], 1) + " W/m², occupied " + r[2] + "–" + r[3] + " h, " + r[4] + " d/a. Ventilation, infiltration, hot water and set points come from its 2019 base program.") + '"><span class="library-sidebar-name">' + esc(r[0]) + '</span><span class="lib-meta">' + fmt(r[6], 1) + ' W/m²</span></button>' +
      (inFile ? '<span class="lib-meta" data-tip="In this file: choose the row to open the local copy">' + svg("check", 14) + '</span>' : iconBtn("add", "Add " + r[0] + " to this file", "lib-add", ' data-v="' + esc(r[0]) + '"')) + '</div>';
  });
  return h + '</section></div></div></aside>';
}

// ---------------------------------------------------------------- Schedules
function schedulesSurface() {
  var groups = {};
  S.schedules.forEach(function (x) { (groups[x.kind] = groups[x.kind] || []).push(x); });
  var g = Object.keys(groups).map(function (k) { return caption(k, groups[k].length) + groups[k].map(function (x) { return fileRow(x.name, x.id, "sel-schedule", S.selSchedule === x.id); }).join(""); }).join("");
  var h = '<div class="pgm-layout"><div class="pgm-main">' + scheduleEditor(schedById(S.selSchedule)) + '</div>' + simpleSidebar("Schedule Library", "Schedules in this file", "new-schedule", "New Schedule", g, S.schedules.length) + '</div>';
  return h;
}
var LOAD_LABEL = { people: "Occupancy", lighting: "Lighting", equip: "Electric equipment", gas: "Gas equipment", shw: "Hot water", infil: "Infiltration", vent: "Ventilation" };
function schedUsers(sid) {
  var out = [];
  S.programs.forEach(function (p) { ["people", "lighting", "equip", "gas", "shw", "infil", "vent"].forEach(function (l) { if (p[l].sched === sid || p[l].act === sid) out.push(p.name + " · " + LOAD_LABEL[l]); }); if (p.setpoint.hs === sid || p.setpoint.cs === sid) out.push(p.name + " · Setpoint"); });
  return out;
}
function hours(sc) {
  if (sc.hourly) return sc.hourly;
  if (sc.vent) { var out = []; sc.vent.periods.forEach(function (pd) { for (var i = 0; i < pd.hours && out.length < 24; i += 1) out.push(pd.frac); }); while (out.length < 24) out.push(0); return out; }
  var p = sc.ph, a = [];
  for (var hr = 0; hr < 24; hr += 1) { var on = p.end > p.start ? (hr >= p.start && hr < p.end) : (hr >= p.start || hr < p.end); a.push(on ? p.frac : p.base); }
  return a;
}
function strip(sc) {
  var a = hours(sc), max = sc.kind === "Fractional" ? 1 : Math.max.apply(null, a) * 1.1, w = 22, H = 70, s = '<svg width="' + (w * 24 + 30) + '" height="' + (H + 22) + '" role="img" aria-label="24-hour profile">';
  s += '<line x1="28" y1="' + H + '" x2="' + (28 + w * 24) + '" y2="' + H + '" stroke="#c9d3d7"/>';
  a.forEach(function (v, i) { var bh = max ? v / max * (H - 4) : 0; s += '<rect x="' + (29 + i * w) + '" y="' + (H - bh) + '" width="' + (w - 2) + '" height="' + bh + '" fill="#9cc3cc"><title>' + i + ':00 ' + v + '</title></rect>'; if (i % 3 === 0) s += '<text x="' + (29 + i * w) + '" y="' + (H + 14) + '" font-size="10" fill="#6b7b80">' + i + '</text>'; });
  s += '<text x="0" y="10" font-size="10" fill="#6b7b80">' + (sc.kind === "Fractional" ? "1.0" : fmt(max, 0)) + '</text><text x="0" y="' + H + '" font-size="10" fill="#6b7b80">0</text>';
  return s + '</svg>';
}
function scheduleEditor(sc) {
  var users = schedUsers(sc.id), a = hours(sc), mean = a.reduce(function (t, v) { return t + v; }, 0) / 24;
  var daysYear = sc.ph ? (sc.ph.daysYear || sc.ph.days * sc.ph.weeks) : sc.vent ? sc.vent.days * sc.vent.weeks : 365;
  var flh = sc.kind === "Fractional" || sc.kind === "Ventilation" ? (sc.ph || sc.vent ? a.reduce(function (t, v) { return t + v; }, 0) * daysYear : mean * 8760) : null;
  var h = '<div class="pgm-head"><div><h2>' + esc(sc.name) + (sc.source === "hbph" ? '<span class="pgm-badge is-lib">From honeybee-ph</span>' : "") + '</h2><div class="pgm-metrics">' +
    metric("Type", sc.kind) + (flh !== null ? metric("Full-load hours [h/a]", fmt(flh)) : metric("Mean value", fmt(mean, 1))) + metric("Used by", users.length + (users.length === 1 ? " load" : " loads")) + '</div></div><div class="pgm-tools">' +
    iconBtn("pencil", "Rename", "noop") + iconBtn("duplicate", "Duplicate", "noop") + iconBtn("more", "More Schedule actions", "noop") + '</div></div>';
  if (sc.vent) {
    var tot = sc.vent.periods.reduce(function (a2, pd) { return a2 + pd.hours; }, 0);
    h += '<div class="vent-form"><b>Period</b><b>Hours per day</b><b>Fraction of design flow</b>' + sc.vent.periods.map(function (pd, i) {
      return '<span>' + pd.name.charAt(0).toUpperCase() + pd.name.slice(1) + '</span><input data-act="vent-period" data-i="' + i + '" data-k="hours" value="' + pd.hours + '" aria-label="' + pd.name + ' hours"><input data-act="vent-period" data-i="' + i + '" data-k="frac" value="' + pd.frac + '" aria-label="' + pd.name + ' fraction">';
    }).join("") + '</div>';
    h += '<div class="vent-total' + (Math.abs(tot - 24) > 0.001 ? " zp-amber" : "") + '">' + (Math.abs(tot - 24) > 0.001 ? flag("The four periods must total 24 hours.") + " " : "") + 'Total ' + fmt(tot, 1) + ' of 24 h</div>';
    h += '<div class="sch-form" style="margin-top:10px">' + field("Days per week", "days", sc.vent.days, "", "vent") + field("Weeks per year", "weeks", sc.vent.weeks, "", "vent") + '</div>';
    h += '<div class="sch-caption">A ventilation schedule is four periods, as WUFI-Passive and METr read it: hours at high, standard, basic and minimum speed, each a fraction of the design flow (PHX requires these four names). Shown below in that order, not by time of day.</div>';
  } else if (sc.ph) {
    var p = sc.ph;
    h += '<div class="sch-form">' + field("Starts at", "start", p.start, "h") + field("Ends at", "end", p.end, "h") + field("Fraction while operating", "frac", p.frac, "") + field("Fraction otherwise", "base", p.base, "") +
      field("Days per week", "days", p.days, "") + field("Weeks per year", "weeks", p.weeks, "") + '</div>';
    h += '<div class="sch-caption">Weekday profile (weekends off when days per week is under 7). Written as a honeybee ruleset with real weekday rules; honeybee-ph operating periods wait for the F4a-13 fix.</div>';
  } else {
    h += '<div class="sch-caption" style="margin-top:14px">Hourly profile from honeybee-ph (values illustrative in this mockup). The PH form cannot describe it; the hourly editor will.</div>';
  }
  h += '<div class="sch-strip">' + strip(sc) + '</div>';
  if (sc.ph && sc.ph.days < 7) {
    h += '<div class="sch-caption">Week</div><div style="display:flex;gap:3px">' + ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map(function (d, i) { var on = i < sc.ph.days; return '<span style="padding:3px 8px;border-radius:4px;font-size:11px;background:' + (on ? "#9cc3cc" : "#eef1f3") + '">' + d + '</span>'; }).join("") + '</div>';
  }
  h += '<div class="sch-caption">Used by</div><div style="font-size:12px">' + (users.length ? users.map(esc).join("<br>") : '<span class="zp-muted">Nothing yet.</span>') + '</div>';
  h += '<div class="sch-advanced"><button type="button" disabled data-tip="Planned, deferred: an hourly day-profile, weekday-rule and date-range editor modelled on the OpenStudio Application\'s schedule editor (Q4a-07).">Hourly editor…</button>Day profiles, weekday rules and date ranges, for schedules the PH form cannot describe.</div>';
  return h;
}
function field(label, key, v, unit, block) { return '<label>' + label + (unit ? " [" + unit + "]" : "") + '<input data-act="sched-value" data-key="' + key + '"' + (block ? ' data-block="' + block + '"' : "") + ' value="' + v + '"></label>'; }

// ---------------------------------------------------------------- Equipment Sets
function setsSurface() {
  var x = setById(S.selSet);
  var h = '<div class="pgm-layout"><div class="pgm-main"><div class="pgm-head"><div><h2>' + esc(x.name) + '</h2><div class="pgm-sub">honeybee-ph devices, exported as Process loads with each device\'s watts worked out per dwelling at export. One Set serves a dwelling, not each of its Zones.</div></div><div class="pgm-tools">' +
    '<button type="button" class="primary" data-act="device-add" data-v="' + x.id + '">' + svg("add", 14) + ' Add device</button>' + iconBtn("duplicate", "Duplicate", "noop") + iconBtn("more", "More", "noop") + '</div></div>';
  h += '<div class="phc-table-mount" style="margin-top:12px; --row-actions-width:76px"><table class="phc-table zp-table reveals-row-actions zp-devices"><thead><tr><th class="col-actions"></th><th>Device</th><th class="num">Quantity</th><th>Energy demand</th><th>In conditioned space</th><th>Reference quantity</th></tr></thead><tbody>' +
    (x.devices.length ? x.devices.map(function (d, i) {
      var ty = devType(d.type);
      return '<tr data-act="device-edit" data-v="' + x.id + '" data-i="' + i + '"><td class="col-actions">' +
        '<button type="button" class="phc-icon-button row-icon" data-row-action="edit" data-act="device-edit" data-v="' + x.id + '" data-i="' + i + '" aria-label="Edit ' + esc(d.name) + '" data-tip="Edit ' + esc(d.name) + '">' + svg("pencil", 16) + '</button>' +
        '<button type="button" class="phc-icon-button row-icon row-delete" data-row-action="delete" data-act="device-delete" data-v="' + x.id + '" data-i="' + i + '" aria-label="Delete ' + esc(d.name) + '" data-tip="Delete ' + esc(d.name) + '">' + svg("del", 16) + '</button></td>' +
        '<td>' + esc(d.name) + (d.name !== ty.label ? ' <span class="zp-muted">· ' + esc(ty.label) + '</span>' : "") + '</td><td class="num">' + d.qty + '</td>' +
        '<td>' + (ty.rule ? '<span style="color:#0b5360">' + svg("sigma", 12) + ' ' + esc(ty.rule) + '</span>' : esc(deviceDemand(d))) + '</td>' +
        '<td>' + (d.inside ? "Yes" : "No") + '</td><td class="zp-muted">' + esc(REFQ[d.ref]) + '</td></tr>';
    }).join("") : '<tr><td></td><td colspan="5" class="zp-muted">No devices yet. Choose Add device.</td></tr>') + '</tbody></table></div></div>' +
    simpleSidebar("Equipment Set Library", "Equipment Sets in this file", "new-set", "New Equipment Set", caption("In this file", S.sets.length) + S.sets.map(function (y) { return fileRow(y.name, y.id, "sel-set", S.selSet === y.id); }).join(""), S.sets.length) + '</div>';
  return h;
}

