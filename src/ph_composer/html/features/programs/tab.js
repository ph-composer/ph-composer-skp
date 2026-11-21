/* The Programs tab: one page header over three peer subtabs, Programs, Schedules and Equipment Sets, each
   a record editor with one right sidebar (features/programs/record_page.js). Records come from the snapshot
   sections `ph_composer.programs.programs`, `schedules` and `equipment_sets`, each its collection's `all` read
   (features/programs/declarations.rb); how many Zones use a Program or Equipment Set comes from the occupancy read
   the Zones / Programs view shows. Every write is one registered Programs action and one Undo step, one at a time;
   a refusal is the panel's notice. */
PhComposerUI.define("features/programs/tab", ["panel", "subtabs", "workspace", "request", "snapshot",
  "features/programs/record_page", "features/programs/program_editor", "features/programs/record_bodies"],
function (panel, Subtabs, ui, requests, snapshot, RecordPage, ProgramEditor, bodies) {
  "use strict";
  var TAB = "programs", PREFIX = "ph_composer.programs";
  var OCCUPANCY = PREFIX + ".occupancy";
  var SCHEDULE_GROUPS = ["fractional", "activity", "temperature", "ventilation"].map(function (type, index) {
    return { id: String.fromCharCode(97 + index) + "-" + type, label: bodies.TYPES[type], type: type };
  });
  var views = Object.create(null), current;

  function plural(count, noun) { return count + " " + noun + (count === 1 ? "" : "s"); }

  /* A record copied from a library says which. */
  function librarySource(row) {
    var source = row.values.source;
    return source && source.kind === "library" ? "From " + (source.library_name || source.library_id || "a library") :
      null;
  }

  var KINDS = {
    programs: { id: "programs", label: "Program", plural: "Programs", library: "programs",
      reserved: "pgm_PHCDEFAULT01", resetKind: "program",
      badge: function (row) { return row.default ? "Unassigned Zones use this" : librarySource(row); },
      useCount: function (row, context) { return context.zoneCount(this, row.id); },
      usedText: function (row, zones) {
        return row.values.name + (row.default ? " is the Model's default Program" : " is in use") +
          (zones ? ", on " + plural(zones, "Zone") : "") + ".";
      } },
    schedules: { id: "schedules", label: "Schedule", plural: "Schedules", groups: SCHEDULE_GROUPS, useNoun: "load",
      createValues: { type: "fractional" },
      group: function (row) {
        return SCHEDULE_GROUPS.filter(function (entry) { return entry.type === row.values.type; })[0].id;
      },
      sameType: function (other, row) { return other.values.type === row.values.type; },
      badge: librarySource,
      usedText: function (row) { return row.values.name + " is used by " + plural(row.use_count, "load") + "."; } },
    equipment_sets: { id: "equipment_sets", label: "Equipment Set", plural: "Equipment Sets",
      reserved: "eqs_PHCDEFAULT01", resetKind: "equipment_set",
      badge: function (row) { return row.default ? "Dwellings without a Set use this" : librarySource(row); },
      useCount: function (row, context) { return context.zoneCount(this, row.id); },
      usedText: function (row, zones) {
        return row.values.name + (row.default ? " is the Model's default Equipment Set" : " is in use") +
          (zones ? ", on " + plural(zones, "Zone") : "") + ".";
      } }
  };

  /* ---------------------------------------------------------------- the page */

  function View(root, state, send) {
    var self = this, page = views[state.session] || (views[state.session] = {});
    this.session = state.session; this.send = send; this.root = root;
    root.replaceChildren();
    this.channel = requests.channel(state.session, send, "programs-tab");
    this.header = ui.pageHeader({ title: "Programs" });
    root.appendChild(this.header.root);
    var host = { session: state.session, send: send, changed: function () { panel.repaint(); },
      busy: function () { return self.channel.busy(); }, run: function (name, params, done) {
        return self.run(name, params, done);
      }, refuse: function (text) { panel.notify(text, "warning"); }, repaint: function () { panel.repaint(); },
      prefix: function (kind) { return PREFIX + "." + kind.id; } };
    var made = { programs: function (owner) { return self.programBody(owner); },
      schedules: function () { return new bodies.ScheduleBody(); },
      equipment_sets: function () { return new bodies.SetBody(); } };
    this.pages = {};
    Object.keys(KINDS).forEach(function (id) { self.pages[id] = new RecordPage(KINDS[id], host, made[id]); });
    this.tabs = new Subtabs({ label: "Programs", state: page, stateKey: "tab", tabs: [
      { id: "programs", label: "Programs", surface: this.pages.programs.root },
      { id: "schedules", label: "Schedules", surface: this.pages.schedules.root },
      { id: "equipment_sets", label: "Equipment Sets", surface: this.pages.equipment_sets.root }],
    guard: function () { return self.guard(); },
    refused: function (reason) { panel.notify(reason, "warning"); },
    changed: function () { panel.repaint(); } });
    root.appendChild(this.tabs.root);
    Object.keys(this.pages).forEach(function (id) { root.appendChild(self.pages[id].root); });
  }

  /* The Program editor, whose edits change one load each and whose Schedule slots open or make Schedules. */
  View.prototype.programBody = function (owner) {
    var self = this;
    return new ProgramEditor({
      update: function (row, load, values, expected) {
        var change = {}, guard = {};
        change[load] = values; guard[load] = expected;
        return owner.update(row, change, guard);
      },
      refuse: function (text) { panel.notify(text, "warning"); },
      openSchedule: function (id) { self.open("schedules", id); },
      newSchedule: function (type, done) {
        self.run(PREFIX + ".schedules.create", { values: { type: type } }, function (outcome) {
          var id = outcome.value && outcome.value.id;
          // The Program names it in a second step, once a snapshot carries it, so that step is read at its revision.
          if (id) self.after = { id: id, run: function () { done(id); } };
          return null;
        });
      }
    });
  };

  /* Opens one record on its subtab. */
  View.prototype.open = function (tab, id) {
    if (this.guard()) { panel.notify(this.guard(), "warning"); return; }
    this.pages[tab].active = id;
    this.tabs.select(tab);
    panel.repaint();
  };

  View.prototype.guard = function () {
    var pages = this.pages, found = null;
    Object.keys(pages).some(function (id) { return Boolean(found = pages[id].guard()); });
    return found;
  };

  /* One write at a time; `done(outcome)` may answer words for a success notice. */
  View.prototype.run = function (name, params, done) {
    if (this.channel.busy()) { panel.notify("Wait for the last change to finish.", "warning"); return false; }
    this.channel.run(name, params, { onDone: function (outcome) {
      var words = done ? done(outcome) : null;
      if (words) panel.notify(words, "success");
    } });
    panel.repaint();
    return true;
  };

  /* What every page reads from one snapshot. */
  View.prototype.context = function (state) {
    var sections = {}, missing = null;
    Object.keys(KINDS).forEach(function (id) {
      var value = snapshot.value(state, PREFIX + "." + id);
      sections[id] = value ? value.records : [];
      if (!value && !missing) {
        var outcome = snapshot.section(state, PREFIX + "." + id);
        missing = outcome && outcome.message ? outcome.message : "Programs are not available in this model.";
      }
    });
    var occupancy = snapshot.value(state, OCCUPANCY) || { zones: [], choices: {} };
    var schedules = {};
    sections.schedules.forEach(function (row) { schedules[row.id] = row; });
    var enabled = !missing && !this.channel.busy();
    return {
      enabled: enabled, available: !missing, unavailable: missing,
      hasSchedule: function (id) { return Boolean(schedules[id]); },
      records: function (kind) {
        return sections[kind.id].slice().sort(function (a, b) { return ui.compareText(a.values.name, b.values.name); });
      },
      // Zones using a Program, by the Program each works out to; or an Equipment Set, by the Set each works out to
      // (its Dwelling's, a single dwelling's house's, its own, else the Model's default), in residential Segments
      // only, since PHX reads no devices elsewhere.
      zoneCount: function (kind, id) {
        var fallback = (occupancy.choices || {}).default_equipment_set_id, nonResidential = {};
        (occupancy.building_segments || []).forEach(function (segment) {
          if (segment.category && segment.category !== "residential") nonResidential[segment.id] = true;
        });
        return (occupancy.zones || []).filter(function (zone) {
          if (kind.id === "programs") return zone.program_id === id;
          return !nonResidential[zone.building_segment_id] && (zone.equipment_set_id || fallback) === id;
        }).length;
      },
      bodyContext: function (kind, row) {
        return { zones: kind.useCount ? kind.useCount(row, this) : row.use_count, schedules: schedules };
      }
    };
  };

  View.prototype.render = function (state) {
    this.channel.consume(state);
    var context = this.context(state), self = this;
    Object.keys(this.pages).forEach(function (id) {
      self.pages[id].render(state, context);
    });
    if (this.after && !this.channel.busy() && context.hasSchedule(this.after.id)) {
      var next = this.after; this.after = null; next.run();
    }
  };

  View.prototype.dispose = function () {
    var pages = this.pages;
    Object.keys(pages).forEach(function (id) { pages[id].dispose(); });
    this.tabs.dispose();
  };

  function render(root, state, send) {
    if (!root._view || root._view.session !== state.session) {
      if (root._view) root._view.dispose();
      root._view = new View(root, state, send);
    }
    current = root._view;
    current.render(state);
  }

  panel.navigationGuard(TAB, function (next) { return next === TAB || !current ? null : current.guard(); });
  // Programs' records are worked on here, so the Export tab's Programs findings offer this tab.
  panel.workedOn(PREFIX, TAB);
  panel.section(TAB, render, { pane: TAB });
  return { render: render, KINDS: KINDS };
});
