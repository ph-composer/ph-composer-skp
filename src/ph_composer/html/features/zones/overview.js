/* The Zones screen: one table of Zones read through views (context/EXTENSIBILITY.md, "Zone views"). Zones are
 * rows; a Zone's own fields are columns on its row, and the active view supplies the rows beneath each Zone
 * and the columns that describe them. Views register with the kit's `table_views` under this screen's host
 * id; this file names none of them. Faces is one, registered as any other. A row of view tabs above the
 * heading switches between them, shown while more than one is listed.
 *
 * Colour by, sort and value filters live in the column headers, the shared view controls above the table
 * hold the text filter, the count and Table options, and a view may float a selection bar over the bottom of
 * the table. The table is the shared record table; this file holds the Zone rows, the Name column, the
 * Zone's own cells, the filter, the expansion and the one call that paints the table, and asks the active
 * view for everything else through its hooks. Every hook receives the view's own state first; the view
 * reaches this screen's state only through the `host` handle it was created with.
 */
PhComposerUI.define("features/zones/overview", ["panel", "workspace", "request", "snapshot", "units",
  "unit_preferences", "table", "view_controls", "column_menu", "sections/colour_by", "fields", "subtabs",
  "table_views", "features/zones/zone_cells", "features/zones/zone_options", "features/zones/option_dialog"],
function (panel, ui, requests, snapshot, units, preferences, tables, viewControls, columnMenus, colourBy, fields,
          Subtabs, tableViews, ZoneCells, zoneOptions, OptionDialog) {
  "use strict";
  var HOST = "ph_composer.zones";
  var registry = tableViews.host(HOST);
  var AREA = fields.AREA_M2;
  var ORDER_FIELDS = [["name", "Name"], ["area_m2", "Area"]];
  // What the Zones read says is wrong with a Zone occurrence, in the words the user needs. Both the
  // original and its copy carry the state, so the marker names the condition, not which one is the copy.
  // A shared Zone's marker is an alert icon: no word fits beside "Zone" in the Hierarchy column.
  // Every write to such a Zone refuses, so its cells are read only.
  var ZONE_STATES = {
    ambiguous: { text: "Shared", icon: "alert",
      tooltip: "Another Zone carries the same identity, as a copy does. Its cells are read only until it is " +
        "made independent, because an edit here could reach the other one." },
    shared_definition: { text: "Shared", icon: "alert",
      tooltip: "This Zone shares its Faces with another occurrence: a copy, or another instance of the same " +
        "component. Its cells are read only, because an edit here would reach both." },
    wrong_hierarchy: { text: "nested",
      tooltip: "This Zone sits inside another Zone. A Zone is one Room, so a Zone within a Zone " +
        "cannot be exported as it stands." }
  };
  // The Zone's own columns and the Colour-by mode each shows; a view lists in `zoneFields` which of the
  // in-place cells it shows beside its own columns, all three when it says nothing.
  var ZONE_FIELDS = ["building_segment", "level", "ground_depth_mm"];
  var ZONE_COLOUR_BY = { name: { mode: "ph_composer.zones.by_zone" },
    building_segment: { mode: "ph_composer.zones.by_building_segment" },
    level: { mode: "ph_composer.zones.by_level" } };
  var ZONE_SORTED = ["name", "building_segment", "level", "ground_depth_mm"];
  var ZONE_FILTERED = { building_segment: true, level: true };
  var ZONE_WIDTHS = { name: 142, building_segment: 136, level: 84, ground_depth_mm: 128 };
  // Listed while no view is: the Zone rows alone, with nothing beneath them.
  var NO_VIEW = { id: "", label: "Zones" };

  var screen = null;
  var MIN_MOUNT = 240;
  var ZONE_DRAFT = "Finish or cancel the Zone edit first.";

  /* One view's hook, called with its own state first; `fallback` when the view does not supply it. */
  function call(slot, name, args, fallback) {
    var hook = slot.view[name];
    return hook ? hook.apply(slot.view, [slot.vs].concat(args || [])) : fallback;
  }

  /* This screen's own state, rebuilt whenever the panel shows a different Model. */
  function forSession(session, send) {
    if (screen && screen.session === session) return screen;
    if (screen) { screen.disposed = screen.host.disposed = true; screen.edits.reset(); screen.look.reset(); }
    if (screen && screen.optionDialog) screen.optionDialog.dispose();
    if (screen && screen.zoneCells) screen.zoneCells.dispose();
    if (screen) Object.keys(screen.slots).forEach(function (id) { call(screen.slots[id], "dispose"); });
    if (screen && screen.independenceDialog) {
      screen.independenceDialog.closeModal();
      var stale = screen.independenceDialog;
      if (stale.parentNode) stale.parentNode.removeChild(stale);
    }
    screen = { session: session, expanded: Object.create(null), slots: Object.create(null), viewId: null,
      edits: requests.channel(session, send, "overview"),
      look: requests.channel(session, send, "locate", "view.invoke") };
    // What a view may reach of this screen; `render` keeps its snapshot fields current.
    var made = screen;
    made.host = { session: session, send: send, edits: made.edits, look: made.look, disposed: false,
      gated: Object.create(null), draftReason: function () { return draftReason(made); }, refuse: refuse,
      // The view shown now, and a way to show one through the tab's and the view row's guards.
      activeView: function () { return made.viewId; },
      show: function (id) {
        var intent = { view: id };
        return panel.navigate("overview", intent) && intent.viewShown === true;
      } };
    screen.zoneCells = new ZoneCells(session, send, refuse, function (field) { screen.optionDialog.open(field); },
      function () { return draftReason(screen, true); });
    screen.optionDialog = new OptionDialog(session, send, function () { return draftReason(screen); },
      function (message, tone) { panel.notify(message, tone); }, function (collection, result) {
        reconcileOptionFilters(screen, collection, result);
      });
    screen.options = tableOptions(screen);
    screen.controls = new viewControls.ViewControls({
      label: "Zones", placeholder: "Zone", fields: ORDER_FIELDS, initialOrder: "name",
      columnSort: true,
      count: zoneCount, expansion: expansion(screen), guard: function () { return draftReason(screen); },
      refused: refuse
    }, function () { panel.repaint(); });
    return screen;
  }

  /* One view's place on this screen for one Model: its state, its surface and table mount, and the column
     widths, hidden columns, menus, filters and sort it keeps while another view is shown. */
  function slot(state, view) {
    var id = view.id, existing = state.slots[id];
    if (existing) return existing;
    var surface = ui.element("div", "phc-zone-view"), mount = ui.element("div", "phc-table-mount");
    // The view's own place in the shared controls row, shown with it: its help, then what it binds there.
    var toolbar = ui.element("div", "phc-view-tools");
    if (view.help) toolbar.appendChild(ui.helpButton("Zones", view.help));
    surface.appendChild(mount);
    var made = state.slots[id] = { view: view, vs: view.create ? view.create(state.host) : {}, surface: surface,
      mount: mount, toolbar: toolbar, columnWidths: {}, hiddenColumns: Object.assign({}, view.hiddenColumns || {}),
      menus: Object.create(null), toggles: Object.create(null),
      filters: Object.create(null), sort: null };
    // The view's own surface and table mount, once, for what it binds there (a range-edit grid).
    call(made, "attach", [{ surface: surface, mount: mount, toolbar: toolbar,
      hiddenColumns: function () { return made.hiddenColumns; } }]);
    return made;
  }

  function active(state) {
    return state.slots[state.viewId];
  }

  /* Work in hand that a filter, a tab change or another assignment must not hide or race. */
  function draftReason(state, skipCells) {
    if (state && state.optionDialog && state.optionDialog.active()) return "Finish the managed options draft first.";
    if (!skipCells && state && state.zoneCells && state.zoneCells.active()) {
      return ZONE_DRAFT;
    }
    var current = state && active(state);
    return current ? call(current, "draftReason", [], null) : null;
  }

  /* A refusal because an edit is held offers to cancel it from the notice, so the way out is in view: a Zone
     edit, or the shown view's draft when it can cancel its drafts (`cancelDrafts`). */
  function refuse(reason) {
    var cells = screen && screen.zoneCells, own = screen && active(screen), action = null;
    if (reason === ZONE_DRAFT && cells) {
      action = { label: "Cancel the Zone edit", run: function () { cells.cancelAll(); panel.repaint(); } };
    } else if (own && own.view.cancelDrafts && call(own, "canCancelDrafts", [], true) &&
        reason === call(own, "draftReason", [], null)) {
      action = { label: "Cancel the edit", run: function () { call(own, "cancelDrafts"); panel.repaint(); } };
    }
    panel.notify(reason, "warning", action);
  }

  /* Held category filters follow explicit merge/removal results; rename keeps the same ID. They are Zone
     filters, held by the controls or, while the shown view lacks their column, by the view that showed it. */
  function reconcileOptionFilters(state, collection, result) {
    var replacements = result.replacement_ids || {};
    [state.controls.columnFilters].concat(Object.keys(state.slots).map(function (id) {
      return state.slots[id].filters;
    })).forEach(function (filters) {
      if (state.optionDialog.adopting) { delete filters.building_segment; delete filters.level; return; }
      var held = filters[collection]; if (!held) return;
      var mapped = held.map(function (id) {
        if (!Object.prototype.hasOwnProperty.call(replacements, id)) return id;
        return replacements[id] || (collection === "level" ? "" : null);
      }).filter(function (id, index, every) { return id !== null && every.indexOf(id) === index; });
      if (mapped.length) filters[collection] = mapped;
      else delete filters[collection];
    });
  }

  /* The control row's count: Zones, how many a filter leaves, what the shown view counts, and how many
     column filters apply. */
  function zoneCount(shown, total, filtered, columnFilters) {
    var noun = total === 1 ? " Zone" : " Zones";
    var text = filtered && shown !== total ? shown + " of " + total + noun : total + noun;
    var own = screen && active(screen), extra = own ? call(own, "count", [], null) : null;
    if (extra) text += " · " + extra;
    return columnFilters ? text + " · " + columnFilters + (columnFilters === 1 ? " filter" : " filters") : text;
  }

  /* ---------------------------------------------------------------- switching views */

  /* The views listed for this snapshot and the one shown: the session's choice while it is listed, else the
     one this computer last showed, else the first. The view row is rebuilt when the listed views change. */
  function settle(state, root, snapshotState) {
    var listed = registry.views(snapshotState), current = active(state);
    // A shown view holding work (a draft, a pending request) stays listed until it lets go, so its controls
    // and results are not stranded when its section is withdrawn.
    if (current && current.shown && current.view.id && listed.indexOf(current.view) < 0 &&
        (call(current, "draftReason", [], null) || call(current, "leaveReason", [], null))) {
      listed = listed.concat([current.view]);
    }
    if (!listed.length) listed = [NO_VIEW];
    var ids = listed.map(function (view) { return view.id; });
    state.listed = listed;
    if (ids.indexOf(state.viewId) < 0) {
      // A shown view that stops being listed leaves as a switch away does.
      var remembered = preferences.tableView(HOST), zones = null;
      var next = slot(state, listed[ids.indexOf(ids.indexOf(remembered) >= 0 ? remembered : ids[0])]);
      if (current && current.shown) {
        zones = call(current, "checkedZones", [], null);
        call(current, "leave");
        stash(state, current, next);
      }
      state.viewId = next.view.id;
      restore(state, next);
      // Handed over once the view switched to has read this snapshot (render does it after consume).
      if (zones && zones.length) state.handover = { slot: next, zones: zones };
    }
    var surfaces = root.querySelector(".phc-zone-views"), owned = listed.map(function (view) {
      return slot(state, view).surface;
    });
    // Another Model's surfaces leave with it; this one's are placed in listing order.
    Array.from(surfaces.children).forEach(function (node) {
      if (owned.indexOf(node) < 0) surfaces.removeChild(node);
    });
    owned.forEach(function (surface) { if (surface.parentNode !== surfaces) surfaces.appendChild(surface); });
    var signature = ids.join("\n");
    if (state.tabsSignature !== signature && listed.length < 2) {
      // One view, or none: no row to choose from, and its surface simply shows.
      state.tabsSignature = signature;
      if (state.tabs) state.tabs.disposed = true;
      state.tabs = null;
      root.querySelector(".phc-view-tabs").replaceChildren();
      slot(state, listed[0]).surface.hidden = false;
    } else if (state.tabsSignature !== signature) {
      state.tabsSignature = signature;
      if (state.tabs) state.tabs.disposed = true;
      state.tabs = new Subtabs({ label: "Zone views", state: state, stateKey: "viewId",
        tabs: listed.map(function (view) {
          return { id: view.id, label: view.label, surface: slot(state, view).surface };
        }),
        guard: function () { return draftReason(state) || call(active(state), "leaveReason", [], null); },
        refused: function (reason) { state.refusedSwitch = reason; refuse(reason); },
        changed: function (id) { switched(state, id); } });
      root.querySelector(".phc-view-tabs").replaceChildren(state.tabs.root);
    }
    root.querySelector(".phc-view-tabs").hidden = listed.length < 2;
    return active(state);
  }

  /* The Subtabs control has already moved `viewId`; the view switched from leaves, the controls take the new
     view's own filters and sort, the page header's settings slot repaints from it, and this computer
     remembers the choice. Nothing is sent to the Model and the SketchUp selection is untouched. */
  function switched(state, id) {
    var previous = Object.keys(state.slots).filter(function (key) {
      return key !== id && state.slots[key].shown;
    })[0];
    var zones = null;
    if (previous) {
      var old = state.slots[previous];
      // The Zones checked in the view switched from are checked in the one switched to.
      zones = call(old, "checkedZones", [], null);
      call(old, "leave");
      stash(state, old, state.slots[id]);
    }
    restore(state, state.slots[id]);
    // Only Zones that are checked are handed over; the view switched to keeps its own checks otherwise.
    if (zones && zones.length) call(state.slots[id], "checkZones", [zones]);
    if (id) panel.setPreference("table_view", id, { scope: HOST });
    // A refusal of an earlier try at a switch no longer holds once a switch goes through.
    if (state.refusedSwitch) panel.withdraw(state.refusedSwitch);
    state.refusedSwitch = null;
    panel.repaint();
  }

  /* A view's column filters and sort leave the shared controls with it. A Zone filter stays while the next
     view shows its column; otherwise it leaves with this view, so no filter applies without its column. */
  function stash(state, own, next) {
    var filters = state.controls.columnFilters, fieldsOwned = own.view.filteredFields || {};
    var nextShows = zoneFields(next).filter(function (field) { return !next.hiddenColumns[field]; });
    own.filters = Object.create(null);
    Object.keys(filters).forEach(function (field) {
      if (fieldsOwned[field] || (ZONE_FILTERED[field] && nextShows.indexOf(field) < 0)) {
        own.filters[field] = filters[field]; delete filters[field];
      }
    });
    own.sort = state.controls.columnSort;
    own.shown = false;
  }

  function restore(state, own) {
    Object.keys(state.slots).forEach(function (id) { state.slots[id].shown = state.slots[id] === own; });
    Object.keys(own.filters).forEach(function (field) { state.controls.columnFilters[field] = own.filters[field]; });
    state.controls.columnSort = own.sort || { field: "name", direction: "asc" };
  }

  /* ---------------------------------------------------------------- columns, filters and sort */

  function zoneFields(own) {
    return own.view.zoneFields || ZONE_FIELDS;
  }

  function viewField(own, field) {
    var profile = units.profile(AREA, preferences.current());
    return call(own, "leadingColumns", [profile], []).concat(call(own, "columns", [profile], []))
      .some(function (column) { return column[0] === field; });
  }

  function sortable(own, field) {
    return ZONE_SORTED.concat(own.view.sorted || []).indexOf(field) >= 0;
  }

  function filtered(own, field) {
    return Boolean(ZONE_FILTERED[field] || (own.view.filteredFields || {})[field]);
  }

  function colourBindings(own) {
    return Object.assign({}, ZONE_COLOUR_BY, own.view.colourBy || {});
  }

  /* A Zone record keeps its stored values in `values`. */
  function filterValue(record, field) {
    var value = zoneOptions.value(record, field);
    return value === null || value === undefined ? "" : String(value);
  }

  /* A value's words in a filter. */
  function filterLabel(state, own, field, value) {
    if ((own.view.filteredFields || {})[field]) return call(own, "filterLabel", [field, value], value);
    if (field === "building_segment" || field === "level") {
      var choice = zoneOptions.find(zoneOptions.read(state.snapshot), field, value);
      if (choice) return choice.values.name;
      var source = (state.zoneRecords || []).filter(function (zone) { return filterValue(zone, field) === value; })[0];
      return source ? zoneOptions.label(zoneOptions.read(state.snapshot), source,
        field) : value ? "Choose a replacement" : "Not set";
    }
    return value || "Not set";
  }

  function columnMenu(state, own, field, label) {
    var menu = own.menus[field];
    if (!menu) {
      var ownColumn = viewField(own, field);
      menu = own.menus[field] = new columnMenus.ColumnMenu({ label: label,
        // A value action that starts something (a paint) closes the menu once it has run.
        valueAction: function (entry) {
          var action = ownColumn ? call(own, "menuValueAction", [field, entry], null) : null;
          if (!action) return null;
          var run = action.run;
          return Object.assign({}, action, { run: function (anchor) { run(anchor); menu.bubble.close(true); } });
        },
        extra: function (root, anchor, close, reopen) {
          if (ownColumn) call(own, "menuExtra", [field, root, anchor, close, reopen]);
          if (field === "building_segment" || field === "level") {
            var manage = ui.button("Manage " + zoneOptions.title(field) + "…", function () {
              close(); anchor.focus(); state.optionDialog.open(field);
            });
            manage.className = "phc-action-menu-item"; root.appendChild(manage);
          }
        },
        sort: sortable(own, field) ? { current: function () { return state.controls.columnDirection(field); },
          choose: function (direction) { state.controls.sortBy(field, direction); } } : null,
        filter: filtered(own, field) ? { values: function () { return filterValues(state, own, field); },
          shown: function () { return state.controls.columnFilter(field); },
          set: function (values) { return state.controls.filterColumn(field, values); } } : null });
    }
    // The label carries a unit (Ground depth), which a unit switch changes.
    menu.options.label = label;
    menu.paint();
    return menu;
  }

  /* Present values plus every declared choice, in reading order, with the blank last. A view's field lists
     its own. */
  function filterValues(state, own, field) {
    var seen = Object.create(null), values = [];
    if ((own.view.filteredFields || {})[field]) values = call(own, "filterValues", [field], []);
    else {
      (state.zoneRecords || []).forEach(function (record) {
        var value = filterValue(record, field);
        if (!seen[value]) { seen[value] = true; values.push(value); }
      });
      zoneOptions.list(zoneOptions.read(state.snapshot), field).forEach(function (choice) {
        if (!seen[choice.id]) { seen[choice.id] = true; values.push(choice.id); }
      });
    }
    return values.map(function (value) { return { value: value, label: filterLabel(state, own, field, value),
      colour: filterColour(state, own, field, value) }; })
      .sort(function (a, b) { return Number(!a.value) - Number(!b.value) || ui.compareText(a.label, b.label); });
  }

  function filterColour(state, own, field, value) {
    var choice = zoneOptions.find(zoneOptions.read(state.snapshot), field, value);
    if (choice && /^#[0-9a-f]{6}$/i.test(choice.values.colour)) {
      return [1, 3, 5].map(function (start) { return parseInt(choice.values.colour.slice(start, start + 2), 16); });
    }
    return colourBy.colour(state.snapshot, colourBindings(own)[field], value);
  }

  function headerActions(state, own, field, label) {
    var actions = [], binding = colourBindings(own)[field];
    if (binding && !own.hiddenColumns[field]) {
      var toggle = own.toggles[field] || (own.toggles[field] = new colourBy.HeaderToggle(binding));
      if (toggle.paint(state.snapshot)) actions.push({ node: toggle.node, persistent: toggle.pressed });
    }
    var paint = viewField(own, field) ? call(own, "headerAction", [field, label], null) : null;
    if (paint) actions.push(paint);
    if (!sortable(own, field) && !filtered(own, field)) return actions;
    var menu = columnMenu(state, own, field, label);
    return actions.concat([{ node: menu.root, persistent: menu.filtered() }]);
  }

  /* A mode a column the shown view displays offers; every other registered mode is offered in Table options. */
  function boundToColumn(own, mode, shown) {
    var bindings = colourBindings(own);
    return Object.keys(bindings).some(function (field) {
      var binding = bindings[field];
      return shown.indexOf(field) >= 0 && !own.hiddenColumns[field] &&
        (binding.mode ? binding.mode === mode.name : binding.group === mode.group);
    });
  }

  /* Table options: show or hide Ground depth, and Colour by for a mode no visible column offers. */
  function tableOptions(state) {
    var menu = new ui.ActionMenu("Table options", { onOpen: function () { fill(); } });
    function toggle(text, pressed, handler) {
      var item = menu.add(text, handler);
      item.classList.add("phc-setting-choice");
      item.setAttribute("aria-pressed", String(pressed));
    }
    function fill() {
      var own = active(state), legend = snapshot.value(panel.state, "ph_composer.colour_by.legend") || { mode: null };
      menu.content.replaceChildren();
      var optional = (zoneFields(own).indexOf("ground_depth_mm") >= 0 ? [["ground_depth_mm", "Ground depth"]] : [])
        .concat(own.view.optionalColumns || []);
      optional.forEach(function (column) {
        toggle(column[1] + " column", !own.hiddenColumns[column[0]], function () {
          var field = column[0], reason = draftReason(state);
          // A held edit keeps the table as it is, so its cell and Cancel stay in view.
          if (reason) return refuse(reason);
          own.hiddenColumns[field] = !own.hiddenColumns[field];
          // No filter applies without a column to clear it from. A Zone column shown again takes the filter
          // the controls hold; an older copy another view kept while the column was hidden goes.
          if (own.hiddenColumns[field]) delete state.controls.columnFilters[field];
          else if (ZONE_FILTERED[field]) {
            Object.keys(state.slots).forEach(function (id) { delete state.slots[id].filters[field]; });
          }
          panel.repaint();
        });
      });
      // The shown view's own choices (Spaces: its readouts and their lines).
      call(own, "tableOptions", [toggle], null);
      var shown = columns(own, units.profile(AREA, preferences.current())).map(function (column) { return column[0]; });
      colourBy.modes(panel.state).filter(function (mode) { return !boundToColumn(own, mode, shown); })
        .forEach(function (mode) {
          var on = legend.mode === mode.name;
          toggle("Colour by " + mode.label, on, function () { colourBy.activate(panel.state, on ? null : mode.name); });
        });
    }
    menu.root.classList.add("phc-table-options");
    return menu;
  }

  /* Collapse all and Expand all act on the tree, because this screen groups by the tree rather than
     by a field: a Zone is the group its rows sit in. */
  function expansion(state) {
    return {
      collapseAll: function () { state.zoneKeys.forEach(function (key) { state.expanded[key] = false; }); },
      expandAll: function () { state.zoneKeys.forEach(function (key) { state.expanded[key] = true; }); },
      canCollapse: function () { return state.zoneKeys.some(function (key) { return open(state, key); }); },
      canExpand: function () { return state.zoneKeys.some(function (key) { return !open(state, key); }); }
    };
  }

  /* As the table opens a row: a Zone open and every row beneath it shut, until the user says otherwise. */
  function open(state, key) {
    if (Object.prototype.hasOwnProperty.call(state.expanded, key)) return state.expanded[key];
    return state.topKeys[key] === true;
  }

  function columns(own, profile) {
    var depth = units.profile(ZoneCells.GROUND_DEPTH, preferences.current()), shown = zoneFields(own);
    return [["actions", "Actions"], ["hierarchy", "Hierarchy"]].concat(call(own, "leadingColumns", [profile], []),
      [["name", "Name"]], ZoneCells.columns(depth).filter(function (column) { return shown.indexOf(column[0]) >= 0; }),
      call(own, "columns", [profile], []));
  }

  /* ---------------------------------------------------------------- rows */

  /* One row per Zone occurrence from the Zones read, each followed by the rows the view puts beneath it.
     A Zone row is keyed by the path that names one Zone occurrence, not by the Zone's record id: a copied Zone
     Group shares its original's dictionary until the copy is repaired, so two occurrences can carry one id,
     and the Zones read reports both and says so in `state`. Keying on the id would put the copy's rows under
     the original's and drop one Zone off the screen entirely. */
  function project(zones, own) {
    var rows = [];
    zones.forEach(function (zone) {
      var key = JSON.stringify(["Zone", zone.reference.zone_path]), record = { id: key, name: zone.values.name,
        zone: zone, state: zone.state };
      var row = { key: key, parent: null, tier: "Zone", depth: 0, record: call(own, "zoneRecord", [record], record) };
      rows.push(row);
      rows.push.apply(rows, call(own, "children", [row], []));
    });
    // Top-level rows the view adds after the Zones (a group of records outside every Zone); they carry no Zone.
    call(own, "extraRows", [], []).forEach(function (row) {
      rows.push(row);
      rows.push.apply(rows, call(own, "children", [row], []));
    });
    return rows;
  }

  function occurrence(path) {
    return JSON.stringify(path || []);
  }

  function value(own, row, field, profile) {
    if (field === "name") return row.record.name;
    if (ZONE_FIELDS.indexOf(field) >= 0) return "";
    return call(own, "value", [row, field, profile], "");
  }

  /* What is wrong with the Zone comes before what the view says of it. A Zone that shares its identity with a
     copy is the first thing to say, because every edit made here names one occurrence and nothing else on the
     screen tells the user there are two. */
  function marker(own, row) {
    var trouble = ZONE_STATES[row.record.state];
    if (trouble) return { text: trouble.text, icon: trouble.icon, tooltip: (trouble.tooltip + " " +
      independenceHint(row.record.zone && row.record.zone.independence)).trim() };
    return call(own, "zoneMarker", [row], null);
  }

  /* What the user can do about a shared Zone: the row's Make independent action, or what comes first. */
  function independenceHint(independence) {
    if (!independence) return "";
    return independence.available ? "Make it independent from its row's actions." : independence.reason || "";
  }

  /* The view's row actions, with Make independent on a Zone row before the view's own Zone actions. */
  function actions(own, row) {
    var items = call(own, "actions", [row], []).slice();
    if (row.depth !== 0 || !row.record.zone) return items;
    var independence = row.record.zone.independence;
    if (independence && independence.available) {
      items.push({ id: "independent", icon: "repair", label: "Make " + row.record.name + " independent" });
    }
    return items.concat(call(own, "zoneActions", [row], []));
  }

  /* ---------------------------------------------------------------- gestures */

  /* A Locate outline outlasts a view switch, so its clear reaches whichever view drew it; each answers
     whether it cleared anything. */
  function clearLocates(state) {
    return Object.keys(state.slots).filter(function (id) {
      return call(state.slots[id], "clearLocate", [], false);
    }).length > 0;
  }

  /* A press in the panel outside a Locate control clears Locate's outline. */
  document.addEventListener("pointerdown", function (event) {
    if (!screen) return;
    for (var node = event.target; node; node = node.parentNode) {
      if (node.getAttribute && node.getAttribute("data-row-action") === "locate") return;
      // Switching views keeps the outline.
      if (node.classList && node.classList.contains("phc-view-tabs")) return;
    }
    clearLocates(screen);
  }, true);

  /* Escape unwinds one layer on this screen: an open bubble or menu takes its own first (it marks the event
     handled), then the shown view's, then an outline another view's Locate left. */
  document.addEventListener("keydown", function (event) {
    var own = screen && active(screen);
    if (event.key !== "Escape" || event.defaultPrevented || !own || !panel.state ||
        panel.state.ui.activeTab !== "overview") return;
    if (Array.from(document.querySelectorAll("dialog")).some(function (dialog) { return dialog.open; })) return;
    if (call(own, "escape", [], false) || clearLocates(screen)) event.preventDefault();
  });

  /* Make Zone independent names the occurrence it acts on and what it costs before it writes. Either
     occurrence can be the one that takes the new identity, and both can carry the same name, so the
     dialog offers the shown view's Locate, when it has one, and says what the other keeps. */
  function confirmIndependent(state, row) {
    var reason = draftReason(state);
    if (reason) return refuse(reason);
    var own = active(state), zone = row.record.zone, retired = zone.independence.retired_pairs;
    var dialog = state.independenceDialog;
    if (!dialog) {
      dialog = state.independenceDialog = ui.formDialog("", function () { dialog.closeModal(); });
      document.body.appendChild(dialog);
    }
    var consequence = "This occurrence gets its own Faces and a new identity. The other occurrence keeps the " +
      "current identity." + (retired ? " " + retired + (retired === 1 ? " Surface pair on this occurrence's " +
        "Faces is" : " Surface pairs on this occurrence's Faces are") + " retired; run Solve adjacencies " +
        "again afterwards." : "");
    var cancel = ui.button("Cancel", function () { dialog.closeModal(); });
    var footer = ui.actionRow(cancel,
      ui.button("Make independent", function () {
        dialog.closeModal();
        if (state.disposed || state.edits.busy()) return;
        state.edits.run("ph_composer.zones.make_independent", { zone_path: zone.reference.zone_path });
        panel.repaint();
      }));
    if (own.view.locate) {
      footer.insertBefore(ui.button("Locate", function () { call(own, "locate", [row]); }), footer.firstChild);
    }
    dialog.replaceChildren(ui.element("h2", "", "Make " + row.record.name + " independent"),
      ui.element("p", "", consequence), footer);
    dialog.openModal();
    cancel.focus();
  }

  /* ---------------------------------------------------------------- paint */

  /* The page header is built once a session and repainted in place, so a press on any of its controls
     (Classify faces, the gear) keeps its focus through the snapshot that follows.
     It holds the authoring toolbar and the shown view's settings. Make Zone lives in SketchUp's context menu;
     view controls stay in the control row. */
  function header(state, pane) {
    if (!state.header) {
      var parts = { toolbar: ui.element("div", "phc-toolbar"), settings: ui.element("div", "phc-view-settings") };
      parts.toolbar.setAttribute("role", "toolbar");
      parts.toolbar.setAttribute("aria-label", "Zone and Face tools");
      parts.toolbar.appendChild(panel.region(pane, "actions"));
      parts.page = ui.pageHeader({ title: "Zones", actions: [parts.toolbar, parts.settings] });
      state.header = parts;
    }
    // A toolbar no section has filled yet would draw as an empty outlined box.
    state.header.toolbar.hidden = !state.header.toolbar.querySelector("button, input, select");
    var settings = call(active(state), "settings", [], null), holder = state.header.settings;
    if (holder.children[0] !== (settings || undefined) || holder.children.length > 1) {
      if (settings) holder.replaceChildren(settings); else holder.replaceChildren();
    }
    return state.header;
  }

  function render(root, state, send) {
    var zones = snapshot.value(state, "ph_composer.zones.overview") || { zones: [], make_zone: null };
    var screenState = forSession(state.session, send), profile = units.profile(AREA, preferences.current());
    var host = screenState.host;
    screenState.send = host.send = send;
    screenState.snapshot = host.snapshot = state;
    screenState.zoneRecords = zones.zones;
    host.gated = Object.create(null);
    zones.zones.forEach(function (zone) {
      if (ZoneCells.gated(zone)) host.gated[occurrence(zone.reference.zone_path)] = true;
    });
    screenState.revision = host.revision = state.revision;
    screenState.optionDialog.consume(state, zoneOptions.read(state));
    if (!root.querySelector(".phc-zone-views")) {
      root.className = "phc-overview";
      root.replaceChildren(ui.element("div", "phc-heading-mount"), ui.element("div", "phc-view-tabs"),
        screenState.controls.root, ui.element("div", "phc-zone-views"));
      screenState.tabsSignature = null;
    }
    settle(screenState, root, state);
    // Every listed view reads each snapshot, shown or not: a hidden view may still have work arriving (a
    // native handoff, a tool that turned on late). Reading may switch views, so the shown one is read after.
    screenState.listed.forEach(function (view) { call(slot(screenState, view), "consume", [state, send]); });
    var handover = screenState.handover;
    screenState.handover = null;
    if (handover && handover.slot === active(screenState)) call(handover.slot, "checkZones", [handover.zones]);
    var own = active(screenState);
    var rows = project(zones.zones, own);
    // A row the view adds may open by default. That is decided once, when the row first appears, so it does
    // not snap shut or open under the user as what it holds changes.
    rows.forEach(function (row) {
      var initial = row.depth === 0 ? null : call(own, "initiallyOpen", [row], null);
      if (initial !== null && !Object.prototype.hasOwnProperty.call(screenState.expanded, row.key)) {
        screenState.expanded[row.key] = initial;
      }
    });
    screenState.edits.consume(state);
    screenState.look.consume(state);
    // Collapse all and Expand all reach every row with rows beneath it.
    var parents = Object.create(null);
    rows.forEach(function (row) { if (row.parent) parents[row.parent] = true; });
    screenState.zoneKeys = rows.filter(function (row) { return parents[row.key]; })
      .map(function (row) { return row.key; });
    screenState.topKeys = Object.create(null);
    rows.forEach(function (row) { if (row.depth === 0) screenState.topKeys[row.key] = true; });
    // The pane's tools (whatever sections registered there) end this screen's control row. Found before the
    // row changes hands, so a new session's row inherits them instead of leaving them in the old one.
    var tools = panel.region(root.closest("[data-pane]").getAttribute("data-pane"), "tools");
    var row = root.children[2];
    if (row !== screenState.controls.root) {
      root.insertBefore(screenState.controls.root, row);
      root.removeChild(row);
    }
    if (screenState.options.root.parentNode !== screenState.controls.root) {
      screenState.controls.root.insertBefore(screenState.options.root, screenState.controls.count.nextSibling);
    }
    // Only the shown view's tools stand in the row, after Table options.
    Object.keys(screenState.slots).forEach(function (id) {
      var tools = screenState.slots[id].toolbar;
      if (screenState.slots[id] !== own && tools.parentNode) tools.parentNode.removeChild(tools);
    });
    if (own.toolbar.parentNode !== screenState.controls.root) {
      screenState.controls.root.insertBefore(own.toolbar, screenState.options.root.nextSibling);
    }
    if (tools.parentNode !== screenState.controls.root) screenState.controls.root.appendChild(tools);
    var heading = header(screenState, root.closest("[data-pane]").getAttribute("data-pane")).page.root;
    var headingMount = root.querySelector(".phc-heading-mount");
    if (heading.parentNode !== headingMount) headingMount.replaceChildren(heading);
    // Set before the tree paints, so the selection bar never works from an earlier pass if painting fails.
    screenState.rows = rows;
    screenState.zoneCells.refresh(rows.filter(zoneRow), state);
    call(own, "prepare", [rows, state]);
    screenState.controls.filter.placeholder = own.view.placeholder || "Zone";
    paintTable(own, rows, screenState, profile);
    paintFindings(root, zones.findings || []);
  }

  /* What belongs to no Zone row, such as a Zone made into a component, collects below the table with its way
     back. It is the read's own words, so it says what to do without naming a code. */
  function paintFindings(root, findings) {
    var list = root.querySelector(".phc-zone-findings");
    if (!list) {
      list = ui.element("div", "phc-zone-findings");
      list.setAttribute("role", "status");
      root.appendChild(list);
    }
    list.replaceChildren.apply(list, findings.map(function (finding) {
      return ui.element("p", "phc-zone-finding", finding.message);
    }));
    list.hidden = !findings.length;
  }

  /* The shown view's selection bar floats over the bottom of its table. */
  function renderBar(root, state) {
    var overview = document.querySelector("[data-section='ph_composer.overview']");
    root.hidden = true;
    var own = screen && screen.session === state.session && active(screen);
    if (screen) screen.bar = null;
    if (!own || !overview) return;
    screen.bar = call(own, "selectionBar", [overview], null);
    place(own, screen.bar);
  }

  /* The table takes the height its pane leaves, however the tabs and the control row wrap, so the tab does
     not scroll and a floating selection bar sits at the pane's visible bottom. Below MIN_MOUNT the pane
     scrolls instead. Where the floating bar would cover the table's header, it docks beneath the table and
     the table is fitted again around it. */
  function place(own, bar) {
    var mount = own.mount, pane = mount.closest(".panel-panes");
    if (!pane || !mount.closest("[data-pane]") || !mount.getClientRects().length) return;
    var refit = function () { fit(mount, pane); }, head = mount.querySelector("thead");
    if (bar) bar.reserve(mount, head ? head.offsetHeight : 0, refit); else refit();
  }

  /* Below the table: the rest of the overview (a docked bar) and any section another feature adds to the pane. */
  function fit(mount, pane) {
    var paneBox = pane.getBoundingClientRect(), box = mount.getBoundingClientRect(), end = box.bottom;
    Array.prototype.forEach.call(mount.closest("[data-pane]").children, function (part) {
      if (part.getClientRects().length) end = Math.max(end, part.getBoundingClientRect().bottom);
    });
    var room = pane.clientHeight - (box.top - paneBox.top + pane.scrollTop) - (end - box.bottom);
    mount.style.maxHeight = Math.max(MIN_MOUNT, Math.floor(room)) + "px";
  }

  /* A top-level row for one Zone occurrence; a view's group row has no Zone. */
  function zoneRow(row) {
    return row.depth === 0 && Boolean(row.record.zone);
  }

  /* The view controls order and filter Zones, because a Zone is what the tree is built from; the view's rows
     follow it, ordered among themselves by the same field. They project the Zone records, and `rows` tells
     them how a view's row traces back to the Zone that decides whether it shows. Filtering reads the view's
     rows too, so a search for "Ground" keeps the Zone that has a Ground Face. */
  function paintTable(own, rows, state, profile) {
    var zoneRows = rows.filter(zoneRow), viewFields = own.view.filteredFields || {};
    // A view's group rows (records outside every Zone) are not Zones: the controls neither count nor order them,
    // and they follow the Zones in any sort.
    var groupRows = rows.filter(function (row) { return row.depth === 0 && !row.record.zone; });
    var byId = Object.create(null);
    zoneRows.concat(groupRows).forEach(function (row) { byId[row.record.id] = row; });
    var projection = state.controls.project(zoneRows.map(function (row) { return row.record; }), {
      id: function (record) { return record.id; },
      value: function (record, field) {
        if (field === "name") return record.name;
        var viewValue = call(own, "sortValue", [record, field], undefined);
        if (viewValue !== undefined) return viewValue;
        if (viewFields[field] || !record.zone) return null;
        return field === "building_segment" || field === "level" ?
          zoneOptions.label(zoneOptions.read(state.snapshot), record.zone, field) : record.zone.values[field];
      },
      search: function (record) { return searchText(own, record, state); },
      // A Zone shows while its own values pass the Zone filters and the view's filters pass it too; a view's
      // row shows while the view says it does.
      columnMatch: function (record, filters) {
        return zoneMatches(own, record, filters) && call(own, "zoneMatch", [record, filters], true);
      },
      rowMatch: function (row, filters) { return call(own, "rowMatch", [row, filters], true); },
      queryMatch: function (row, query, record) { return queryMatch(own, row, query, record, state); },
      rows: function () { return rows; }
    });
    var labels = Object.create(null), shownColumns = columns(own, profile);
    shownColumns.forEach(function (column) { labels[column[0]] = column[1]; });
    var filters = state.controls.columnFilters, hidden = groupedHidden(own, rows, groupRows, projection, state);
    var shown = ordered(own, projection.records.concat(groupRows.map(function (row) { return row.record; })), byId,
      rows, state.controls);
    var visible = shown.filter(function (row) { return !hidden(row); });
    // Only column Show filters affect the viewport. Text search and collapsed rows remain table navigation.
    // A view's group rows join the mask as their rows join the table: by the view's filters.
    var matchingPaths = state.controls.filterCount() ? zoneRows.concat(groupRows).reduce(function (all, row) {
      if (!zoneMatches(own, row.record, filters) || !call(own, "zoneMatch", [row.record, filters], true)) return all;
      return all.concat(call(own, "viewportPaths", [row.record, filters],
        row.record.zone ? [row.record.zone.reference.zone_path] : []));
    }, []).sort(function (a, b) { return ui.compareText(JSON.stringify(a), JSON.stringify(b)); }) : null;
    colourBy.filter(state.snapshot, matchingPaths);
    var check = call(own, "check", [{ visible: visible, zoneRows: visible.filter(zoneRow), allZoneRows: zoneRows,
      filters: filters }], null);
    var parents = Object.create(null);
    rows.forEach(function (row) { if (row.parent) parents[row.parent] = true; });
    tables.table(own.mount, rows, {
      // Sized so the whole table shows at the panel's usual width; labels have their own band above the icons,
      // and the user can still drag any column wider.
      defaultWidths: Object.assign({}, ZONE_WIDTHS, own.view.widths || {}),
      tree: true, tiers: own.view.tiers, rows: shown, columns: shownColumns,
      painted: function () { call(own, "painted"); },
      // Shutting a row while the view holds a draft could hide it; opening never does.
      mayToggle: function (row, opening) {
        var reason = opening ? null : call(own, "draftReason", [], null);
        if (reason) refuse(reason);
        return !reason;
      },
      expanded: state.expanded,
      expandable: function (row) { return Boolean(parents[row.key]); },
      decorate: function (td, row, field) { call(own, "decorate", [td, row, field]); },
      columnWidths: own.columnWidths, visibleCount: projection.visibleCount + hidden.groupsShown,
      disabled: state.edits.busy(),
      empty: zoneRows.length || groupRows.length ? "No Zones match this filter." :
        "No Zones yet. Select geometry in SketchUp, then right-click and choose Make Zone.",
      value: function (row, field) { return value(own, row, field, profile); },
      cell: function (td, row, field) {
        return (row.depth !== 0 || Boolean(row.record.zone)) && state.zoneCells.render(td, row, field) ||
          call(own, "cell", [td, row, field], false);
      },
      marker: function (row) { return marker(own, row); }, actions: function (row) { return actions(own, row); },
      rowHidden: hidden, hiddenColumns: own.hiddenColumns, revealRowActions: true,
      check: check || undefined,
      headerActions: function (field) { return headerActions(state, own, field, labels[field]); },
      inspect: function (row) { call(own, "inspect", [row]); },
      columnResize: function (field, width) {
        if (field === null) own.columnWidths = {};
        else if (width === null) delete own.columnWidths[field];
        else own.columnWidths[field] = width;
      },
      action: function (row, item, control) {
        if (item.id === "independent") confirmIndependent(state, row);
        else call(own, "action", [row, item, control]);
      },
      selected: function (row) { return call(own, "selected", [row], false); }
    });
  }

  /* Which rows the filters hide: the controls' answer for a Zone and its rows, and the same rules (the text
     filter and the view's column filters) for a view's group row and its rows, which the controls do not hold.
     `groupsShown` counts the group rows that show. */
  function groupedHidden(own, rows, groupRows, projection, state) {
    var root = Object.create(null), shown = Object.create(null), records = Object.create(null), groupsShown = 0;
    var query = (state.controls.filter.value || "").trim().toLocaleLowerCase();
    var filters = state.controls.columnFilters, filterCount = state.controls.filterCount();
    rows.forEach(function (row) { root[row.key] = row.parent ? root[row.parent] : row.key; });
    groupRows.forEach(function (row) {
      var record = records[row.key] = row.record;
      shown[row.key] = (!query || searchText(own, record, state).toLocaleLowerCase().indexOf(query) >= 0) &&
        (!filterCount || zoneMatches(own, record, filters) && call(own, "zoneMatch", [record, filters], true));
      if (shown[row.key]) groupsShown += 1;
    });
    function hidden(row) {
      var top = root[row.key];
      if (!Object.prototype.hasOwnProperty.call(shown, top)) return projection.hidden(row);
      if (!shown[top]) return true;
      if (query && row.parent && !queryMatch(own, row, query, records[top], state)) return true;
      return Boolean(filterCount && row.parent && !call(own, "rowMatch", [row, filters], true));
    }
    hidden.groupsShown = groupsShown;
    return hidden;
  }

  /* Whether a Zone's own values pass the Zone filters; the view's fields are the view's to judge. */
  function zoneMatches(own, record, filters) {
    var viewFields = own.view.filteredFields || {};
    return Object.keys(filters).every(function (field) {
      // A group row with no Zone passes only the view's filters: a Zone filter names Zones.
      return viewFields[field] || Boolean(record.zone) && filters[field].indexOf(filterValue(record.zone, field)) >= 0;
    });
  }

  /* A row beneath a Zone the text filter matched shows while the Zone's own text matches, or else while the
     view says the row matches (a Zone matched only through one of its Spaces lists just that Space). */
  function queryMatch(own, row, query, record, state) {
    return searchText(own, record, state, false).toLocaleLowerCase().indexOf(query) >= 0 ||
      call(own, "queryMatch", [row, query, record], true);
  }

  /* A Zone row's text for the filter: its own name, Building-Segment and Level, and unless `withView` is false,
     what the view adds (`search`). */
  function searchText(own, record, state, withView) {
    var options = zoneOptions.read(state.snapshot);
    return [record.name].concat(record.zone ? [zoneOptions.label(options, record.zone, "building_segment"),
      zoneOptions.label(options, record.zone, "level")] : [],
    withView === false ? [] : [call(own, "search", [record], "")]).join(" ");
  }

  /* The Zone order the controls settled on, each Zone followed by its own rows in the order the view gives
     them for the sorted column. */
  function ordered(own, records, byId, rows, controls) {
    var children = Object.create(null), field = controls.sortField(), direction = controls.sortDirection();
    rows.forEach(function (row) {
      if (row.parent) (children[row.parent] = children[row.parent] || []).push(row);
    });
    function withChildren(row) {
      var list = children[row.key] || [];
      return call(own, "sort", [list, field, direction], list).reduce(function (all, child) {
        return all.concat(withChildren(child));
      }, [row]);
    }
    return records.reduce(function (all, record) { return all.concat(withChildren(byId[record.id])); }, []);
  }

  // First in its pane: the Zone tree is the screen's work surface, and the palette and column menus
  // are controls that act on what it shows.
  // A refused tab change restates its reason through `refuse`, so a held Zone edit's notice offers Cancel too.
  panel.navigationGuard("ph_composer.overview", function () { return draftReason(screen); },
    function () { var reason = draftReason(screen); if (reason) refuse(reason); });
  // A refused Zone write says what to do about a shared Zone rather than naming its duplicated id.
  panel.outcomeText(function (result) {
    if (!screen || result.session !== screen.session || !screen.zoneCells.owns(result.request_id)) return null;
    return ZoneCells.refusalText(result.outcome);
  }, { owner: "ph_composer.zones" });
  /* Another tab can open this one on a view (`panel.navigate("overview", { view })`) and, with `check`, with
     rows checked and, with `locate: true`, framed, as the Assemblies tab's "Select faces using" does. The
     named view is shown first, through the view row's guards; `intent.viewShown` says whether it was, and a
     refused switch applies nothing. */
  panel.section("ph_composer.overview", render, { order: 10, onNavigate: function (root, intent) {
    if (!screen) return;
    if (intent.view) {
      intent.viewShown = intent.view === screen.viewId ||
        Boolean(screen.tabs && screen.slots[intent.view] && screen.tabs.select(intent.view));
      if (!intent.viewShown) return;
    }
    if (intent.check) call(active(screen), "navigate", [intent]);
    panel.repaint();
  } });
  panel.workedOn("ph_composer.zones", "overview");
  panel.section("ph_composer.zones.selection_bar", renderBar, { order: 1000 });
  if (window.addEventListener) window.addEventListener("resize", function () {
    var own = screen && active(screen);
    if (own) place(own, screen.bar);
  });
});
