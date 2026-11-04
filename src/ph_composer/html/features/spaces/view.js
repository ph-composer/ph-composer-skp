/* The Spaces view of the Zones table (context/EXTENSIBILITY.md, "Zone views"): beneath each Zone its Spaces,
 * each Space's Volumes and each Volume's Floor Segments, with their areas, heights, volumes and airflows, and
 * the Zone's sums on its row. A Space outside every Zone is listed under one "No Zone" row after the Zones.
 * Every figure comes from the `spaces` snapshot section; the panel sums and computes nothing.
 *
 * Airflows follow the any-set rule: a set rate reads as typed, an unset rate on a user-specified Space reads
 * as a muted 0, and a Space with all three unset reads "Zone" (it inherits the Zone's ventilation load).
 * A Zone holding any inheriting Space shows a muted dash for its airflow sums and evaluates no imbalance.
 * Names, numbers, heights, factors and airflows edit in place (cells.js).
 */
PhComposerUI.define("features/spaces/view", ["panel", "workspace", "snapshot", "units", "unit_preferences", "fields",
  "table_views", "features/spaces/cells", "features/spaces/actions", "features/spaces/selection",
  "features/spaces/mark_paint", "features/spaces/create_review", "sections/colour_by", "request"],
function (panel, ui, snapshot, units, preferences, fields, tableViews, SpaceCells, SpaceActions, SpaceSelection,
          MarkPaint, CreateReview, colourBy, requests) {
  "use strict";
  var SECTION = "ph_composer.spaces.spaces";
  var AIRFLOWS = [["v_sup_m3h", "Supply"], ["v_eta_m3h", "Extract"], ["v_tran_m3h", "Transfer"]];
  var AIRFLOW_FIELDS = { v_sup_m3h: true, v_eta_m3h: true, v_tran_m3h: true };
  // Each column, the quantity it shows, and the metric or value a row reads it from.
  var QUANTITY = { floor_area_m2: fields.AREA_M2, weighted_area_m2: fields.AREA_M2, net_volume_m3: fields.VOLUME_M3,
    height_m: fields.LENGTH_M, v_sup_m3h: fields.AIRFLOW_M3H, v_eta_m3h: fields.AIRFLOW_M3H,
    v_tran_m3h: fields.AIRFLOW_M3H };
  var SORTED = ["number", "floor_area_m2", "weighting_factor", "weighted_area_m2", "height_m", "net_volume_m3",
    "v_sup_m3h", "v_eta_m3h", "v_tran_m3h", "net_area_factor"];
  var NO_ZONE = JSON.stringify(["NoZone"]);
  // The modes each column offers from its header (context/EXTENSIBILITY.md, "Colour-by modes").
  var COLOUR_BY = { name: { mode: "ph_composer.spaces.by_space" },
    weighting_factor: { mode: "ph_composer.spaces.by_weighting_factor" },
    height_m: { mode: "ph_composer.spaces.by_height" },
    v_sup_m3h: { group: "ventilation" }, v_eta_m3h: { group: "ventilation" }, v_tran_m3h: { group: "ventilation" } };
  var READOUT_LABELS = { "ph_composer.spaces.labels": "Space labels",
    "ph_composer.spaces.selection_totals": "Selection totals" };
  var LABEL_LINES = [["weighted_area", "Weighted area (iCFA)"], ["net_volume", "Net volume"],
    ["airflows", "Supply and extract"]];

  function create(host) {
    var cells = new SpaceCells(host);
    var vs = { host: host, spaces: [], byZone: Object.create(null), sums: Object.create(null), outside: [],
      cells: cells, actions: new SpaceActions(host), selection: new SpaceSelection(cells), paint: new MarkPaint(host) };
    vs.labelOptions = requests.channel(host.session, host.send, "spaces-label-options", "view.invoke");
    // Create Space's review waits for a held edit, the Zones screen's or this view's, and is shown over this
    // view.
    vs.review = new CreateReview(host, function () { return host.draftReason() || draftReason(vs); }, {
      shown: function (state) {
        return (!state.ui || state.ui.activeTab === "overview") && host.activeView() === VIEW.id;
      },
      show: function () { panel.showTab("overview"); host.show(VIEW.id); }
    });
    return vs;
  }

  function occurrence(path) {
    return JSON.stringify(path || []);
  }

  /* The Spaces under each Zone occurrence and each Zone's sums, by the path that names the occurrence. */
  function consume(vs, state) {
    var value = snapshot.value(state, SECTION) || { spaces: [], zones: [] };
    vs.spaces = value.spaces || [];
    vs.byZone = Object.create(null);
    vs.outside = [];
    vs.spaces.forEach(function (space) {
      if (!space.zone) { vs.outside.push(space); return; }
      var key = occurrence(space.zone.zone_path);
      (vs.byZone[key] = vs.byZone[key] || []).push(space);
    });
    vs.sums = Object.create(null);
    (value.zones || []).forEach(function (zone) { vs.sums[occurrence(zone.zone_path)] = zone; });
    vs.actions.consume(state, value.zones || []);
    vs.paint.consume(state);
    vs.review.consume(state);
    // Mark floor runs only while this view is shown on the Zones tab: a start that lands after a switch away
    // is stopped.
    if (state.ui && state.ui.activeTab !== "overview" || vs.host.activeView() !== VIEW.id) vs.paint.stop();
  }

  function zoneRecord(vs, record) {
    var key = occurrence(record.zone.reference.zone_path);
    return Object.assign(record, { spaces: vs.byZone[key] || [], sums: vs.sums[key] || null });
  }

  /* One group row after the Zones for the Spaces no Zone holds, while there are any. */
  function extraRows(vs) {
    if (!vs.outside.length) return [];
    return [{ key: NO_ZONE, parent: null, tier: "No Zone", depth: 0,
      record: { id: NO_ZONE, name: "Outside every Zone", zone: null, spaces: vs.outside, sums: null } }];
  }

  /* A Zone's (or the group's) rows: each Space, then its Volumes, then each Volume's Floor Segments. The
     Space Floor has no row. */
  function children(vs, row) {
    var rows = [];
    row.record.spaces.forEach(function (space) {
      var spaceKey = JSON.stringify(["Space", space.reference.entity_path]);
      rows.push({ key: spaceKey, parent: row.key, tier: "Space", depth: 1,
        record: { id: space.id, name: space.values.name, space: space } });
      (space.volumes || []).forEach(function (volume) {
        var volumeKey = JSON.stringify(["Volume", volume.reference.entity_path]);
        rows.push({ key: volumeKey, parent: spaceKey, tier: "Volume", depth: 2,
          record: { id: volume.id, name: volume.values.display_name, volume: volume, space: space } });
        (volume.floor_segments || []).forEach(function (segment) {
          rows.push({ key: JSON.stringify(["Segment", segment.reference.entity_path]), parent: volumeKey,
            tier: "Segment", depth: 3,
            record: { id: segment.id, name: segment.values.display_name, segment: segment, space: space } });
        });
      });
    });
    return rows;
  }

  function leadingColumns() {
    return [["number", "No."]];
  }

  function columns(vs, profile) {
    function header(label, field) { return units.header(label, field, units.profile(field, preferences.current())); }
    return [["floor_area_m2", header("Floor area", fields.AREA_M2)], ["weighting_factor", "Weighting factor"],
      ["weighted_area_m2", header("Weighted area", fields.AREA_M2)], ["height_m", header("Height", fields.LENGTH_M)],
      ["net_volume_m3", header("Net volume", fields.VOLUME_M3)]].concat(AIRFLOWS.map(function (airflow) {
      return [airflow[0], header(airflow[1], fields.AIRFLOW_M3H)];
    }), [["net_area_factor", "Net area factor"]]);
  }

  /* What a row shows in one column, as `{ value, quantity }` for a quantity, `{ text }` for a word, or null
     for a blank; `muted` marks a value the row does not set itself, `tooltip` says why. */
  function cellOf(row, field) {
    var record = row.record;
    if (record.segment) return segmentCell(record.segment, field);
    if (record.volume) return volumeCell(record.volume, field);
    if (record.space) return spaceCell(record.space, field);
    return zoneCell(record, field);
  }

  function metric(source, field) {
    return field === "floor_area_m2" || field === "weighted_area_m2" || field === "net_volume_m3" ?
      { value: source.metrics[field] } : null;
  }

  function segmentCell(segment, field) {
    if (field === "weighting_factor" || field === "net_area_factor") {
      return { value: segment.values[field], quantity: fields.FRACTION, precision: 2 };
    }
    return field === "net_volume_m3" ? null : metric(segment, field);
  }

  function volumeCell(volume, field) {
    if (field === "height_m") return { value: volume.values.avg_ceiling_height_m };
    return metric(volume, field);
  }

  function spaceCell(space, field) {
    if (field === "number") return { text: space.values.number };
    if (field === "height_m") {
      return { value: space.metrics.average_height_m, muted: true,
        tooltip: "The floor-area-weighted average of this Space's Volume heights. Edit a Volume's height." };
    }
    if (AIRFLOW_FIELDS[field]) {
      if (space.airflow_mode === "inheriting") {
        return { text: "Zone", muted: true,
          tooltip: "No airflow is set, so this Space uses its Zone's ventilation load." };
      }
      var set = Object.prototype.hasOwnProperty.call(space.values, field);
      return { value: space.airflows[field], muted: !set,
        tooltip: set ? "" : "Not set. Another airflow on this Space is, so this one counts as 0." };
    }
    return metric(space, field);
  }

  /* A Zone row carries its Spaces' sums from the snapshot; the group row of Spaces outside every Zone none. */
  function zoneCell(record, field) {
    var sums = record.sums;
    if (!sums) return null;
    if (AIRFLOW_FIELDS[field]) {
      if (sums.inheriting_count) {
        var noun = sums.inheriting_count === 1 ? " Space in this Zone inherits" : " Spaces in this Zone inherit";
        return { text: "—", muted: true,
          tooltip: sums.inheriting_count + noun + " its airflow, so the sums are not shown." };
      }
      return { value: sums.airflows[field] };
    }
    return field === "floor_area_m2" || field === "weighted_area_m2" || field === "net_volume_m3" ?
      { value: sums[field] } : null;
  }

  function format(cell, field) {
    if (!cell) return "";
    if (cell.text !== undefined) return cell.text || "";
    var quantity = cell.quantity || QUANTITY[field];
    return units.format(cell.value, quantity, units.profile(quantity, preferences.current()),
      { showUnit: false, precision: cell.precision });
  }

  function value(vs, row, field) {
    return format(cellOf(row, field), field);
  }

  /* A muted value says why in its tooltip; every other cell's tooltip is its text, which the table sets. */
  function decorate(vs, td, row, field) {
    var cell = cellOf(row, field);
    td.classList.toggle("is-muted", Boolean(cell && cell.muted));
    if (cell && cell.tooltip) ui.tooltip(td, cell.tooltip);
  }

  /* A row's marker: on a Zone row, the airflow imbalance; on a Space, Volume or Floor Segment row, its
     findings, those that block export named first. */
  function marker(vs, row) {
    var record = row.record, target = record.segment || record.volume || record.space;
    if (target) {
      var findings = target.findings || [];
      if (!findings.length) return null;
      var blocking = findings.filter(function (finding) { return finding.blocks_export; });
      var words = (blocking.length ? ["Blocks export."] : []).concat(blocking, findings.filter(function (finding) {
        return !finding.blocks_export;
      })).map(function (item) { return typeof item === "string" ? item : item.message; });
      return { text: "", icon: "alert", tooltip: words.join(" ") };
    }
    return zoneMarker(vs, row);
  }

  /* The Zone row's marker when its supply and extract sums differ by more than the host's threshold. */
  function zoneMarker(vs, row) {
    var sums = row.record.sums;
    if (!sums || !sums.imbalanced) return null;
    var profile = units.profile(fields.AIRFLOW_M3H, preferences.current());
    function flow(value) { return units.format(value, fields.AIRFLOW_M3H, profile); }
    var supply = sums.airflows.v_sup_m3h, extract = sums.airflows.v_eta_m3h;
    return { text: "", icon: "alert", tooltip: "Supply and extract differ by more than 10 percent of the larger: " +
      "supply " + flow(supply) + ", extract " + flow(extract) + ", difference " + flow(Math.abs(supply - extract)) +
      ". Review the airflows." };
  }

  /* What a Zone row sorts by in this view's columns. */
  function sortValue(vs, record, field) {
    if (SORTED.indexOf(field) < 0) return undefined;
    var cell = zoneCell(record, field);
    return cell && cell.value !== undefined ? cell.value : null;
  }

  /* Rows under one parent in the sorted column's order, by the value they show; a row with none keeps its
     place after the others. Name and the Zone fields leave the rows in path order. */
  function sort(vs, list, field, direction) {
    if (SORTED.indexOf(field) < 0) return list;
    var sign = direction === "desc" ? -1 : 1;
    function key(row) {
      var cell = cellOf(row, field);
      if (!cell) return null;
      return cell.text !== undefined ? cell.text : cell.value;
    }
    return list.map(function (row, index) { return { row: row, index: index, key: key(row) }; })
      .sort(function (a, b) {
        if (a.key === null || a.key === undefined || b.key === null || b.key === undefined) {
          return (a.key === null || a.key === undefined) - (b.key === null || b.key === undefined) || a.index - b.index;
        }
        var difference = typeof a.key === "number" && typeof b.key === "number" ? a.key - b.key :
          String(a.key).localeCompare(String(b.key), undefined, { numeric: true });
        return difference * sign || a.index - b.index;
      }).map(function (entry) { return entry.row; });
  }

  /* A Zone's Spaces as search text, so a search for a Space's number or name keeps its Zone. */
  function search(vs, record) {
    return record.spaces.map(spaceText).join(" ");
  }

  /* A row under a Zone the text filter matched through its Spaces shows while its Space matches. A query no
     single Space matches (one spanning two Spaces' text, or the Zone's and a Space's) shows them all. */
  function queryMatch(vs, row, query, zone) {
    function matches(space) { return spaceText(space).toLocaleLowerCase().indexOf(query) >= 0; }
    var space = row.record.space;
    return !space || matches(space) || !zone.spaces.some(matches);
  }

  function spaceText(space) { return space.values.number + " " + space.values.name; }

  /* ---------------------------------------------------------------- the weighting factor filter */

  /* A Floor Segment's band: the host publishes it (`weighting_band`), the key By weighting factor's legend
     uses too, so the panel never re-derives it from the number. */
  function band(segment) {
    return segment.weighting_band;
  }

  function segmentsOf(record) {
    var spaces = record.space ? [record.space] : record.spaces || [];
    if (record.segment) return [record.segment];
    if (record.volume) return record.volume.floor_segments || [];
    return spaces.reduce(function (all, space) {
      return (space.volumes || []).reduce(function (inner, volume) {
        return inner.concat(volume.floor_segments || []);
      }, all);
    }, []);
  }

  function passes(segment, filters) {
    return !filters.weighting_factor || filters.weighting_factor.indexOf(band(segment)) >= 0;
  }

  /* The factors in use, with 1 and 0 always offered, so the menu's paint icons can start either. */
  function filterValues(vs) {
    var seen = { "1": true, "0": true };
    segmentsOf({ spaces: vs.spaces }).forEach(function (segment) {
      seen[band(segment)] = true;
    });
    return Object.keys(seen);
  }

  /* A Zone, Space or Volume passes while a Floor Segment beneath it does; a Floor Segment by its own band. */
  function zoneMatch(vs, record, filters) {
    return !filters.weighting_factor ||
      segmentsOf(record).some(function (segment) { return passes(segment, filters); });
  }

  function rowMatch(vs, row, filters) {
    return zoneMatch(vs, row.record, filters);
  }

  /* The viewport shows the Floor Segment faces that pass. */
  function viewportPaths(vs, record, filters) {
    if (!filters.weighting_factor) return record.zone ? [record.zone.reference.zone_path] : [];
    return segmentsOf(record).filter(function (segment) { return passes(segment, filters); })
      .map(function (segment) { return segment.reference.entity_path; });
  }

  // An open Create Space review holds the view as a draft does, so no tab, view or hand-off covers it.
  function draftReason(vs) {
    if (vs.review.active()) return "Finish the Create Space review first.";
    return vs.cells.draftReason() || vs.selection.draftReason();
  }

  /* Table options: the Spaces readouts, and the label lines while Space labels are on. Each is a view command;
     none writes to the Model. */
  function tableOptions(vs, toggle) {
    var shown = colourBy.readouts(panel.state).filter(function (readout) { return READOUT_LABELS[readout.name]; });
    shown.forEach(function (readout) {
      toggle(READOUT_LABELS[readout.name], readout.on, function () {
        colourBy.showReadout(panel.state, readout.name, !readout.on);
      });
    });
    var labels = shown.filter(function (readout) { return readout.name === "ph_composer.spaces.labels"; })[0];
    if (!labels || !labels.on) return;
    var options = snapshot.value(panel.state, "ph_composer.spaces.label_options") || {};
    LABEL_LINES.forEach(function (line) {
      toggle("Label " + line[1].charAt(0).toLowerCase() + line[1].slice(1), Boolean(options[line[0]]), function () {
        var change = {};
        change[line[0]] = !options[line[0]];
        vs.labelOptions.send("ph_composer.spaces.labels.set_options", change);
      });
    });
  }

  function count(vs) {
    var total = vs.spaces.length;
    return total + (total === 1 ? " Space" : " Spaces");
  }

  var VIEW = {
    id: "ph_composer.spaces", label: "Spaces", order: 20, sections: [SECTION], tiers: 3,
    placeholder: "Zone, number or name",
    // Building-Segment and Level stay available from Table options; Ground depth is the Faces view's.
    zoneFields: ["building_segment", "level"],
    hiddenColumns: { building_segment: true, level: true, net_area_factor: true },
    optionalColumns: [["building_segment", "Building-Segment"], ["level", "Level"],
      ["net_area_factor", "Net area factor"]],
    sorted: SORTED,
    // Four tree levels, each indented, with a chevron and a finding marker, need a wider Hierarchy column.
    widths: { hierarchy: 124, number: 64, floor_area_m2: 104, weighting_factor: 132, weighted_area_m2: 132,
      height_m: 84,
      net_volume_m3: 112, v_sup_m3h: 104, v_eta_m3h: 104, v_tran_m3h: 112, net_area_factor: 112 },
    create: create, consume: consume,
    attach: function (vs, place) { vs.cells.attach(place); },
    prepare: function (vs, rows, state) { vs.cells.prepare(rows, state); vs.selection.prepare(rows); },
    check: function (vs, context) { return vs.selection.check(context); },
    selectionBar: function (vs, overview) { return vs.selection.bar(overview); },
    checkedZones: function (vs) { return vs.selection.checkedZones(); },
    checkZones: function (vs, keys) { vs.selection.pendingZones = keys; },
    // Leaving the view stops the Mark floor tool; the checked rows and their bar stay with the view.
    leave: function (vs) { vs.selection.hideBar(); vs.paint.stop(); },
    // Escape stops a running Mark floor tool first, then clears the checked rows.
    escape: function (vs) {
      if (vs.paint.stop()) return true;
      if (!vs.selection.checked().length) return false;
      if (vs.selection.clear()) panel.repaint();
      return true;
    },
    cell: function (vs, td, row, field) { return vs.cells.render(td, row, field); },
    painted: function (vs) { vs.cells.painted(); },
    draftReason: draftReason,
    cancelDrafts: function (vs) { vs.cells.cancelAll(); vs.selection.cancelDrafts(); },
    canCancelDrafts: function (vs) {
      return vs.cells.cancellable() || !vs.cells.inFlight() && Boolean(vs.selection.draftReason());
    },
    dispose: function (vs) {
      vs.cells.dispose(); vs.actions.dispose(); vs.selection.dispose(); vs.paint.dispose(); vs.review.dispose();
      vs.labelOptions.reset();
    },
    // The Weighting factor column's paint: an icon per factor in its menu, a pressed glyph in its header.
    menuValueAction: function (vs, field, entry) {
      return field === "weighting_factor" ? vs.paint.action(entry) : null;
    },
    headerAction: function (vs, field, label) { return field === "weighting_factor" ? vs.paint.header(label) : null; },
    zoneRecord: zoneRecord, extraRows: extraRows, children: children,
    leadingColumns: leadingColumns, columns: columns, value: value, decorate: decorate, zoneMarker: marker,
    sortValue: sortValue, sort: sort, search: search, queryMatch: queryMatch, count: count,
    colourBy: COLOUR_BY,
    tableOptions: tableOptions,
    filteredFields: { weighting_factor: true },
    filterValues: filterValues, filterLabel: function (vs, field, value) { return value; },
    zoneMatch: zoneMatch, rowMatch: rowMatch, viewportPaths: viewportPaths,
    actions: function (vs, row) { return vs.actions.actions(row); },
    action: function (vs, row, item) { vs.actions.run(row, item); },
    selected: function (vs, row) { return vs.actions.open(row); }
  };
  tableViews.register("ph_composer.zones", VIEW);
  return VIEW;
});
