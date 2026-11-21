/* The Programs view of the Zones table (context/EXTENSIBILITY.md, "Zone views"; context/CONTRACTS.md,
   "Occupancy"): one row per Zone under its Building Segment's heading, with its Program, Dwelling, bedrooms, occupants,
   Equipment Set, floor area, iCFA and the peak people, lighting and ventilation the export will write. Every value
   comes from `ph_composer.programs.zones`, published as the `ph_composer.programs.occupancy` snapshot section; the
   panel formats it and sums nothing. A value Ruby cannot work out is an amber "?" naming why; a Zone's findings
   are its row's flag. The heading rows show each Segment's sums, and a single dwelling's heading is the house row,
   whose bedrooms, occupants and Equipment Set are the only inputs for its Zones.

   Cells and the Dwelling bubble: features/programs/zones_cells.js. Checks and the selection bar:
   features/programs/zones_selection.js. Library Programs: features/programs/library_programs.js. */
PhComposerUI.define("features/programs/zones_view", ["panel", "workspace", "units", "unit_preferences", "fields",
  "table_views", "features/programs/occupancy", "features/programs/zones_cells",
  "features/programs/zones_selection", "features/programs/library_programs"],
function (panel, ui, units, preferences, fields, tableViews, occupancy, ZoneCells, ZoneSelection, LibraryPrograms) {
  "use strict";
  var ID = "ph_composer.programs.zones";
  var SECTION = "ph_composer.programs.occupancy";
  var AREA = fields.AREA_M2, AIRFLOW = fields.AIRFLOW_M3H;
  var POWER = { quantity: "power", unit: "w" };
  // Each column header's tooltip names the basis its values are worked out on (Q4a-17).
  var HELP = {
    bedrooms: "Per Zone in a Dwelling, totalled for the Dwelling. A Dwelling that holds its own count shows it " +
      "on each of its Zones.",
    occupants: "Average occupants. Left empty, the Dwelling uses the Phius rule: bedrooms + 1 per dwelling unit.",
    floor_area_m2: "Gross Zone floor area: the basis per-area loads multiply.",
    icfa_m2: "Weighted Space floor area (iCFA): the basis of the Phius residential rules.",
    people: "Peak people. The residential default shares its Dwelling's occupants over the presence schedule's " +
      "mean by gross floor area; any other Program multiplies its people per area by gross floor area.",
    lighting_w: "Peak interior lighting, W. The residential default works out the Phius interior lighting from its " +
      "Dwelling's iCFA and units, shared by iCFA; any other Program multiplies its W per area by gross floor area.",
    ventilation_m3h: "From the Program (per person, per gross floor area, per Zone and air changes) for a Zone " +
      "By Program, or from its Spaces' detailed airflows, the larger of supply and extract. The Program's " +
      "schedule applies either way."
  };

  function occurrence(path) { return JSON.stringify(path || []); }

  /* What every part of the view reads from the last snapshot. */
  function Data() { this.value = { zones: [], building_segments: [], dwellings: [], choices: {} }; this.byKey = {}; }
  Data.prototype.read = function () { return this.value; };
  Data.prototype.consume = function (state) {
    var self = this;
    this.value = Object.assign({ dwellings: [] }, occupancy.read(state));
    this.byPath = Object.create(null);
    this.value.zones.forEach(function (zone) { self.byPath[occurrence(zone.reference.zone_path)] = zone; });
  };
  Data.prototype.zone = function (path) { return this.byPath && this.byPath[occurrence(path)] || null; };
  Data.prototype.segment = function (id) {
    return this.value.building_segments.filter(function (row) { return row.id === id; })[0] || null;
  };
  Data.prototype.dwelling = function (id) {
    if (!id) return null;
    return this.value.dwellings.filter(function (row) { return row.id === id; })[0] || null;
  };
  /* The Dwellings a Zone of `segmentId` may join, by name: those in its Segment, those in none, and its own. */
  Data.prototype.segmentDwellings = function (segmentId, own) {
    return this.value.dwellings.filter(function (row) {
      if (row.single_dwelling || !row.id) return false;
      return row.id === own || !row.building_segment_ids.length || row.building_segment_ids.indexOf(segmentId) >= 0;
    });
  };
  Data.prototype.zoneNames = function (ids) {
    var names = this.value.zones.filter(function (zone) { return ids.indexOf(zone.zone_id) >= 0; })
      .map(function (zone) { return zone.name; });
    return names.sort(function (a, b) { return String(a).localeCompare(String(b)); });
  };
  Data.prototype.row = function (key) { return this.rows && this.rows[key] || null; };

  function create(host) {
    var data = new Data(), changed = function () { panel.repaint(); };
    var library = new LibraryPrograms(host.session, host.send, changed);
    var cells = new ZoneCells(host, data, library);
    return { host: host, data: data, library: library, cells: cells, selection: new ZoneSelection(cells, data) };
  }

  function consume(vs, state) {
    vs.data.consume(state);
    vs.cells.consume(state);
    vs.library.consume(state);
  }

  function zoneRecord(vs, record) {
    return Object.assign(record, { programs: vs.data.zone(record.zone.reference.zone_path) });
  }

  function profile() { return preferences.current(); }

  function formatted(value, field, digits) {
    if (value === null || value === undefined) return "";
    var settings = units.profile(field, profile());
    return units.format(value, field, settings, { showUnit: false, precision: digits });
  }

  /* Lighting shows in W in either system, as the export writes it. */
  function watts(value) {
    if (value === null || value === undefined) return "";
    var settings = units.profile(POWER, profile());
    return units.format(value, POWER, { system: "SI", numberFormat: settings.numberFormat }, { showUnit: false });
  }

  function people(value) {
    if (value === null || value === undefined) return "";
    return units.format(value, fields.FRACTION, units.profile(fields.FRACTION, profile()),
      { showUnit: false, precision: 2 });
  }

  function columns(vs, settings) {
    return [["program", "Program"], ["dwelling", "Dwelling"], ["bedrooms", "Bedrooms"], ["occupants", "Occupants"],
      ["equipment_set", "Equipment Set"], ["floor_area_m2", units.header("Floor area", AREA, settings)],
      ["icfa_m2", units.header("iCFA", AREA, settings)], ["people", "People"], ["lighting_w", "Lighting (W)"],
      ["ventilation_m3h", units.header("Ventilation", AIRFLOW, settings)]];
  }

  function value(vs, row, field) {
    var zone = row.record.programs;
    if (!zone) return "";
    if (field === "floor_area_m2" || field === "icfa_m2") return formatted(zone[field], AREA, 1);
    if (field === "people") return people(zone.people);
    if (field === "lighting_w") return watts(zone.lighting_w);
    if (field === "ventilation_m3h") return formatted(zone.ventilation_m3h, AIRFLOW);
    return "";
  }

  /* A Zone's numbers carry their source in a tooltip: Ventilation says whether it is the Program's or the
     Spaces' detailed airflows. */
  function decorate(vs, td, row, field) {
    var zone = row.record.programs;
    if (!zone || field !== "ventilation_m3h") return;
    ui.tooltip(td, zone.ventilation_m3h === null ? "" : zone.ventilation_source === "detailed" ? "Detailed " +
      "airflows from Zones / Spaces: the larger of its Spaces' supply and extract." : "From " + zone.program_name +
      ": its rates per person, per floor area, per Zone and its air changes.");
  }

  function marker(vs, row) {
    var zone = row.record.programs, findings = zone && zone.findings || [];
    if (!findings.length) return null;
    return { text: "", icon: "alert", tooltip: findings.map(function (finding) { return finding.message; })
      .join(" ") };
  }

  /* A Segment's heading: its sums, from Ruby. Under Single dwelling its counts and Set are inputs (segmentCell). */
  function segmentSums(vs, group) {
    var segment = group.segment && vs.data.segment(group.segment.id);
    if (!segment || !segment.sums) return {};
    var sums = segment.sums, shown = {};
    if (!segment.single_dwelling) {
      shown.bedrooms = sums.bedrooms === null ? "" : String(sums.bedrooms);
      shown.occupants = sums.occupants === null ? "" : people(sums.occupants);
    }
    shown.floor_area_m2 = formatted(sums.floor_area_m2, AREA, 1);
    shown.icfa_m2 = formatted(sums.icfa_m2, AREA, 1);
    shown.people = people(sums.people);
    shown.lighting_w = watts(sums.lighting_w);
    shown.ventilation_m3h = formatted(sums.ventilation_m3h, AIRFLOW);
    return shown;
  }

  /* The house row's inputs, and an amber "?" on a load some Zone lacks. */
  function segmentCell(vs, td, group, field) {
    if (vs.cells.houseCell(td, group, field)) return true;
    var segment = group.segment && vs.data.segment(group.segment.id);
    if (!segment || !segment.sums || (segment.sums.incomplete || []).indexOf(field) < 0) return false;
    var known = field === "people" ? people(segment.sums[field]) : field === "lighting_w" ?
      watts(segment.sums[field]) : formatted(segment.sums[field], AIRFLOW);
    return ZoneCells.missing(td, "A Zone in " + segment.name + " has no value" + (known ? "; the others sum to " +
      known : "") + ". Its row names why.", segment.name);
  }

  /* The Dwellings that hold Zones, a single dwelling's house among them (the read lists it with a null id). */
  function count(vs) {
    var total = vs.data.read().dwellings.filter(function (row) { return row.zone_ids.length; }).length;
    return total + (total === 1 ? " dwelling" : " dwellings");
  }

  function prepare(vs, rows) {
    var keyed = Object.create(null);
    rows.forEach(function (row) { keyed[row.key] = row; });
    vs.data.rows = keyed;
    vs.selection.prepare(rows);
    // The library loads leave after this paint, so a host that answers at once never repaints inside it.
    if (vs.host.activeView() === ID && !vs.library.started() && window.setTimeout) {
      window.setTimeout(function () { if (!vs.host.disposed) vs.library.start(); }, 0);
    }
  }

  var VIEW = {
    id: ID, label: "Programs", order: 30, sections: [SECTION], zoneFields: [],
    placeholder: "Zone, Program or Dwelling",
    widths: { program: 188, dwelling: 120, bedrooms: 84, occupants: 92, equipment_set: 168, floor_area_m2: 104,
      icfa_m2: 88, people: 72, lighting_w: 96, ventilation_m3h: 128 },
    sorted: ["floor_area_m2", "icfa_m2", "people", "lighting_w", "ventilation_m3h"],
    sortValue: function (vs, record, field) {
      var zone = record.programs;
      return zone && VIEW.sorted.indexOf(field) >= 0 ? zone[field] : undefined;
    },
    create: create, consume: consume, zoneRecord: zoneRecord, columns: columns, value: value, decorate: decorate,
    zoneMarker: marker, segmentSums: segmentSums, segmentCell: segmentCell, count: count,
    headerHelp: function (vs, field) { return HELP[field] || null; },
    search: function (vs, record) {
      var zone = record.programs;
      return zone ? [zone.program_name, zone.dwelling_name].filter(Boolean).join(" ") : "";
    },
    attach: function (vs, place) { vs.cells.attach(place); },
    prepare: prepare,
    cell: function (vs, td, row, field) { return vs.cells.render(td, row, field); },
    painted: function (vs) { vs.cells.painted(vs.data.rows || {}); },
    check: function (vs, context) { return vs.selection.check(context); },
    selectionBar: function (vs, overview) { return vs.selection.bar(overview); },
    checkedZones: function (vs) { return vs.selection.checkedZones(); },
    checkZones: function (vs, keys) { vs.selection.pending = keys; },
    leave: function (vs) { vs.selection.hide(); vs.cells.closeDwelling(); occupancy.closeLock(); },
    escape: function (vs) {
      if (vs.cells.bubble) { vs.cells.closeDwelling(); return true; }
      if (occupancy.closeLock()) return true;
      if (!vs.selection.clear()) return false;
      panel.repaint();
      return true;
    },
    dispose: function (vs) {
      vs.cells.dispose(); vs.selection.dispose(); vs.library.dispose(); occupancy.closeLock();
    }
  };
  tableViews.register("ph_composer.zones", VIEW);
  return VIEW;
});
