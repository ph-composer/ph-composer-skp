/* The Mechanical tab's systems and their tables. A system is one subtab (Ventilation, later Heat Pumps, Hot Water,
   Pumps, Fans and Electric Heating); a table is one pill beneath it (Ventilation's Ventilators, later Ducting).
   Each family registers its own from its file, so adding one edits no list here or in the tab.

   system({ id, label, order })
   table({ system, id, label, order, build(surface, context) }), where `build` answers the table's view:
   { render(state, shown), guard(), dispose(), create (the page header's primary action or null),
     navigate(intent) (optional) }. `context` is { session, send }.
   Ids are dotted names under the feature's id, so the choice can be remembered as a display preference. */
PhComposerUI.define("features/mechanical/systems", [], function () {
  "use strict";
  var systems = [], tables = [];

  function byOrder(a, b) { return a.order - b.order || (a.label < b.label ? -1 : a.label > b.label ? 1 : 0); }
  function system(entry) {
    if (!entry.id || systems.some(function (known) { return known.id === entry.id; })) {
      throw new Error("A Mechanical system needs a unique id.");
    }
    systems.push(Object.assign({ order: 100 }, entry));
    systems.sort(byOrder);
  }
  function table(entry) {
    if (!entry.id || !entry.system || typeof entry.build !== "function" ||
      tables.some(function (known) { return known.id === entry.id; })) {
      throw new Error("A Mechanical table needs a unique id, its system and a build function.");
    }
    tables.push(Object.assign({ order: 100 }, entry));
    tables.sort(byOrder);
  }
  /* The systems with at least one table, each with its tables in order. */
  function list() {
    return systems.map(function (entry) {
      return { id: entry.id, label: entry.label, tables: tables.filter(function (candidate) {
        return candidate.system === entry.id;
      }) };
    }).filter(function (entry) { return entry.tables.length > 0; });
  }
  return { system: system, table: table, list: list };
});
