/* The Faces view of the Zones table: each Zone's Faces as rows beneath it, their type, boundary, area and
 * Assembly as editable columns, the Classify column paint, the checked-Face selection bar and checked-Zone
 * Solve. It registers under the Zones screen's host id (context/EXTENSIBILITY.md, "Zone views") as any other
 * view does. The Zones screen (overview.js) is the host: it owns the Zone rows, the Name column, the Zone's
 * own cells, the text filter and the expansion, and calls this view for everything below a Zone. The view
 * keeps its own state in the object `create` returns and reaches the host's only through `vs.host`.
 *
 * A Face with no record is a row too, under its Zone's "N unclassified Faces" summary. The Zone's row carries
 * their count and the Suggest classification action that gives them all a record. Every write goes through a
 * registered action carrying the values the row was painted from. Select and Locate are separate: a row's
 * checkbox builds the checked set (checked_faces.js) for a bulk assignment, and Locate goes through the view
 * command, which frames and outlines Faces and changes neither the selection nor the Model.
 */
PhComposerUI.define("features/zones/faces_view", ["panel", "workspace", "snapshot", "units", "fields", "face_words",
  "table_views", "features/zones/attached_zone_assignment", "features/zones/zone_settings",
  "features/zones/selection_assignment", "features/zones/assembly_assignment", "features/zones/zone_cells",
  "features/zones/checked_faces", "features/zones/classify", "selection_bar"],
function (panel, ui, snapshot, units, fields, words, tableViews, attachedAssignment, ZoneSettings,
          SelectionAssignment, assemblies, ZoneCells, CheckedFaces, classify, selectionBars) {
  "use strict";
  var AREA = fields.AREA_M2;
  var SHARED_FACE = "Read only while this Face's Zone is shared with another occurrence.";
  /* A short list of unclassified Faces opens by itself; a very long one shows its first rows and offers the
     rest, because a new Zone can hold hundreds. */
  var OPEN_UP_TO = 10, SHOWN_AT_FIRST = 50;
  /* The view's own columns: those a Face's value fills, the ones with a value filter (read from the Face), the
     Colour-by mode each shows and the order the column menus offer. */
  var FACE_FIELDS = { face_type: true, boundary_condition: true, assembly_id: true };
  var SORTED = ["face_type", "boundary_condition", "area_m2", "assembly_id"];
  /* These are this feature's own modes; Assembly binds to the "construction" group, so Window Type reaches this
     column without Zones naming it. */
  var COLOUR_BY = { face_type: { mode: "ph_composer.zones.faces.by_face_type" },
    boundary_condition: { mode: "ph_composer.zones.faces.by_boundary_condition" },
    assembly_id: { group: "construction" } };

  /* This view's state for one Model, with the host handle it reaches the shared state through. */
  function create(host) {
    var vs = { host: host, checked: new CheckedFaces(), showAll: Object.create(null), locating: false,
      faces: [], barTargets: [], limit: Infinity, faceTypes: [], boundaries: [] };
    // The Assembly chip keeps the object it was painted with and reads it again when the user chooses, so it
    // is one object for the session whose fields follow the host's.
    vs.assembly = Object.defineProperties({}, {
      snapshot: { get: function () { return host.snapshot; } },
      session: { get: function () { return host.session; } },
      disposed: { get: function () { return host.disposed; } },
      edits: { get: function () { return host.edits; } },
      assemblyEnabled: { get: function () { return vs.assemblyEnabled; } }
    });
    vs.settings = new ZoneSettings(host.session, host.send, function () { return host.draftReason(); }, host.refuse);
    vs.selectionAssignment = new SelectionAssignment(host.session, host.send, function () {
      return host.draftReason();
    }, host.refuse, function () { return vs.barTargets || []; }, function (faces) {
      return gatedReason(vs, faces, true);
    }, { // A native handoff is presented in this view, shown through the tab's and the view row's guards.
      shown: function (state) {
        return (!state.ui || state.ui.activeTab === "overview") && host.activeView() === VIEW.id;
      },
      show: function () { host.show(VIEW.id); }
    });
    return vs;
  }

  function dispose(vs) {
    if (vs.attachedDraft) vs.attachedDraft.dispose();
    vs.settings.dispose();
    vs.selectionAssignment.dispose();
    if (vs.bar) withdrawBar(vs.bar);
  }

  /* Work in hand that a filter, a tab change or another assignment must not hide or race. */
  function draftReason(vs) {
    if (vs.attachedDraft) return "Finish the Attached zone assignment first.";
    if (vs.selectionAssignment.active()) return "Finish the selected Faces assignment first.";
    if (vs.settings.busy()) return "Wait for the Zone settings change to finish.";
    return null;
  }

  /* What this view reads from one snapshot, before the host builds rows. A new SketchUp selection replaces
     the checked set, and the host has already cleared Locate's outline. */
  function consume(vs, state, send) {
    classify.refresh(state, send);
    // The paint tool runs only while this view or the Assemblies table shows it: a choose that lands after a switch
    // away is stopped.
    if (vs.host.activeView() !== VIEW.id && !assemblies.paintShown(state)) classify.stop();
    var tool = snapshot.value(state, "ph_composer.zones.faces.palette") || {};
    vs.faces = (snapshot.value(state, "ph_composer.zones.faces.faces") || { faces: [] }).faces;
    vs.assemblyEnabled = Boolean(snapshot.value(state, "ph_composer.zones.faces.assemblies") &&
      snapshot.value(state, "ph_composer.zones.faces.faces"));
    vs.attachedRecords = (snapshot.value(state, "ph_composer.zones.faces.attached_zone.list") ||
      { records: [] }).records;
    if (vs.attachedDraft) vs.attachedDraft.consume(state);
    vs.targets = (snapshot.value(state, "ph_composer.zones.faces.selected") || {}).targets || [];
    var change = snapshot.value(state, "ph_composer.zones.faces.selection_change");
    if (vs.checked.sync(vs.targets, change && change.generation)) vs.locating = false;
    vs.barTargets = vs.checked.among(vs.faces).map(function (face) {
      return { reference: face.reference, expected_values: face.values };
    });
    vs.limit = tool.gesture_face_limit || Infinity;
    vs.selectionAssignment.consume(state, vs.attachedRecords);
    vs.faceTypes = tool.face_types || [];
    vs.boundaries = tool.boundary_conditions || [];
    vs.settings.consume(state, snapshot.value(state, "ph_composer.zones.settings"));
    vs.byZone = Object.create(null);
    vs.faces.forEach(function (face) {
      var key = occurrence(face.reference.zone_path);
      (vs.byZone[key] = vs.byZone[key] || []).push(face);
    });
  }

  /* What a Zone row carries for this view: its Faces, recorded and every one, the unclassified count and its
     gross area. Matched by the path that names one Zone occurrence, not by the Zone's record id: a copied Zone
     Group shares its original's dictionary until the copy is repaired, so two occurrences can carry one id. */
  function zoneRecord(vs, record) {
    var own = vs.byZone[occurrence(record.zone.reference.zone_path)] || [];
    var recorded = own.filter(function (face) { return face.state !== "unclassified"; });
    return Object.assign(record, { faces: recorded, every: own, unclassified: own.length - recorded.length,
      area: record.zone.face_area_m2 });
  }

  /* The rows under one Zone row: its recorded Faces, then one summary of the unclassified ones whose short
     list opens by itself, with "Show all" when a very long list shows only its first rows. */
  function children(vs, row) {
    var zone = row.record.zone, own = row.record.every, key = row.key, rows = [];
    function faceRow(face, parent, depth) {
      return { key: JSON.stringify(["Face", zone.reference.zone_path, face.reference.entity_path]),
        parent: parent, tier: "Face", depth: depth,
        record: { id: face.reference.entity_id, name: words.faceName(face, own), place: own.indexOf(face) + 1,
          face: face, gated: ZoneCells.gated(zone) } };
    }
    row.record.faces.forEach(function (face) { rows.push(faceRow(face, key, 1)); });
    var waiting = own.filter(function (face) { return face.state === "unclassified"; });
    if (!waiting.length) return rows;
    var summary = JSON.stringify(["Unclassified", zone.reference.zone_path]);
    var all = Boolean(vs.showAll[summary]) || waiting.length <= SHOWN_AT_FIRST;
    rows.push({ key: summary, parent: key, tier: "Faces", depth: 1,
      record: { id: summary, faces: waiting, summary: true, area: zone.unclassified_face_area_m2,
        name: waiting.length + (waiting.length === 1 ? " unclassified Face" : " unclassified Faces") } });
    (all ? waiting : waiting.slice(0, SHOWN_AT_FIRST)).forEach(function (face) {
      rows.push(faceRow(face, summary, 2));
    });
    if (!all) {
      rows.push({ key: JSON.stringify(["More", zone.reference.zone_path]), parent: summary, tier: "Show all",
        depth: 2, record: { id: summary, faces: [], more: summary,
          name: (waiting.length - SHOWN_AT_FIRST) + " more unclassified " +
            (waiting.length - SHOWN_AT_FIRST === 1 ? "Face" : "Faces") } });
    }
    return rows;
  }

  /* Whether a row this view adds opens by default: a short unclassified list, decided once when it first
     appears so it does not snap shut or open under the user as the count changes. */
  function initiallyOpen(vs, row) {
    return row.record.summary ? row.record.faces.length <= OPEN_UP_TO : null;
  }

  function occurrence(path) {
    return JSON.stringify(path || []);
  }

  function columns(vs, profile) {
    return [["face_type", "Type"], ["boundary_condition", "Boundary"],
      ["area_m2", units.header("Gross area", AREA, profile)], ["assembly_id", "Assembly"]];
  }

  /* The Zone row's marker for this view, after the host's own (a shared or nested Zone): its unclassified
     Faces. */
  function zoneMarker(vs, row) {
    var count = row.record.unclassified;
    if (!count) return null;
    return { text: String(count),
      tooltip: count + " unclassified Faces in this Zone have no record yet. Suggest classification writes one " +
        "for each of them and leaves every Face that already has one alone." };
  }

  /* A Zone row and its unclassified summary show the totals the host published for the occurrence. */
  function value(vs, row, field, profile) {
    var face = row.record.face;
    if (!face) return field === "area_m2" && !row.record.more ? area(row.record.area, profile) : "";
    if (field === "assembly_id") return "";
    if (field === "face_type") return words.faceType(face.values.face_type);
    if (field === "boundary_condition") return words.boundary(face.values.boundary_condition);
    if (field === "area_m2") return area(face.area_m2, profile);
    return "";
  }

  function area(squareMetres, profile) {
    return units.format(squareMetres, AREA, profile, { showUnit: false });
  }

  /* What a chip in this column offers: the values the host published, less the ones a chip cannot set on
     its own. A Face already holding one of those keeps it and its cell stays read only. */
  function choices(vs, field) {
    return (field === "face_type" ? vs.faceTypes : vs.boundaries)
      .filter(function (value) { return value === "AttachedZone" || !words.UNCHOOSABLE[value]; });
  }

  function chipLabel(field, value) {
    return field === "face_type" ? words.faceType(value) : words.boundary(value);
  }

  /* What a Face's type or boundary cell still needs, in words, or null. The host's verdict for the whole row
     is `state`; this says which cell it is about, so the flag sits where the fix is made. */
  function problem(face, field) {
    if (!face || (field !== "face_type" && field !== "boundary_condition")) return null;
    if (!face.values[field]) return field === "face_type" ? "Type not set" : "Boundary not set";
    if (field !== "boundary_condition") return null;
    if (face.attached_zone_state && face.attached_zone_state !== "resolved") {
      return "The Attached zone record is missing. Choose one.";
    }
    if (face.adjacency_state && face.adjacency_state !== "current") {
      return "This adjacency is out of date. Run Solve adjacencies.";
    }
    return null;
  }

  function flag(td, issue, hint) {
    td.classList.toggle("is-flagged", Boolean(issue));
    ui.tooltip(td, issue || hint || "");
  }

  function decorate(vs, td, row, field) {
    flag(td, problem(row.record.face, field));
  }

  /* A value a chip cannot set here (a paired Surface, an Air boundary) shows as the same pill, read only,
     with what sets it in its tooltip. An earlier control, if the cell had one, is forgotten. */
  function readOnly(td, field, face, why) {
    var stored = face.values[field];
    td.className = "col-" + field + (stored ? " phc-pill-cell" : "");
    td._chip = td._attachedChip = td._chipValues = null;
    if (!stored) {
      // The table paints the text; a pill this cell held before goes with it.
      if (td._pill && td._pill.parentNode === td) td.removeChild(td._pill);
      td._pill = null;
      return false;
    }
    var pill = td._pill;
    if (!pill || pill.parentNode !== td) {
      pill = td._pill = ui.element("span", "phc-enum-pill");
      td.replaceChildren(pill);
    }
    pill.textContent = chipLabel(field, stored);
    words.paintFill(pill, field, stored);
    var hint = why || "Read only. " + (words.UNCHOOSABLE[stored] ?
      pill.textContent + ": " + words.UNCHOOSABLE[stored] : pill.textContent);
    flag(td, problem(face, field), hint);
    return true;
  }

  /* Type and boundary are editable chips; area is read only. An edit sends the values the row was painted
     from, so a Model that changed underneath refuses rather than overwriting.

     The control is built once per cell and repainted afterwards. Rebuilding it on every snapshot would take
     the user's open dropdown with it, and a snapshot follows every viewport click.

     A stored value the chip does not offer is shown as text rather than silently missing from the control:
     an `AirBoundary` Face, or one the solver paired, reads what it is and refuses the edit. */
  function cell(vs, td, row, field) {
    var face = row.record.face, offered, chip, host = vs.host;
    // A Face with no record has nothing to hang an Assembly on yet; its type or boundary comes first.
    if (field === "assembly_id") {
      if (!face || face.state !== "unclassified") {
        var painted = assemblies.cell(td, row, vs.assembly, function () { return host.draftReason(); }, host.refuse);
        if (painted && row.record.gated) { td._assemblyChip.disabled = true; ui.tooltip(td, SHARED_FACE); }
        else if (painted) ui.tooltip(td, "");
        return painted;
      }
      // Back to text: the control this cell may have held (the Face had a record until an Undo) is forgotten.
      if (td._assemblyChip) { td._assemblyChip = null; td.className = "col-assembly_id"; }
      return false;
    }
    if (!face || (field !== "face_type" && field !== "boundary_condition")) return false;
    var issue = problem(face, field);
    if (row.record.gated) return readOnly(td, field, face, SHARED_FACE);
    if (field === "boundary_condition" && face.values.boundary_condition === "AttachedZone") {
      attachedCell(vs, td, row);
      flag(td, issue);
      return true;
    }
    td._attachedChip = null;
    offered = choices(vs, field);
    if (!offered.length) return readOnly(td, field, face);
    if (face.values[field] && offered.indexOf(face.values[field]) < 0) return readOnly(td, field, face);
    chip = td._chip;
    // A Face with no value here yet reads "?": the flag sits on the cell that needs it.
    var missing = !face.values[field], signature = (missing ? "?," : "") + offered.join(",");
    if (!chip || td._chipValues !== signature) {
      var hadFocus = Boolean(chip) && document.activeElement === chip;
      chip = ui.element("select", "phc-cell-input phc-enum-cell");
      if (missing) {
        var unset = ui.option("", "?");
        unset.disabled = true;
        chip.appendChild(unset);
      }
      offered.forEach(function (choice) {
        var option = ui.element("option", "", chipLabel(field, choice));
        option.value = choice;
        chip.appendChild(option);
      });
      chip.addEventListener("change", function () {
        words.paintFill(chip, field, chip.value);
        if (field === "boundary_condition" && chip.value === "AttachedZone") {
          openAttached(td._view, td._face, chip);
          chip.value = td._face.values[field] || "";
          words.paintFill(chip, field, chip.value);
        } else apply(td._view, td._face, field, chip.value);
      });
      td.className = "col-" + field + " phc-editable-cell";
      td.replaceChildren(chip);
      td._chip = chip;
      td._chipValues = signature;
      // Filling a "?" rebuilds the control without it; the user's place in the table stays.
      if (hadFocus) chip.focus();
    }
    td._view = vs;
    td._face = face;
    chip.value = face.values[field] || "";
    words.paintFill(chip, field, face.values[field]);
    chip.disabled = host.edits.busy();
    chip.setAttribute("aria-label", (missing ? "Set " : "") + row.record.name +
      (field === "face_type" ? " type" : " boundary"));
    ui.tooltip(td, "");
    flag(td, issue);
    return true;
  }

  function attachedCell(vs, td, row) {
    var chip = td._attachedChip;
    if (!chip) {
      chip = ui.button("Attached zone", function () { openAttached(td._view, td._face, chip); });
      chip.className = "phc-cell-input";
      td.className = "col-boundary_condition phc-editable-cell";
      td.replaceChildren(chip); td._attachedChip = chip; td._chip = null; td._chipValues = null;
    }
    td._view = vs; td._face = row.record.face;
    chip.disabled = vs.host.edits.busy();
    chip.setAttribute("aria-label", row.record.name + " boundary");
    ui.tooltip(chip, "Choose or create an Attached zone");
    return true;
  }

  function openAttached(vs, face, trigger) {
    if (vs.attachedDraft) return;
    vs.attachedDraft = attachedAssignment.open(vs.host.session, vs.host.send, vs.host.revision, face,
      vs.attachedRecords, trigger, function () { vs.attachedDraft = null; panel.repaint(); });
  }

  function apply(vs, face, field, chosen) {
    var intent = { face_type: { mode: "keep" }, boundary_condition: { mode: "keep" } };
    intent[field] = { mode: "set", value: chosen };
    vs.host.edits.run("ph_composer.zones.faces.classify",
      { faces: [face.reference], intent: intent, expected_values: face.values });
  }

  /* The Zone occurrences every write refuses, keyed by path, and why a gesture naming one of them cannot run.
     A bulk change is refused whole rather than quietly leaving out the Faces the user checked. */
  function gatedReason(vs, references, selected) {
    var count = references.filter(function (reference) {
      return vs.host.gated[occurrence((reference.reference || reference).zone_path)];
    }).length, noun = selected ? " selected" : " checked";
    if (!count) return null;
    return count + noun + (count === 1 ? " Face is" : " Faces are") + " in a shared Zone, which is read only. " +
      (selected ? "Select only Faces in other Zones to assign them." :
        "Uncheck " + (count === 1 ? "it" : "them") + " to assign the rest.");
  }

  /* ---------------------------------------------------------------- filters, sort and search */

  /* A Face keeps its stored values in `values`. */
  function filterValue(face, field) {
    var value = face.values[field];
    return value === null || value === undefined ? "" : String(value);
  }

  /* A value's words in a filter: a Face with no type or boundary is Unclassified. */
  function filterLabel(vs, field, value) {
    if (field === "face_type" || field === "boundary_condition") {
      return value ? chipLabel(field, value) : "Unclassified";
    }
    if (!value) return "None";
    var record = assemblies.choices(vs.host.snapshot, []).filter(function (entry) { return entry.id === value; })[0];
    return record ? record.name : "Missing Assembly";
  }

  /* Present values plus every declared paint choice. */
  function filterValues(vs, field) {
    var seen = Object.create(null), values = [];
    vs.faces.forEach(function (face) {
      var value = filterValue(face, field);
      if (!seen[value]) { seen[value] = true; values.push(value); }
    });
    classify.values(field).forEach(function (entry) {
      if (!seen[entry.value]) { seen[entry.value] = true; values.push(entry.value); }
    });
    return values;
  }

  function matches(face, filters) {
    return Object.keys(FACE_FIELDS).every(function (field) {
      return !filters[field] || filters[field].indexOf(filterValue(face, field)) >= 0;
    });
  }

  function filtered(filters) {
    return Object.keys(FACE_FIELDS).some(function (field) { return Boolean(filters[field]); });
  }

  /* What a Zone row sorts by in this view's columns: its gross area; a Face field leaves the Zones in order
     and orders the Faces within each. */
  function sortValue(vs, record, field) {
    if (field === "area_m2") return record.area;
    return FACE_FIELDS[field] ? null : undefined;
  }

  /* A Zone passes this view's filters while one of its Faces does; a Face row shows while it passes, and a
     summary row while one of its Faces does. */
  function zoneMatch(vs, record, filters) {
    return !filtered(filters) || record.every.some(function (face) { return matches(face, filters); });
  }

  function rowMatch(vs, row, filters) {
    if (row.record.face) return matches(row.record.face, filters);
    return row.record.more ? true : row.record.faces.some(function (face) { return matches(face, filters); });
  }

  /* A Zone's Faces as search text, so a search for "Ground" keeps the Zone that has one. */
  function search(vs, record) {
    return [record.unclassified ? "unclassified" : ""].concat(record.faces.map(function (face) {
      var assigned = assemblies.choices(vs.host.snapshot, []).filter(function (record) {
        return record.id === face.values.assembly_id;
      })[0];
      return words.faceType(face.values.face_type) + " " + words.boundary(face.values.boundary_condition) + " " +
        (assigned ? assigned.name : face.values.assembly_id || "");
    })).join(" ");
  }

  /* The sorted column orders a Zone's Faces where a Face has that value (its area, its type, boundary or
     Assembly), so a sort changes something even when the Model has one Zone; a Zone field leaves the Faces in
     place order. A Face's name orders by its place number, not its text: the text starts with the Face's type,
     and choosing a type in a chip must not move the row out from under the user. A summary row and "Show all"
     keep their place after the Faces. */
  function sort(vs, list, field, direction) {
    var sign = direction === "desc" ? -1 : 1;
    function faceValue(row) {
      var face = row.record.face;
      if (field === "area_m2") return Number(face.area_m2) || 0;
      return FACE_FIELDS[field] ? filterLabel(vs, field, filterValue(face, field)) : row.record.place;
    }
    function byFace(a, b) {
      var left = faceValue(a), right = faceValue(b);
      var difference = typeof left === "number" ? left - right : ui.compareText(left, right);
      return difference * sign || a.record.place - b.record.place;
    }
    var faces = list.filter(function (row) { return row.record.face; }).sort(byFace);
    return faces.concat(list.filter(function (row) { return !row.record.face; }));
  }

  /* The occurrence mask the viewport shows under this view's filters: every Face that passes, or, with only
     Zone filters, each passing Zone whole (its Window units beside its Faces included). */
  function viewportPaths(vs, record, filters) {
    if (!filtered(filters)) return [record.zone.reference.zone_path];
    return record.every.filter(function (face) { return matches(face, filters); })
      .map(function (face) { return face.reference.zone_path.concat(face.reference.entity_path); });
  }

  /* ---------------------------------------------------------------- row actions and Locate */

  function actions(vs, row) {
    if (row.record.more) return [];
    var locatable = row.record.face || (row.record.every || row.record.faces).length;
    var items = [{ id: "locate", icon: "locate", disabled: !locatable,
      label: locatable ? "Locate " + row.record.name : "Nothing to locate: " + row.record.name + " has no Faces" }];
    return items;
  }

  /* The Zone row's own action for this view, after the host's: Suggest classification for its unclassified
     Faces. */
  function zoneActions(vs, row) {
    if (!row.record.unclassified) return [];
    var shared = ZoneCells.gated(row.record.zone);
    return [{ id: "suggest", icon: "sort", disabled: shared, label: shared ?
      "Suggest classification is unavailable: " + row.record.name + " is read only" :
      "Suggest classification for " + row.record.name }];
  }

  function action(vs, row, item) {
    if (item.id === "locate") { locate(vs, row); return true; }
    if (item.id === "suggest") {
      vs.host.edits.run("ph_composer.zones.faces.auto_classify", { zone: row.record.zone.reference });
      return true;
    }
    return false;
  }

  function inspect(vs, row) {
    if (row.record.more) { vs.showAll[row.record.more] = true; panel.repaint(); }
  }

  function locate(vs, row) {
    locateFaces(vs, row.record.face ? [row.record.face.reference]
      : (row.record.every || row.record.faces).map(function (face) { return face.reference; }));
  }

  /* A Locate is never dropped: while the channel waits on an earlier command (a clear the same click's press
     sent), it goes untracked; the host answers in order. */
  function locateFaces(vs, references) {
    if (!references.length) return;
    var params = { faces: references }, look = vs.host.look;
    if (look.busy()) look.send("ph_composer.zones.faces.locate", params);
    else look.run("ph_composer.zones.faces.locate", params);
    vs.locating = true;
  }

  /* Locate's outline lasts until the next pointer press in the panel outside a Locate control, Escape, the
     next Locate or a new selection; the host clears it on the last two, and this sends one clear for the
     others, only while one is showing. While the Locate is still in flight the clear goes after it,
     untracked, rather than being dropped; the host answers in order. */
  function clearLocate(vs) {
    if (!vs || !vs.locating) return false;
    vs.locating = false;
    var look = vs.host.look;
    if (look.busy()) look.send("ph_composer.zones.faces.clear_locate", {});
    else look.run("ph_composer.zones.faces.clear_locate", {});
    return true;
  }

  /* Escape for this view, after any open bubble or menu: the Classify palette, open or in use, takes its own
     first, then the checked set, then Locate's outline. True when this view used the key. */
  function escape(vs) {
    if (classify.showing()) return false;
    if (vs.checked.among(vs.faces).length) { vs.checked.clear(); panel.repaint(); return true; }
    return clearLocate(vs);
  }

  /* Leaving this view turns the paint tool off and hides the checked-Face bar; the checked set and Locate's
     outline stay. An open Attached zone draft holds the view until it is saved or cancelled. */
  function leave(vs) {
    classify.stop();
    if (vs.bar) vs.bar.hide();
    vs.settings.bubble.close(false);
  }

  /* Another tab can open this view with Faces checked and, with `locate`, framed (the Assemblies tab's
     "Select faces using"). Locating here keeps the outline this view's to clear. */
  function navigate(vs, intent) {
    if (!intent.check) return;
    vs.checked.replace(intent.check);
    if (intent.locate) locateFaces(vs, intent.check);
  }

  /* ---------------------------------------------------------------- the checked set and its bar */

  /* What the shared table's checkboxes do in this view: a Face row checks its Face, a Zone or summary row
     checks the Faces beneath it, and the header box checks every Face the filters show. Called as the table
     paints, with the rows it shows, the Zone rows that pass the filters and every Zone row. */
  function check(vs, context) {
    var visible = context.visible, filterFaces = facesShown(context.zoneRows, context.filters);
    vs.checkedZones = context.allZoneRows.filter(function (row) { return vs.checked.state(row) === true; })
      .map(function (row) { return row.record.zone; });
    vs.hiddenChecked = vs.checked.among(vs.faces).length - vs.checked.among(filterFaces).length;
    return { state: function (row) { return vs.checked.state(row); },
      toggle: function (row, event) { vs.checked.toggle(row, event, visible); panel.repaint(); },
      header: function () { return Boolean(filterFaces.length) && vs.checked.stateOf(filterFaces); },
      toggleAll: function () { vs.checked.toggleAll(filterFaces); panel.repaint(); },
      label: function (row) { return (vs.checked.state(row) === true ? "Uncheck " : "Check ") + row.record.name; },
      headerLabel: function (value) { return (value === true ? "Uncheck" : "Check") + " every Face the filter shows"; },
      any: function () { return vs.checked.among(vs.faces).length > 0; } };
  }

  /* The Faces the filters show, whether or not their rows are open or painted (a long unclassified list
     paints only its first fifty): what the header box checks, and what "hidden" in the bar counts against. */
  function facesShown(visibleZones, filters) {
    var faceFiltered = filtered(filters);
    return visibleZones.reduce(function (all, row) {
      return all.concat(row.record.every.filter(function (face) {
        return !faceFiltered || matches(face, filters);
      }));
    }, []);
  }

  /* A selection bar belongs to one Model and leaves with it. */
  function withdrawBar(bar) {
    if (bar.root.parentNode) bar.root.parentNode.removeChild(bar.root);
  }

  /* Checked-Face controls remain independent of the native paint tool. */
  function selectionBar(vs, overview) {
    var bar = vs.bar;
    if (!bar) {
      bar = vs.bar = new selectionBars.SelectionBar("Checked Faces", function () {
        vs.checked.clear(); panel.repaint();
      });
      vs.selectionControls = selectionControls(vs);
      bar.controls.appendChild(vs.selectionControls.root);
      vs.zoneSolveControls = zoneSolveControls(vs);
      bar.controls.appendChild(vs.zoneSolveControls.root);
    }
    if (bar.root.parentNode !== overview) overview.appendChild(bar.root);
    var count = vs.barTargets.length;
    vs.selectionControls.root.hidden = false;
    vs.zoneSolveControls.paint();
    if (count) {
      bar.show(count + (count === 1 ? " Face selected" : " Faces selected") +
        (vs.hiddenChecked ? ", " + vs.hiddenChecked + " hidden" : ""), true);
      vs.selectionControls.paint();
    } else bar.hide();
    return bar;
  }

  /* Solve mutates whole Zones. A mixed Zone is not a target, even though some of its Faces are checked. The
     solver reads neighbours and refuses if a reciprocal write would leave this explicit scope. */
  function zoneSolveControls(vs) {
    var root = ui.element("div", "phc-zone-selection-controls"), host = vs.host;
    var count = ui.element("span", "phc-checked-zone-count");
    count.setAttribute("role", "status");
    var label = "Solve adjacencies for checked Zones";
    var solve = ui.button(label, function () {
      var zones = vs.checkedZones || [];
      if (zones.length < 2 || host.edits.busy() || sharedChecked()) return;
      var reason = host.draftReason();
      if (reason) return host.refuse(reason);
      host.edits.run("ph_composer.zones.solve_adjacency", {
        zones: zones.map(function (zone) { return zone.reference; })
      });
      panel.repaint();
    });
    solve.classList.add("phc-toolbar-button");
    solve.setAttribute("aria-label", label);
    solve.replaceChildren(ui.glyph("link"), ui.element("span", "", label));
    function sharedChecked() {
      return (vs.checkedZones || []).filter(function (zone) { return ZoneCells.gated(zone); }).length;
    }
    var why = ui.element("span", "phc-selection-limit");
    root.appendChild(count); root.appendChild(solve); root.appendChild(why);
    return { root: root, paint: function () {
      var total = (vs.checkedZones || []).length, shared = sharedChecked();
      root.hidden = !total;
      var reason = shared ? shared + (shared === 1 ? " checked Zone is" : " checked Zones are") +
        " shared with another occurrence and read only. Uncheck " + (shared === 1 ? "it" : "them") +
        " to solve." : null;
      why.hidden = !reason;
      if (reason && why._reason !== reason) {
        why._reason = reason; why.replaceChildren(ui.reasonButton("Solve", reason));
      }
      count.textContent = total + (total === 1 ? " Zone checked" : " Zones checked");
      solve.disabled = host.edits.busy() || total < 2 || Boolean(shared);
      ui.tooltip(solve, reason ? reason :
        total < 2 ? "Check at least two complete Zones. Partially checked Zones are not included." :
        "Only fully checked Zones are solved, including those hidden by filters. Check touching neighbours too.");
    } };
  }

  /* What the checked Faces share, one attribute at a time: each choice applies at once to every Face checked,
     hidden by a filter or not, as one Undo step. A value they do not share reads "Mixed". Attached zone needs
     a record, so it is offered where a record can be chosen: a Face's own row and the right-click menu. More
     Faces than one gesture may change disables the controls, with the limit as the reason. */
  function selectionControls(vs) {
    var root = ui.element("div", "phc-selection-controls"), host = vs.host;
    var controls = {};
    var over = ui.element("span", "phc-selection-limit");
    function common(field) {
      var values = vs.barTargets.map(function (target) { return target.expected_values[field] || ""; });
      return values.every(function (value) { return value === values[0]; }) ? values[0] : null;
    }
    function control(field, label) {
      var select = ui.element("select"), wrap = ui.element("label", "phc-selection-field");
      select.setAttribute("aria-label", label + " for selected Faces");
      select.addEventListener("change", function () {
        var reason = host.draftReason(), chosen = select.value;
        if (!chosen) { paint(); return; }
        if (reason) { paint(); host.refuse(reason); return; }
        var intent = { face_type: { mode: "keep" }, boundary_condition: { mode: "keep" } };
        var params = { faces: vs.barTargets.map(function (target) { return target.reference; }), intent: intent };
        intent[field] = { mode: "set", value: chosen };
        // One Face is guarded by the values it was read with; several rarely share them, so the Model's own
        // checks stand alone.
        if (vs.barTargets.length === 1) params.expected_values = vs.barTargets[0].expected_values;
        host.edits.run("ph_composer.zones.faces.classify", params);
        paint();
      });
      wrap.appendChild(ui.element("span", "", label));
      wrap.appendChild(select);
      root.appendChild(wrap);
      controls[field] = select;
    }
    function paint() {
      var tooMany = vs.barTargets.length > vs.limit, shared = gatedReason(vs, vs.barTargets);
      var reason = shared || (tooMany ? "Check at most " + vs.limit + " Faces to assign them together." : null);
      over.hidden = !reason;
      if (reason && over._reason !== reason) {
        over._reason = reason;
        over.replaceChildren(ui.reasonButton("Assign", reason));
      }
      tooMany = Boolean(reason);
      Object.keys(controls).forEach(function (field) {
        var select = controls[field], shared = common(field);
        var offered = choices(vs, field).filter(function (choice) { return choice !== "AttachedZone"; });
        var first = shared === null ? "Mixed" :
          shared && offered.indexOf(shared) < 0 ? chipLabel(field, shared) : "Not set";
        // A value the tree shows as read only (a paired Surface, an Air boundary, an Attached zone) is read
        // only here too: the Face's own row is where it can be changed.
        var locked = vs.barTargets.some(function (target) {
          var stored = target.expected_values[field];
          return Boolean(stored) && offered.indexOf(stored) < 0;
        });
        var signature = first + "|" + offered.join(",");
        // Rebuilt only when what it offers changes: a snapshot follows every viewport click, and rebuilding
        // would close a dropdown the user has open.
        if (select._signature !== signature) {
          var placeholder = ui.option("", first);
          placeholder.disabled = true;
          select.replaceChildren(placeholder);
          offered.forEach(function (choice) { select.appendChild(ui.option(choice, chipLabel(field, choice))); });
          select._signature = signature;
        }
        select.value = shared && offered.indexOf(shared) >= 0 ? shared : "";
        select.disabled = host.edits.busy() || !offered.length || locked || tooMany;
        ui.tooltip(select, locked ? "Set on the Face's own row" : "");
      });
      assembly.hidden = vs.selectionAssignment.root.hidden;
      vs.selectionAssignment.assembly.limit(tooMany);
    }
    var assembly = ui.element("label", "phc-selection-field");
    control("face_type", "Type");
    control("boundary_condition", "Boundary");
    assembly.appendChild(ui.element("span", "", "Assembly"));
    assembly.appendChild(vs.selectionAssignment.root);
    root.appendChild(assembly);
    root.appendChild(over);
    return { root: root, paint: paint };
  }

  var VIEW = {
    id: "ph_composer.zones.faces", label: "Geometry", order: 10, sections: ["ph_composer.zones.faces.faces"],
    placeholder: "Zone, type or boundary",
    help: "Select Faces in SketchUp, or check their rows, to edit them together in the bar under the table. " +
      "A column's palette icon colours the Model by that column; its menu sorts and filters.",
    colourBy: COLOUR_BY, sorted: SORTED, filteredFields: FACE_FIELDS,
    // Most Zones keep the default, so Ground depth waits in Table options until it is wanted.
    hiddenColumns: { ground_depth_mm: true },
    // Sized so the whole table shows at the panel's usual width with the Zone columns beside them.
    widths: { face_type: 126, boundary_condition: 110, area_m2: 104, assembly_id: 156 },
    create: create, dispose: dispose, draftReason: draftReason, consume: consume, zoneRecord: zoneRecord,
    children: children, initiallyOpen: initiallyOpen, columns: columns, zoneMarker: zoneMarker, value: value,
    cell: cell, decorate: decorate, filterLabel: filterLabel, filterValues: filterValues,
    zoneMatch: zoneMatch, rowMatch: rowMatch, search: search, sort: sort, sortValue: sortValue,
    viewportPaths: viewportPaths,
    actions: actions, zoneActions: zoneActions, action: action, inspect: inspect, locate: locate,
    clearLocate: clearLocate, escape: escape, navigate: navigate, check: check, selectionBar: selectionBar,
    settings: function (vs) { return vs.settings.bubble.root; },
    leave: leave,
    // Zones every Face of which is checked, and checking every Face of Zones another view handed over.
    checkedZones: function (vs) {
      return (vs.checkedZones || []).map(function (zone) {
        return JSON.stringify(["Zone", zone.reference.zone_path]);
      });
    },
    checkZones: function (vs, keys) {
      vs.checked.replace(keys.reduce(function (all, key) {
        var faces = (vs.byZone || {})[occurrence(JSON.parse(key)[1])] || [];
        return all.concat(faces.map(function (face) { return face.reference; }));
      }, []));
    },
    leaveReason: function (vs) {
      return classify.draftReason() ||
        (vs.settings.held() ? "Correct the Faces settings, or press Escape to restore them, first." : null);
    },
    // The Classify palette paints this view's columns from their header and their menu.
    headerAction: function (vs, field, label) { return classify.header(field, label); },
    menuValueAction: function (vs, field, entry) { return classify.paint(field, entry.value, entry.label); },
    menuExtra: function (vs, field, root, anchor, close, reopen) {
      classify.extra(field, root, anchor, close, reopen);
    }
  };
  tableViews.register("ph_composer.zones", VIEW);
  return VIEW;
});
